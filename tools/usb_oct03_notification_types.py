"""Physical notification dismiss buttons for all three alarm types."""
import re
import time
import xml.etree.ElementTree as ET
from usb_audit_device import adb, evaluate, tap_text, capture, compare_os, OUT
from usb_audit_scenarios import scenario

def ring_id():
    values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as','com.hwani1103.shiftbell.dev','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
    return int(values.get('currently_ringing_alarm_id','-1'))

def expand_own_notification():
    adb('shell','cmd','statusbar','expand-notifications')
    time.sleep(.5)
    adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
    root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
    if any((n.get('text') or n.get('content-desc'))=='알람 끄기' for n in root.iter('node')):
        return
    candidates=[]
    for n in root.iter('node'):
        children=list(n.iter('node'))
        if any((c.get('text') or c.get('content-desc'))=='알람 울림 중' for c in children):
            expand=[c for c in children if (c.get('content-desc') or c.get('text'))=='펼치기']
            if len(expand)==1:
                candidates.append((len(children),expand[0]))
    assert candidates, 'No expand control for this alarm notification'
    node=min(candidates,key=lambda pair:pair[0])[1]
    x,y,r,b=map(int,re.findall(r'\d+',node.get('bounds')))
    adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
    time.sleep(.4)

try:
    for kind in [1,2,3]:
        name=f'notification_type_{kind}'
        ident=int(evaluate(name+'_create','providers/alarm_provider.dart',f"""(() async {{
          final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
          final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
          try{{await n.addAlarm(Alarm(time:'${{at.hour.toString().padLeft(2,"0")}}:${{at.minute.toString().padLeft(2,"0")}}',date:at,type:'custom',alarmTypeId:{kind}));}}finally{{n.dispose();}}
          return '${{(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}}';}})()""".replace('\n',' ')))
        for _ in range(40):
            if ring_id()==ident: break
            time.sleep(1)
        else: raise AssertionError('No native delivery')
        adb('shell','input','keyevent','KEYCODE_HOME')
        expand_own_notification()
        capture(name+'_visible')
        visible=ET.parse(OUT/(name+'_visible.xml'))
        buttons=[n for n in visible.iter('node') if (n.get('text') or n.get('content-desc'))=='알람 끄기']
        assert len(buttons)==1
        x,y,r,b=map(int,re.findall(r'\d+',buttons[0].get('bounds')))
        adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
        adb('shell','cmd','statusbar','collapse')
        adb('shell','am','start','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.MainActivity')
        scenario(name+'_dismiss','services/database_service.dart',f"""
          final d=await DatabaseService.instance.database;
          check((await d.query('alarms',where:'id=?',whereArgs:[{ident}])).isEmpty,'actual notification button removed fired row');
          check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'ring stopped');
          check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one dismissal history');
          check((await d.query('alarms',where:'id=2')).length==1,'original alarm intact');
        """)
        assert compare_os(name+'_os')
finally:
    import usb_oct03_restore_baseline
print('PASS actual notification dismiss buttons for sound+vibration, vibration and silent; physical perception remains separate.')
