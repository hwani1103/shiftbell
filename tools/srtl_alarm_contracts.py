"""Latest-dev alarm contracts on disposable SRTL data, never the personal USB phone."""
import json
from usb_audit_device import SERIAL, connect_vm, compare_os, OUT
from usb_audit_scenarios import scenario, native_refresh

assert SERIAL.startswith('localhost:'), 'This suite deletes SRTL test data'
connect_vm()
scenario('deletion_contract_nonempty_roster','services/database_service.dart','''
 final s=DatabaseService.instance;final m=(await s.getShiftSchedule())!;
 final offset=(m.todayIndex!-m.startDate!.difference(TeamScheduleConfig.baseDate).inDays)%m.pattern!.length;
 await s.saveTeamScheduleConfig(TeamScheduleConfig(names:['A','B','C','D'],
   offsets:{'A':offset,'B':offset+2,'C':offset+4,'D':offset+6},myTeam:'A').materialize(m.pattern!));
 check((await s.getTeamScheduleConfig())!.names.length==4,'nonempty roster for retention/reset assertions');
''')
native_refresh()
assert compare_os('current_refresh_os')
scenario('current_history_clear_contract','services/database_service.dart','''
 final s=DatabaseService.instance;final d=await s.database;
 final alarms=jsonEncode(await d.query('alarms',orderBy:'id'));
 final templates=jsonEncode(await d.query('shift_alarm_templates',orderBy:'id'));
 final main=jsonEncode(await d.query('shift_schedule'));
 final teams=jsonEncode(await d.query('team_schedule_config'));
 await s.resetAllAlarmHistoryAndLog();
 check((await d.query('alarm_history')).isEmpty,'history cleared');
 check((await d.query('alarm_creation_log')).isEmpty,'creation log cleared');
 check(alarms==jsonEncode(await d.query('alarms',orderBy:'id')),'future alarms untouched');
 check(templates==jsonEncode(await d.query('shift_alarm_templates',orderBy:'id')),'fixed templates untouched');
 check(main==jsonEncode(await d.query('shift_schedule')),'main schedule untouched');
 check(teams==jsonEncode(await d.query('team_schedule_config')),'roster untouched');
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 check((await d.query('alarm_history')).isEmpty && (await d.query('alarm_creation_log')).isEmpty,'stable refresh does not recreate deleted history');
''')
assert compare_os('current_history_clear_os')
scenario('current_all_alarm_delete_contract','providers/alarm_provider.dart','''
 final s=DatabaseService.instance;final d=await s.database;
 final main=(await d.query('shift_schedule')).single.toString();
 final teams=(await d.query('team_schedule_config')).toString();
 final n=AlarmNotifier();
 try {
  final at=DateTime.now().add(const Duration(days:1,hours:1));
  await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));
  check((await d.query('alarms',where:"type='custom'")).isNotEmpty,'custom and fixed mixed');
  final ringAt=DateTime.now().add(const Duration(seconds:8));
  await n.addAlarm(Alarm(time:'${ringAt.hour.toString().padLeft(2,"0")}:${ringAt.minute.toString().padLeft(2,"0")}',date:ringAt,type:'custom',alarmTypeId:3));
  final ringId=(await d.query('alarms',orderBy:'id DESC',limit:1)).single['id'] as int;
  var ringing=false;
  for(var i=0;i<25;i++){ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':ringId})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}
  check(ringing,'actual OS alarm is ringing before all-delete');
  await n.deleteAllAlarmsCompletely();
  check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':ringId})??true),'all-delete stops active ring too');
  for(final t in ['alarms','shift_alarm_templates'])check((await d.query(t)).isEmpty,'$t deleted');
  check((await d.query('alarm_history')).isNotEmpty,'cancellation history retained');
  check(main==(await d.query('shift_schedule')).single.toString(),'main schedule retained');
  check(teams==(await d.query('team_schedule_config')).toString(),'roster retained');
  await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
  check((await d.query('alarms')).isEmpty,'refresh cannot resurrect all-deleted alarms');
 }finally{n.dispose();}
''')
assert compare_os('current_all_delete_os')
from srtl_ring_checks import prepare
prepare('reset_while_actually_ringing',False,3)
reset_ring_id=json.loads((OUT/'ring_current.json').read_text(encoding='utf-8'))['id']
scenario('current_schedule_reset_contract','providers/schedule_provider.dart','''
 final n=ScheduleNotifier();
 try{
  check(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':RESET_RING_ID})??false,'actual ring active before reset');
  await n.refresh();await n.resetSchedule();
  check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':RESET_RING_ID})??true),'reset stops active ring');
  final d=await DatabaseService.instance.database;
  for(final t in ['shift_schedule','alarms','shift_alarm_templates','alarm_overrides','alarm_history','alarm_creation_log'])check((await d.query(t)).isEmpty,'reset $t');
  check(await DatabaseService.instance.getTeamScheduleConfig()==null,'roster tombstone prevents legacy resurrection');
  await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
  check((await d.query('alarms')).isEmpty,'refresh after reset remains empty');
 }finally{n.dispose();}
'''.replace('RESET_RING_ID',str(reset_ring_id)))
assert compare_os('current_reset_os')
print('PASS: refresh/history-only deletion/all-alarm deletion/full reset have distinct verified effects',flush=True)
