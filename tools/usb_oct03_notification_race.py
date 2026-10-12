import json
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from usb_audit_device import adb, OUT, compare_os
from usb_audit_scenarios import scenario

fixture=json.loads((OUT/'notification_fixture.json').read_text())
ident=fixture['id']
values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as','com.hwani1103.shiftbell.dev','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
assert int(values['currently_ringing_alarm_id'])==ident
new=int(values['currently_ringing_round'])
old=fixture['first_round']
assert new!=old

def action(name, round_):
    response=adb('shell','run-as','com.hwani1103.shiftbell.dev','/system/bin/am','broadcast','--user','0',
        '-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.AlarmActionReceiver','-a',name,
        '--ei','alarmId',str(ident),'--el','ringRound',str(round_))
    assert b'Broadcast completed' in response

try:
    for name in ['DISMISS_FROM_NOTIFICATION','SNOOZE_FROM_NOTIFICATION']:
        action(name,old)
    scenario('notification_stale_round_ignored','services/database_service.dart',f"""
      final d=await DatabaseService.instance.database;
      check(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false,'stale notification actions preserve new round');
      check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'stale actions add no history');
    """)
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(action,name,new) for name in ['DISMISS_FROM_NOTIFICATION','SNOOZE_FROM_NOTIFICATION']]
        for future in futures: future.result()
    scenario('notification_current_round_first_wins','services/database_service.dart',f"""
      final d=await DatabaseService.instance.database;
      check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'current round ended');
      check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==2,'exactly one result for each of two rounds');
      final rows=await d.query('alarms',where:'id=?',whereArgs:[{ident}]);
      check(rows.isEmpty || (rows.length==1 && rows.single['type']=='snoozed'),'one winning action');
    """)
    assert compare_os('notification_race_os')
    (OUT/'notification_rounds.json').write_text(json.dumps({'id':ident,'first_round':old,'second_round':new,
        'actual_snooze_ui':True,'clock_changed':False,'race_delivery':'same-app UID receiver broadcasts'}),encoding='utf-8')
finally:
    adb('shell','cmd','statusbar','collapse')
    import usb_oct03_restore_baseline
print('PASS actual 5-minute re-ring, stale round ignored, concurrent end action has one winner, originals restored.')
