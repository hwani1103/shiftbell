import json,subprocess,base64
from usb_audit_device import evaluate,adb,OUT,PACKAGE,ADB,SERIAL,compare_os,connect_vm
from usb_audit_scenarios import scenario
connect_vm()
raw=json.loads((OUT/'export_oct02_original.vm.json').read_text(encoding='utf-8'))['valueAsString']
target='/data/user_de/0/'+PACKAGE+'/files/oct02_original_restore.json'
subprocess.run([ADB,'-s',SERIAL,'shell','-T','run-as',PACKAGE,'tee',target],input=raw.encode(),stdout=subprocess.DEVNULL,check=True)
scenario('original_restore','services/restore_coordinator.dart',f"""
 final d=await DatabaseService.instance.database;final history=(await d.query('alarm_history')).length;
 final payload=BackupPayload.decode(await File('{target}').readAsString());
 await RestoreCoordinator.instance.start(payload,overwrite:true);
 for(final table in ['shift_schedule','shift_alarm_templates','alarm_overrides','date_memos','date_schedules','sleep_records','friends']){{
 check(jsonEncode(await d.query(table,orderBy:'rowid'))==jsonEncode(payload.tables[table]),'original '+table+' restored');}}
 final alarms=await d.query('alarms');check(alarms.length==1 && alarms.single['date']==payload.tables['alarms']!.single['date'],'original 04:50 alarm restored');
 check((await d.query('alarm_history')).length>=history,'test and original permanent history retained');
 check(!await RestoreCoordinator.instance.hasPendingJob(),'no incomplete restore');
 check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'no restore lock');
 """,timeout=120)
# Sharing was off at the beginning; only restore that installation's original keys.
prefs=json.loads(json.loads((OUT/'export_oct02_original_prefs.vm.json').read_text(encoding='utf-8'))['valueAsString'])
encoded=base64.b64encode(json.dumps(prefs,ensure_ascii=False).encode()).decode()
scenario('original_share_preferences','services/friend_sync_service.dart',f"""
 final p=await SharedPreferences.getInstance();final original=jsonDecode(utf8.decode(base64Decode('{encoded}'))) as Map;
 check(!(await FriendSyncService.instance.getShareState()).isActive,'no sharing active');
 for(final key in FriendSyncService.backupExcludedPreferenceKeys){{
 final value=original[key];if(value==null){{await p.remove(key);}}else if(value is bool){{await p.setBool(key,value);}}else if(value is int){{await p.setInt(key,value);}}else if(value is String){{await p.setString(key,value);}}
 }}
 check((await FriendSyncService.instance.getShareState()).intent==FriendShareIntent.off,'original sharing off');
 """)
assert compare_os('original_restored_os')
evaluate('original_restored_backup','services/backup_watcher.dart','(() async {await BackupWatcher.instance.backupNow();await BackupWatcher.instance.backupNow(manual:true);return "restored data saved in dev backup slots";})()')
