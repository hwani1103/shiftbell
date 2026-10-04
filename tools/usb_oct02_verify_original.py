import base64,json
from usb_audit_device import evaluate,OUT,compare_os
from usb_audit_scenarios import scenario
prefs=json.loads(json.loads((OUT/'export_oct02_original_prefs.vm.json').read_text(encoding='utf-8'))['valueAsString'])
encoded=base64.b64encode(json.dumps(prefs,ensure_ascii=False).encode()).decode()
scenario('final_original_share_preferences','services/friend_sync_service.dart',f"""
 final p=await SharedPreferences.getInstance();final original=jsonDecode(utf8.decode(base64Decode('{encoded}'))) as Map;
 check(!(await FriendSyncService.instance.getShareState()).isActive,'sharing off before restoring original keys');
 final uid=await FriendSyncService.instance.getOrCreateOwnerId();
 check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'own temporary server document absent');
 for(final key in FriendSyncService.backupExcludedPreferenceKeys){{
 final value=original[key];if(value==null){{await p.remove(key);}}else if(value is bool){{await p.setBool(key,value);}}else if(value is int){{await p.setInt(key,value);}}else if(value is String){{await p.setString(key,value);}}
 }}
 check((await FriendSyncService.instance.getShareState()).intent==FriendShareIntent.off,'original sharing off restored');
 """)
original=json.loads(json.loads((OUT/'export_oct02_original.vm.json').read_text(encoding='utf-8'))['valueAsString'])
current=json.loads(evaluate('export_original_verified','services/backup_service.dart','(() async {return (await BackupService.instance.exportAll()).encode();})()'))
differences=[]
for table,rows in original['tables'].items():
 if table in ('alarm_history','alarm_creation_log'):continue
 if rows!=current['tables'].get(table):differences.append(table)
(OUT/'original_table_comparison.json').write_text(json.dumps({'changedTables':differences,'permanentHistoryRetained':True}),encoding='utf-8')
assert not differences,differences
assert compare_os('original_verified_os')
print('PASS original tables unchanged except retained permanent audit history; original sharing keys restored; DB/OS1')
