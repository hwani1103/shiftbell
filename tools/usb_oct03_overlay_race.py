import time
from concurrent.futures import ThreadPoolExecutor
from usb_audit_device import evaluate,capture,compare_os,adb
from usb_audit_scenarios import scenario
ident=int(evaluate('overlay_race_create','providers/alarm_provider.dart',"""(() async {
 final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
 final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
 try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
 return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';})()""".replace('\n',' ')))
scenario('overlay_race_delivery','services/database_service.dart',f'''
 var ringing=false;for(var i=0;i<30;i++){{ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}}
 check(ringing,'actual native ring');
''')
time.sleep(1)
capture('overlay_race_visible')
with ThreadPoolExecutor(max_workers=2) as pool:
    results=[pool.submit(adb,'shell','input','tap',x,'382') for x in ['932','720']]
    for result in results:result.result()
scenario('overlay_race_actions','services/database_service.dart',f'''
 await Future<void>.delayed(const Duration(seconds:2));
 final d=await DatabaseService.instance.database;
 check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'round stopped');
 check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one winning action history');
 final rows=await d.query('alarms',where:'id=?',whereArgs:[{ident}]);
 check(rows.isEmpty || rows.single['type']=='snoozed','one valid final result');
''')
assert compare_os('overlay_race_os')
import usb_oct03_restore_baseline
