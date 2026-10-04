from usb_audit_device import evaluate, OUT
evaluate('resume_counts','services/database_service.dart',"""(() async {
final d=await DatabaseService.instance.database;final counts={};
for(final t in ['alarms','shift_alarm_templates','alarm_history','friends','date_memos','date_schedules','sleep_records']){counts[t]=(await d.query(t)).length;}
return jsonEncode(counts);})()""".replace('\n',' '))
evaluate('export_oct02_original','services/backup_service.dart',
         '(() async {return (await BackupService.instance.exportAll()).encode();})()')
evaluate('export_oct02_original_prefs','screens/settings_tab.dart',
         '(() async {final p=await SharedPreferences.getInstance(); return jsonEncode({for(final k in p.getKeys()) k:p.get(k)});})()')
