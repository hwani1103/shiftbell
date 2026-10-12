"""Mixed lifecycle evidence; preserves the user's data and permanent history."""
import json,subprocess
from usb_audit_device import evaluate,adb,OUT,ADB,SERIAL,PACKAGE,compare_os
from usb_audit_scenarios import scenario

(OUT/'real_snooze_delivery_log.txt').write_bytes(adb('logcat','-d','-s','CustomAlarmReceiver','AlarmActionReceiver'))
scenario('real_snooze_finished','services/database_service.dart',"""
final d=await DatabaseService.instance.database;
check((await d.query('alarms',where:'id=?',whereArgs:[3])).isEmpty,'snoozed alarm completed');
final h=await d.query('alarm_history',where:'alarm_id=?',whereArgs:[3]);
check(h.any((r)=>r['dismiss_type']=='timeout'),'real snooze ended by timeout');
check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':3})??true),'no active ring after timeout');
""")
raw=evaluate('export_mixed_restore','services/backup_service.dart','(() async {return (await BackupService.instance.exportAll()).encode();})()')
target='/data/user_de/0/'+PACKAGE+'/files/oct02_mixed_restore.json'
subprocess.run([ADB,'-s',SERIAL,'shell','-T','run-as',PACKAGE,'tee',target],input=raw.encode(),stdout=subprocess.DEVNULL,check=True)
scenario('mixed_restore_roundtrip','services/restore_coordinator.dart',f"""
final d=await DatabaseService.instance.database;
final payload=BackupPayload.decode(await File('{target}').readAsString());
final beforeOverrides=jsonEncode(await d.query('alarm_overrides',orderBy:'id'));
final beforeMemos=jsonEncode(await d.query('date_memos',orderBy:'id'));
final beforeSleep=jsonEncode(await d.query('sleep_records',orderBy:'id'));
final beforeHistory=(await d.query('alarm_history')).length;
await RestoreCoordinator.instance.start(payload,overwrite:true);
check(jsonEncode(await d.query('alarm_overrides',orderBy:'id'))==beforeOverrides,'fixed skip and type exceptions survive restore');
check(jsonEncode(await d.query('date_memos',orderBy:'id'))==beforeMemos,'user memos preserved');
check(jsonEncode(await d.query('sleep_records',orderBy:'id'))==beforeSleep,'user sleep records preserved');
check((await d.query('alarm_history')).length>=beforeHistory,'permanent history preserved');
check((await d.query('alarms',where:"type='custom'")).length==1,'original one-tap restored');
check(!await RestoreCoordinator.instance.hasPendingJob(),'restore completed without pending job');
check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'restore lock released');
""")
assert compare_os('mixed_restore_roundtrip_os')
