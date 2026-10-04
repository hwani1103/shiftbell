import json,time,datetime
from usb_audit_device import evaluate,adb,capture,compare_os,OUT
from usb_audit_scenarios import scenario

if datetime.datetime.now().second>35:time.sleep(60-datetime.datetime.now().second+1)
raw=evaluate('overlay_collision_fixture','providers/alarm_provider.dart',"""(() async {
final d=await DatabaseService.instance.database;final before=(await d.query('alarms')).map((r)=>r['id']).toSet();final n=AlarmNotifier();
try{for(final secs in [8,310]){final at=DateTime.now().add(Duration(seconds:secs));await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}}finally{n.dispose();}
return (await d.query('alarms',orderBy:'date')).where((r)=>!before.contains(r['id'])).map((r)=>r['id']).join(',');})()""".replace('\n',' '))
a,b=map(int,raw.split(','))
(OUT/'overlay_collision_fixture.json').write_text(json.dumps({'a':a,'b':b}),encoding='utf-8')
try:
 scenario('overlay_collision_ring','services/database_service.dart',f"""
 var on=false;for(var i=0;i<30;i++){{on=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{a}}})??false;if(on)break;await Future<void>.delayed(const Duration(seconds:1));}}check(on,'collision source actually rings');
 """)
 time.sleep(1);adb('shell','input','tap','720','382');capture('overlay_collision_message')
 scenario('overlay_collision_result','services/database_service.dart',f"""
 final d=await DatabaseService.instance.database;
 check((await d.query('alarms',where:'id=?',whereArgs:[{a}])).isEmpty,'colliding snooze source removed');
 check((await d.query('alarms',where:'id=?',whereArgs:[{b}])).single['type']=='custom','existing target kept');
 check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{a}])).single['dismiss_type']=='snooze_skipped_existing_alarm','collision history exactly once');
 check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{a}}})??true),'collision ring stops');
 """)
 assert compare_os('overlay_collision_os')
finally:
 scenario('overlay_collision_cleanup','providers/alarm_provider.dart',f"""
 final d=await DatabaseService.instance.database;final n=AlarmNotifier();try{{for(final id in [{a},{b}]){{final rows=await d.query('alarms',where:'id=?',whereArgs:[id]);if(rows.isNotEmpty)await n.deleteAlarm(id,DateTime.parse(rows.single['date'] as String));}}}}finally{{n.dispose();}}
 check((await d.query('alarms',where:'id IN (?,?)',whereArgs:[{a},{b}])).isEmpty,'only collision fixtures removed');
 """)
