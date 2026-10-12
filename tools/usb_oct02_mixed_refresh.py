import sys,json
from usb_audit_device import evaluate,compare_os,OUT
from usb_audit_scenarios import scenario
action=sys.argv[1]
if action=='prepare':
 scenario('mixed_refresh_prepare','providers/alarm_provider.dart',"""
 final d=await DatabaseService.instance.database;final s=(await DatabaseService.instance.getShiftSchedule())!;
 check((await d.query('shift_alarm_templates')).isEmpty,'original templates empty');
 final snoozed=(await d.query('alarms',where:"type='snoozed'")).single;
 final custom=(await d.query('alarms',where:"type='custom'")).single;
 await DatabaseService.instance.replaceAllAlarmTemplates([
 {'shift_type':s.pattern!.first,'time':'23:41','alarm_type_id':3,'day_offset':0},
 {'shift_type':s.pattern!.last,'time':'23:42','alarm_type_id':3,'day_offset':0}]);
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final fixed=await d.query('alarms',where:"type='fixed'",orderBy:'date');
 check(fixed.length>=2,'fixed fixtures generated');
 final n=AlarmNotifier();try{
 await n.updateAlarmType(fixed[0]['id'] as int,2);
 await n.deleteAlarm(fixed[1]['id'] as int,DateTime.parse(fixed[1]['date'] as String));
 }finally{n.dispose();}
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 check((await d.query('alarms',where:'id=?',whereArgs:[snoozed['id']])).single['date']==snoozed['date'],'real snooze instant retained');
 check((await d.query('alarms',where:'id=?',whereArgs:[custom['id']])).single['date']==custom['date'],'original custom retained');
 check((await d.query('alarm_overrides')).length==2,'set_type and skip prepared');
 """)
elif action=='cleanup':
 scenario('mixed_refresh_cleanup','services/database_service.dart',"""
 final d=await DatabaseService.instance.database;
 await DatabaseService.instance.replaceAllAlarmTemplates([]);
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 check((await d.query('alarms',where:"type='fixed'")).isEmpty,'temporary fixed alarms removed');
 check((await d.query('shift_alarm_templates')).isEmpty,'original empty templates restored');
 """)
name='mixed_'+action
raw=evaluate('export_'+name,'services/database_service.dart',"""(() async {
final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),
'overrides':await d.query('alarm_overrides',orderBy:'id')});})()""".replace('\n',' '))
(OUT/(name+'.json')).write_text(raw,encoding='utf-8')
assert compare_os(name+'_os')
if action not in ['prepare','cleanup']:
 before=json.loads((OUT/'mixed_prepare.json').read_text(encoding='utf-8'));after=json.loads(raw)
 assert before==after, 'mixed reservations/overrides changed across lifecycle trigger'
 print('PASS mixed fixed/custom/real-snooze + set_type/skip survived '+action)
