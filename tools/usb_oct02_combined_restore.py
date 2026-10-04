import time,json,subprocess
from usb_audit_device import evaluate,adb,OUT,PACKAGE,ADB,SERIAL,compare_os,capture
from usb_audit_scenarios import scenario
ident=int(evaluate('combined_ring_create','providers/alarm_provider.dart',"""(() async {
final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';})()""".replace('\n',' ')))
(OUT/'combined_snooze_id.json').write_text(json.dumps({'id':ident}),encoding='utf-8')
scenario('combined_actual_ring','services/database_service.dart',f"""
var on=false;for(var i=0;i<30;i++){{on=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(on)break;await Future<void>.delayed(const Duration(seconds:1));}}check(on,'actual English alarm delivered');
""")
time.sleep(1);adb('shell','input','tap','720','382');time.sleep(.5)
raw=evaluate('export_combined_payload','services/backup_service.dart','(() async {return (await BackupService.instance.exportAll()).encode();})()')
target='/data/user_de/0/'+PACKAGE+'/files/oct02_combined_restore.json'
subprocess.run([ADB,'-s',SERIAL,'shell','-T','run-as',PACKAGE,'tee',target],input=raw.encode(),stdout=subprocess.DEVNULL,check=True)
scenario('combined_stop_pending_snooze_restore','services/restore_coordinator.dart',f"""
final d=await DatabaseService.instance.database;final p=await SharedPreferences.getInstance();
check(p.getString('friend_share_intent')=='stop_pending','offline locale stop pending before restore');
final original=(await d.query('alarms',where:'id=?',whereArgs:[{ident}])).single;
check(original['type']=='snoozed','real native snooze prepared');
final generation=p.getInt('friend_share_generation');
await RestoreCoordinator.instance.start(BackupPayload.decode(await File('{target}').readAsString()),overwrite:true);
final after=(await d.query('alarms',where:'id=?',whereArgs:[{ident}])).single;
check(jsonEncode(original)==jsonEncode(after),'real snooze ID and instant carried through restore');
check(p.getString('friend_share_intent')=='stop_pending' && p.getInt('friend_share_generation')==generation,'restore preserves pending share stop ownership');
check(!await RestoreCoordinator.instance.hasPendingJob(),'combined restore job completed');
check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'combined restore lock released');
""",timeout=120)
assert compare_os('combined_restore_os')
capture('combined_english_restored')
