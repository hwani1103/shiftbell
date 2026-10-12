import json,sys,time
from usb_audit_device import evaluate,capture,OUT,compare_os
action=sys.argv[1]
if action=='create':
 result=evaluate('ring_created','providers/alarm_provider.dart',"""(() async {
 final d=await DatabaseService.instance.database;final before=(await d.query('alarms')).map((r)=>r['id']).toSet();
 final at=DateTime.now().add(const Duration(seconds:30));final n=AlarmNotifier();
 try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
 final row=(await d.query('alarms')).singleWhere((r)=>!before.contains(r['id']));
 return '${row['id']}';})()""".replace('\n',' '))
 (OUT/'ring_fixture.json').write_text(json.dumps({'id':int(result)}),encoding='utf-8')
elif action=='wait':
 row=json.loads((OUT/'ring_fixture.json').read_text(encoding='utf-8'))
 result=evaluate('ring_actual_delivery','services/database_service.dart',f"""(() async {{
 for(var i=0;i<90;i++){{if(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{row['id']}}})??false)return 'PASS actual AlarmManager delivery id={row['id']}';await Future<void>.delayed(const Duration(seconds:1));}}
 return 'FAIL not ringing';}})()""".replace('\n',' '),timeout=100)
 assert result.startswith('PASS')
 capture('ring_native_overlay')
elif action=='snooze_state':
 row=json.loads((OUT/'ring_fixture.json').read_text(encoding='utf-8'))
 result=evaluate('ring_after_native_snooze','services/database_service.dart',f"""(() async {{
 final d=await DatabaseService.instance.database;final r=(await d.query('alarms',where:'id=?',whereArgs:[{row['id']}])).single;
 if(r['type']!='snoozed')throw StateError('Not snoozed');
 return jsonEncode(r);}})()""".replace('\n',' '))
 (OUT/'real_snooze_fixture.json').write_text(result,encoding='utf-8')
 assert compare_os('real_snooze_os')
else:raise ValueError(action)
