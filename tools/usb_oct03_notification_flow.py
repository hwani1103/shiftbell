import json
import sys
import time
import xml.etree.ElementTree as ET
from usb_audit_device import adb, evaluate, capture, compare_os, OUT
from usb_audit_scenarios import scenario

action = sys.argv[1]
fixture = OUT/'notification_fixture.json'
if action == 'prepare':
    ident = int(evaluate('notification_fixture_create','providers/alarm_provider.dart',"""(() async {
      final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
      final at=DateTime.now().add(const Duration(seconds:10));final n=AlarmNotifier();
      try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
      return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';})()""".replace('\n',' ')))
    fixture.write_text(json.dumps({'id':ident}),encoding='utf-8')
    scenario('notification_actual_first_ring','services/database_service.dart',f"""
      var ringing=false;for(var i=0;i<35;i++){{ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}}
      check(ringing,'real OS delivery for notification fixture');
    """)
    adb('shell','input','keyevent','KEYCODE_HOME')
    adb('shell','cmd','statusbar','expand-notifications')
    capture('notification_first_shade')
elif action == 'snooze_state':
    ident=json.loads(fixture.read_text())['id']
    row=json.loads(evaluate('notification_actual_snooze_row','services/database_service.dart',f"""(() async {{
      final d=await DatabaseService.instance.database;final row=(await d.query('alarms',where:'id=?',whereArgs:[{ident}])).single;
      if(row['type']!='snoozed')throw StateError('notification button did not snooze');return jsonEncode(row);
    }})()""".replace('\n',' ')))
    (OUT/'notification_snoozed.json').write_text(json.dumps(row),encoding='utf-8')
    assert compare_os('notification_snoozed_os')
    adb('shell','cmd','statusbar','collapse')
elif action == 'tap_snooze':
    from usb_audit_device import tap_text
    values = {n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as','com.hwani1103.shiftbell.dev','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
    state=json.loads(fixture.read_text())
    assert int(values['currently_ringing_alarm_id'])==state['id']
    state['first_round']=int(values['currently_ringing_round'])
    fixture.write_text(json.dumps(state),encoding='utf-8')
    tap_text('^5분 후$')
    print('Actual notification 5-minute button tapped.',flush=True)
elif action == 'wait_second':
    ident=json.loads(fixture.read_text())['id']
    for i in range(37):
        values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as','com.hwani1103.shiftbell.dev','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
        ringing=int(values.get('currently_ringing_alarm_id','-1'))==ident
        print(f'Native re-ring poll {i}: {ringing}',flush=True)
        if ringing:
            print('Actual 5-minute snooze fired again without changing device clock.',flush=True)
            adb('shell','cmd','statusbar','expand-notifications')
            capture('notification_second_shade')
            break
        time.sleep(10)
    else:
        raise AssertionError('Snooze did not ring within 6 minutes')
else:
    raise ValueError(action)
