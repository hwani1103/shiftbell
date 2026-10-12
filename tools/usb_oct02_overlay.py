import time,json
from usb_audit_device import evaluate,adb,capture,compare_os,OUT
from usb_audit_scenarios import scenario

for kind in [1,2,3]:
 name='overlay_type_'+str(kind)
 ident=int(evaluate(name+'_create','providers/alarm_provider.dart',f"""(() async {{
 final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
 final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
 try{{await n.addAlarm(Alarm(time:'${{at.hour.toString().padLeft(2,"0")}}:${{at.minute.toString().padLeft(2,"0")}}',date:at,type:'custom',alarmTypeId:{kind}));}}finally{{n.dispose();}}
 return '${{(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}}';}})()""".replace('\n',' ')))
 (OUT/(name+'_fixture.json')).write_text(json.dumps({'id':ident}),encoding='utf-8')
 scenario(name+'_ring','services/database_service.dart',f"""
 var ringing=false;for(var i=0;i<30;i++){{ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}}
 check(ringing,'actual AlarmManager delivery');
 """)
 time.sleep(1)
 capture(name+'_visible')
 adb('shell','input','tap','932','382')
 time.sleep(.6)
 scenario(name+'_dismiss','services/database_service.dart',f"""
 final d=await DatabaseService.instance.database;
 check((await d.query('alarms',where:'id=?',whereArgs:[{ident}])).isEmpty,'overlay X deletes only fired row');
 check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'ring stopped');
 check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one dismissal history');
 check((await d.query('alarms',where:'id=2')).length==1,'original alarm retained');
 """)
assert compare_os('overlay_types_final_os')
