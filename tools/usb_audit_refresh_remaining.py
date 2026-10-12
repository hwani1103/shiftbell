"""Additional real-device refresh contracts, using only the backed-up dev fixture."""
from usb_audit_device import connect_vm, compare_os
from usb_audit_scenarios import scenario

connect_vm()
scenario('r3_refresh_transitions', 'services/database_service.dart', '''
final service=DatabaseService.instance;
final d=await service.database;
final original=(await service.getShiftSchedule())!;
final templates=await d.query('shift_alarm_templates');
final now=DateTime.now();
final tomorrow=DateTime(now.year,now.month,now.day+1);
final key=tomorrow.toIso8601String().substring(0,10);
Future<void> refresh() async {await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');}
ShiftSchedule fixture(String shift) => ShiftSchedule.fromMap({...original.toMap(),
  'is_regular':1,'pattern':'Day Shift','today_index':0,
  'start_date':DateTime(now.year,now.month,now.day).toIso8601String(),
  'assigned_dates':jsonEncode({key:shift})});
try {
  await service.updateShiftSchedule(fixture('Day Shift'));
  await service.replaceAllAlarmTemplates([{'shift_type':'Day Shift','time':'23:40','alarm_type_id':3,'day_offset':0},
    {'shift_type':'Night duty','time':'23:50','alarm_type_id':3,'day_offset':0}]);
  await refresh();
  final first=(await d.query('alarms',where:'date LIKE ? AND time=?',whereArgs:['$key%','23:40'])).single;
  await service.updateAlarmTypeWithOverride(first['id'] as int,2);
  check((await d.query('alarm_overrides',where:'origin_date=?',whereArgs:[key])).isNotEmpty,'A override exists');
  await service.updateShiftSchedule(fixture('Night duty')); await refresh();
  check((await d.query('alarm_overrides',where:'origin_date=?',whereArgs:[key])).isEmpty,'A to B clears old override');
  check((await d.query('alarms',where:'date LIKE ?',whereArgs:['$key%'])).single['time']=='23:50','B schedule generated');
  await service.updateShiftSchedule(fixture('Day Shift')); await refresh();
  final back=(await d.query('alarms',where:'date LIKE ?',whereArgs:['$key%'])).single;
  check(back['time']=='23:40' && back['alarm_type_id']==3,'A restored from current template, no old type override');
  await service.updateAlarmTypeWithOverride(back['id'] as int,2);
  for(final time in ['23:41','23:40']) {
    await service.replaceAllAlarmTemplates([{'shift_type':'Day Shift','time':time,'alarm_type_id':3,'day_offset':0}]);
    await refresh();
    final row=(await d.query('alarms',where:'date LIKE ?',whereArgs:['$key%'])).single;
    check(row['time']==time && row['alarm_type_id']==3,'template transition $time uses current source');
  }
  final stable=await d.query('alarms',orderBy:'id');
  final history=await d.query('alarm_history',orderBy:'id');
  final log=await d.query('alarm_creation_log',orderBy:'id');
  await refresh();
  check(jsonEncode(stable)==jsonEncode(await d.query('alarms',orderBy:'id')),'stable refresh preserves IDs');
  check(jsonEncode(history)==jsonEncode(await d.query('alarm_history',orderBy:'id')),'stable refresh preserves history');
  check(jsonEncode(log)==jsonEncode(await d.query('alarm_creation_log',orderBy:'id')),'stable refresh adds no creation logs');
  for(final days in [29,30,31]) {
    final past=now.subtract(Duration(days:days,minutes:1));
    await d.insert('alarm_overrides',{'slot_time':past.toIso8601String().substring(0,19),
      'shift_type':'auditAge$days','day_offset':0,'action':'skip','created_at':past.toIso8601String(),
      'origin_date':past.toIso8601String().substring(0,10),'origin_shift':'auditAge$days'});
  }
  await refresh();
  for(final days in [29,30,31]) {
    final rows=await d.query('alarm_overrides',where:'shift_type=?',whereArgs:['auditAge$days']);
    check(rows.isNotEmpty==(days==29),'override retention $days days');
  }
} finally {
  await d.delete('alarm_overrides',where:'shift_type LIKE ?',whereArgs:['auditAge%']);
  await service.updateShiftSchedule(original);
  await service.replaceAllAlarmTemplates(templates);
  await refresh();
}
''')
assert compare_os('r3_refresh_transitions_os')

scenario('r3_refresh_atomic_window', 'services/database_service.dart', '''
final service=DatabaseService.instance;final d=await service.database;
final original=(await service.getShiftSchedule())!;
final templates=await d.query('shift_alarm_templates');
final now=DateTime.now();final today=DateTime(now.year,now.month,now.day);
Future<void> refresh() async {await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');}
ShiftSchedule fixture(String name)=>ShiftSchedule.fromMap({...original.toMap(),
 'is_regular':1,'pattern':name,'today_index':0,'start_date':today.toIso8601String(),'assigned_dates':null});
try {
 await service.updateShiftSchedule(fixture('Day Shift'));
 await service.replaceAllAlarmTemplates([
  for(final offset in [-1,0,1]) {'shift_type':'Day Shift','time':'23:40','alarm_type_id':3,'day_offset':offset},
  {'shift_type':'Night duty','time':'23:50','alarm_type_id':3,'day_offset':0}]);
 await refresh();
 final rows=await d.query('alarms',where:"type='fixed'",orderBy:'date');
 check(rows.length==10,'rolling window exactly ten future daily slots');
 check(rows.every((r)=>r['day_offset']==0),'same-day wins all three offset collision');
 check(DateTime.parse(rows.last['date'] as String).isBefore(today.add(const Duration(days:10))),'eleventh actual day excluded');
 final swapped=ShiftSchedule.fromMap({...fixture('Night duty').toMap(),
  'shift_types':original.shiftTypes.map((s)=>s=='Day Shift'?'Night duty':s=='Night duty'?'Day Shift':s).join(',')});
 await service.renameShiftAtomic(renamedShifts:{'Day Shift':'Night duty','Night duty':'Day Shift'},newSchedule:swapped);
 final ts=await d.query('shift_alarm_templates');
 check(ts.where((r)=>r['time']=='23:40').every((r)=>r['shift_type']=='Night duty'),'swap retains first template identity');
 check(ts.where((r)=>r['time']=='23:50').single['shift_type']=='Day Shift','swap retains second template identity');
 await refresh();
 check((await d.query('alarms',where:"type='fixed'")).every((r)=>r['shift_type']=='Night duty' && r['time']=='23:40'),'swap Native references agree');
 await service.renameShiftAtomic(renamedShifts:{'Day Shift':'Night duty','Night duty':'Day Shift'},newSchedule:fixture('Day Shift'));
 await refresh();
 final stable=await d.query('alarms',orderBy:'id');
 await service.replaceAllAlarmTemplates([{'shift_type':'Day Shift','time':'23:42','alarm_type_id':3,'day_offset':0}]);
 await d.execute("CREATE TRIGGER audit_fail_insert BEFORE INSERT ON alarms BEGIN SELECT RAISE(ABORT, 'audit failure'); END");
 try {await refresh();} catch (_) {}
 check(jsonEncode(stable)==jsonEncode(await d.query('alarms',orderBy:'id')),'Native insert failure rolls back old alarms');
 await d.execute('DROP TRIGGER audit_fail_insert'); await refresh();
 check((await d.query('alarms',where:"type='fixed'")).every((r)=>r['time']=='23:42'),'refresh recovers after SQL failure');
 await Future.wait([service.updateShiftSchedule(fixture('Night duty')),refresh()]);
 await refresh();
 check((await d.query('alarms',where:"type='fixed'")).isEmpty,'concurrent schedule and refresh converge to committed no-template shift');
 await service.updateShiftSchedule(fixture('Day Shift'));await refresh();
 check((await d.query('alarms',where:"type='fixed'")).length==10,'return from concurrent change regenerates full window');
} finally {
 await d.execute('DROP TRIGGER IF EXISTS audit_fail_insert');
 await service.updateShiftSchedule(original);await service.replaceAllAlarmTemplates(templates);await refresh();
}
''')
assert compare_os('r3_refresh_atomic_window_os')
