"""Silent-only real-device ring audit. Explicit serial; original data backed up first."""
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('SHIFTBELL_RING_AUDIT_OUT', str(ROOT / 'build/ring_localization_2026-10-05')))
SERIAL = os.environ['SHIFTBELL_AUDIT_SERIAL']
assert SERIAL == 'R5KL20DHWAE', 'Re-audit device authorization before changing serial'
PKG = 'com.hwani1103.shiftbell.dev'
ADB = ['C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe', '-s', SERIAL]
os.environ['SHIFTBELL_AUDIT_OUT'] = str(OUT)
os.environ['SHIFTBELL_AUDIT_VM_PORT'] = '58182'
from usb_audit_device import connect_vm, evaluate, capture, tap_text

def adb(*args, data=None):
    p = subprocess.run(ADB + list(args), input=data, capture_output=True, timeout=60)
    if p.returncode: raise RuntimeError(p.stderr.decode(errors='replace'))
    return p.stdout

def launch():
    adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    adb('shell', 'wm', 'dismiss-keyguard')
    adb('shell', 'am', 'start', '-n', PKG + '/com.hwani1103.shiftbell.MainActivity')
    time.sleep(3)
    connect_vm()

def call(name, body, library='services/database_service.dart'):
    return evaluate(name, library, ('(() async {' + body + '})()').replace('\n',' '), timeout=60)

def state(name, alarm_id):
    return json.loads(call(name, '''final db=await DatabaseService.instance.database;
      return jsonEncode({'ringing': await DatabaseService.platform.invokeMethod<bool>('isAlarmRinging',{'alarmId':%d}),
      'alarms':await db.query('alarms',where:'id=?',whereArgs:[%d]),
      'history':await db.query('alarm_history',where:'alarm_id=?',whereArgs:[%d])});''' % (alarm_id, alarm_id, alarm_id)))

def fixture(name, minutes=1, seconds=10):
    result = json.loads(call(name, '''final db=await DatabaseService.instance.database;
      await db.update('alarm_types',{'sound_file':'silent','volume':0.0,'vibration_strength':0,'duration':%d});
      final at=DateTime.now().add(const Duration(seconds:%d));
      final alarm=Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',date:at,type:'custom',alarmTypeId:3);
      final id=await DatabaseService.instance.insertAlarm(alarm);
      await DatabaseService.platform.invokeMethod('scheduleNativeAlarm',{'id':id,'timestamp':at.millisecondsSinceEpoch,'label':'Silent audit','soundType':'silent'});
      return jsonEncode({'id':id,'at':at.toIso8601String(),'duration':%d});''' % (minutes, seconds, minutes)))
    (OUT/(name+'.json')).write_text(json.dumps(result),encoding='utf-8')
    return result

def notification_granted(granted):
    adb('shell','pm','grant' if granted else 'revoke',PKG,'android.permission.POST_NOTIFICATIONS')

def overlay(granted):
    adb('shell','cmd','appops','set',PKG,'SYSTEM_ALERT_WINDOW','allow' if granted else 'ignore')

def capture_evidence(name):
    capture(name)
    (OUT/(name+'.native.log')).write_bytes(adb('logcat','-d','-v','threadtime','RingDeadline:I','AlarmAction:D','InAppAlarm:D','AlarmOverlay:D','AlarmActivity:D','CustomAlarmReceiver:D','AlarmPlayer:D','*:S'))
    (OUT/(name+'.notifications.txt')).write_bytes(adb('shell','dumpsys','notification','--noredact'))
    (OUT/(name+'.power.txt')).write_bytes(adb('shell','dumpsys','power'))

def wait_ring(name, alarm_id, expected=True, limit=25):
    end=time.monotonic()+limit
    while time.monotonic()<end:
        current=state(name+'_poll',alarm_id)
        if bool(current['ringing']) == expected:return current
        time.sleep(1)
    raise AssertionError((name,expected,current))

def prepare():
    assert (OUT/'original_de.tar').exists() and (OUT/'original_ce.tar').exists()
    target=OUT/'fixture_source';target.mkdir(exist_ok=True)
    with tarfile.open(OUT/'original_de.tar') as archive:
        for entry in archive.getmembers():
            if entry.name.startswith('databases/shiftbell.db') and entry.isfile():
                (target/Path(entry.name).name).write_bytes(archive.extractfile(entry).read())
    db=sqlite3.connect(target/'shiftbell.db')
    for table in ['alarms','alarm_history','alarm_creation_log','shift_alarm_templates','alarm_overrides','friends','date_schedules']:
        db.execute('DELETE FROM '+table)
    db.execute("UPDATE alarm_types SET sound_file='silent',volume=0,vibration_strength=0,duration=1")
    db.commit();db.execute('PRAGMA wal_checkpoint(TRUNCATE)');db.close()
    adb('shell','am','force-stop',PKG)
    adb('push',str(target/'shiftbell.db'),'/data/local/tmp/shiftbell_ring_fixture.db')
    adb('shell','chmod','644','/data/local/tmp/shiftbell_ring_fixture.db')
    path='/data/user_de/0/'+PKG+'/databases/shiftbell.db'
    adb('shell','run-as',PKG,'cp','/data/local/tmp/shiftbell_ring_fixture.db',path)
    adb('shell','run-as',PKG,'rm','-f',path+'-wal',path+'-shm')
    prefs=b'<?xml version="1.0" encoding="utf-8"?><map><boolean name="flutter.permissions_requested" value="true"/><boolean name="flutter.welcome_popup_shown" value="true"/><boolean name="flutter.friend_share_enabled" value="false"/></map>'
    adb('shell','-T','run-as',PKG,'tee','shared_prefs/FlutterSharedPreferences.xml',data=prefs)
    launch()
    print('SILENT fixture ready. Original archives preserved.',flush=True)

def button(resource):
    import xml.etree.ElementTree as ET
    adb('shell','uiautomator','dump','/sdcard/shiftbell_ring_ui.xml')
    root=ET.fromstring(adb('exec-out','cat','/sdcard/shiftbell_ring_ui.xml'))
    matches=[n for n in root.iter('node') if n.get('resource-id','').endswith('/'+resource)]
    assert len(matches)==1,(resource,len(matches))
    x1,y1,x2,y2=map(int,re.findall(r'\d+',matches[0].get('bounds')))
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))

def control_count():
    import xml.etree.ElementTree as ET
    adb('shell','uiautomator','dump','/sdcard/shiftbell_ring_ui.xml')
    return sum(n.get('resource-id','').endswith('/dismissButton') for n in
        ET.fromstring(adb('exec-out','cat','/sdcard/shiftbell_ring_ui.xml')).iter('node'))

def notification_action(pattern):
    import xml.etree.ElementTree as ET
    adb('shell','cmd','statusbar','expand-notifications');time.sleep(1)
    adb('shell','uiautomator','dump','/sdcard/shiftbell_ring_ui.xml')
    root=ET.fromstring(adb('exec-out','cat','/sdcard/shiftbell_ring_ui.xml'))
    if not any(re.search(pattern,n.get('text','')) for n in root.iter('node')):
        parents={child:parent for parent in root.iter() for child in parent}
        node=next(n for n in root.iter('node') if n.get('text') in ('알람 울림 중','Alarm ringing'))
        while node in parents:
            candidates=[n for n in node.iter('node') if n.get('resource-id')=='android:id/expand_button']
            if candidates:
                x1,y1,x2,y2=map(int,re.findall(r'\d+',candidates[0].get('bounds')))
                adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(1)
                break
            node=parents[node]
    tap_text(pattern)
    adb('shell','cmd','statusbar','collapse');time.sleep(1)

def finish_case(name, row, expected):
    final=state(name+'_final',row['id'])
    assert final['ringing'] is False, final
    assert [r['dismiss_type'] for r in final['history']]==[expected],final
    if expected!='snoozed':assert not final['alarms'],final
    capture_evidence(name+'_finished')
    (OUT/(name+'_result.json')).write_text(json.dumps(final,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS',name,flush=True)

def auto_case(name, minutes, foreground, notifications, screen_off=False, reenter=False):
    notification_granted(notifications);overlay(False);launch()
    row=fixture(name,minutes,12)
    if not foreground:adb('shell','input','keyevent','KEYCODE_HOME')
    if screen_off:adb('shell','input','keyevent','KEYCODE_SLEEP')
    wait_ring(name,row['id'])
    started=time.monotonic()
    if foreground:assert control_count()==1
    if reenter:
        time.sleep(12);launch();assert control_count()==1
        adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(8);launch();assert control_count()==1
    capture_evidence(name+'_ringing')
    # Preserve a pre-deadline check and wait naturally; never change the clock.
    remaining=minutes*60-(time.monotonic()-started)-22
    if remaining>0:time.sleep(remaining)
    # XML/VM inspection takes seconds on USB. Check the deadline using native
    # timestamps rather than pretending the observed ring start is its start.
    final=wait_ring(name+'_ended',row['id'],False,limit=40)
    print('NATURAL_DURATION',name,round(time.monotonic()-started,2),flush=True)
    finish_case(name,row,'timeout')

def dismiss_case(name, from_notification=False, with_overlay=False, locked=False):
    notification_granted(True);overlay(with_overlay);launch()
    row=fixture(name,3,12)
    if with_overlay or locked:adb('shell','input','keyevent','KEYCODE_HOME')
    if locked:adb('shell','input','keyevent','KEYCODE_SLEEP')
    wait_ring(name,row['id'])
    if locked:
        capture_evidence(name+'_lock')
        adb('shell','input','keyevent','KEYCODE_HOME')
        launch()
    if with_overlay:
        capture_evidence(name+'_external')
        launch()
        # Non-focusable SYSTEM_ALERT_WINDOW is omitted from UIAutomator's
        # active-window tree. Count actual windows: MainActivity + one overlay.
        windows=adb('shell','dumpsys','window','windows').decode(errors='replace')
        own=[line for line in windows.splitlines() if re.search(r'Window #\d+ Window\{',line) and PKG in line]
        assert len(own)==2,own
        (OUT/(name+'_windows.txt')).write_text('\n'.join(own),encoding='utf-8')
    else:assert control_count()==1
    capture_evidence(name+'_card')
    if from_notification or with_overlay:
        notification_action('^(알람 끄기|Dismiss alarm)$')
    else:button('dismissButton')
    time.sleep(1)
    assert control_count()==0
    finish_case(name,row,'swiped')

def snooze_case(name, from_notification=False):
    notification_granted(True);overlay(False);launch()
    row=fixture(name,1,12)
    wait_ring(name,row['id'])
    assert control_count()==1
    if from_notification:
        notification_action('^(5분 후|Snooze 5m)$')
    else:button('snoozeButton')
    time.sleep(1)
    pending=state(name+'_snoozed',row['id'])
    assert pending['ringing'] is False and pending['alarms'][0]['type']=='snoozed',pending
    assert control_count()==0
    capture_evidence(name+'_waiting')
    print('Waiting natural five minutes for',name,flush=True)
    # At the old one-minute deadline, the five-minute reservation must remain.
    time.sleep(65)
    pending=state(name+'_past_old_deadline',row['id'])
    assert pending['ringing'] is False and pending['alarms'][0]['type']=='snoozed',pending
    time.sleep(220)
    wait_ring(name+'_rering',row['id'],limit=25)
    assert control_count()==1
    capture_evidence(name+'_rering')
    button('dismissButton');time.sleep(1)
    final=state(name+'_final',row['id'])
    assert final['ringing'] is False and not final['alarms'],final
    assert len(final['history'])==2,final
    capture_evidence(name+'_finished')
    (OUT/(name+'_result.json')).write_text(json.dumps(final,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS',name,flush=True)

if __name__=='__main__':
    phase=sys.argv[1]
    if phase=='prepare':prepare()
    elif phase=='launch':launch()
    elif phase=='fixture':print(fixture(sys.argv[2],int(sys.argv[3]) if len(sys.argv)>3 else 1),flush=True)
    elif phase=='state':print(state(sys.argv[2],int(sys.argv[3])),flush=True)
    elif phase=='capture':capture_evidence(sys.argv[2])
    elif phase=='matrix':
        cases={
          'no_permissions':lambda:auto_case('no_permissions',1,True,False),
          'background_three':lambda:auto_case('background_three',3,False,True),
          'reentry':lambda:auto_case('reentry',1,False,True,reenter=True),
          'screen_off':lambda:auto_case('screen_off',1,False,False,screen_off=True),
          'app_dismiss':lambda:dismiss_case('app_dismiss'),
          'notification_dismiss':lambda:dismiss_case('notification_dismiss',from_notification=True),
          'external_duplicate':lambda:dismiss_case('external_duplicate',with_overlay=True),
          'lock_home':lambda:dismiss_case('lock_home',locked=True),
          'app_snooze':lambda:snooze_case('app_snooze'),
          'notification_snooze':lambda:snooze_case('notification_snooze',True),
        }
        for name in sys.argv[2:] or cases:
            print('START',name,flush=True);cases[name]()
