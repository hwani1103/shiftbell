import sys,json
from usb_audit_device import evaluate,OUT,compare_os
from usb_audit_scenarios import scenario
if sys.argv[1]=='prepare':
 raw=evaluate('date_fixed_prepare','services/database_service.dart',"""(() async {
 final d=await DatabaseService.instance.database;if((await d.query('shift_alarm_templates')).isNotEmpty)throw StateError('original templates must be empty');
 final s=(await DatabaseService.instance.getShiftSchedule())!;final now=DateTime.now();final at=now.add(const Duration(hours:2));
 final wall='${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}';
 await d.insert('shift_alarm_templates',{'shift_type':s.getShiftForDate(now),'time':wall,'alarm_type_id':3,'day_offset':0});
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final row=(await d.query('alarms',where:'type=?',whereArgs:['fixed'],orderBy:'date')).first;
 return jsonEncode(row);})()""".replace('\n',' '))
 (OUT/'date_fixed_fixture.json').write_text(raw,encoding='utf-8')
 assert compare_os('date_fixed_prepared_os')
else:
 scenario('date_fixed_cleanup','services/database_service.dart',"""
 await DatabaseService.instance.replaceAllAlarmTemplates([]);await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final d=await DatabaseService.instance.database;await d.delete('alarm_overrides');
 check((await d.query('alarms')).length==1 && (await d.query('alarms')).single['id']==2,'only original alarm remains');
 """)
 assert compare_os('date_fixed_clean_os')
