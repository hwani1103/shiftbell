"""DB v26 atomicity on the disposable SRTL fixture, including process death."""
import json,sys,time
from usb_audit_device import SERIAL,PACKAGE,OUT,adb,evaluate,connect_vm,compare_os
from usb_audit_scenarios import scenario

assert SERIAL.startswith('localhost:')
connect_vm()
setup='''
 final service=DatabaseService.instance; final d=await service.database;
 final before=(await service.getShiftSchedule())!;
 final teams=(await service.getTeamScheduleConfig())!;
 final next=teams.withMyTeam(teams.names.firstWhere((n)=>n!=teams.myTeam));
 final rule=next.rules[next.myTeam]!;final now=DateTime.now();
 final after=ShiftSchedule(id:before.id,isRegular:true,pattern:rule.shifts,
   todayIndex:rule.indexOn(now),startDate:DateTime(now.year,now.month,now.day),
   shiftTypes:before.shiftTypes,activeShiftTypes:rule.shifts.toSet().toList(),
   shiftColors:before.shiftColors,customShiftColors:before.customShiftColors,
   assignedDates:{},shiftDurations:before.shiftDurations);
'''

if sys.argv[1]=='rollback':
    scenario('srtl_team_atomic_rollback','services/database_service.dart',setup+'''
      final oldMain=jsonEncode(before.toMap());final oldTeams=jsonEncode(teams.toJson());
      final alarms=jsonEncode(await d.query('alarms',orderBy:'id'));
      final overrides=jsonEncode(await d.query('alarm_overrides',orderBy:'rowid'));
      await d.execute("CREATE TRIGGER srtl_fail_roster BEFORE INSERT ON team_schedule_config BEGIN SELECT RAISE(ABORT,'SRTL interrupted roster write'); END");
      var failed=false;
      try {await service.applyTeamScheduleChange(before:before,after:after,expectedTeams:teams,nextTeams:next);}
      catch(_){failed=true;}finally{await d.execute('DROP TRIGGER srtl_fail_roster');}
      check(failed,'failure reached roster write after calendar write');
      check(jsonEncode((await service.getShiftSchedule())!.toMap())==oldMain,'calendar rolled back');
      check(jsonEncode((await service.getTeamScheduleConfig())!.toJson())==oldTeams,'roster rolled back');
      check(jsonEncode(await d.query('alarm_overrides',orderBy:'rowid'))==overrides,'exceptions rolled back');
      check(jsonEncode(await d.query('alarms',orderBy:'id'))==alarms,'alarms untouched before commit');
    ''')
    assert compare_os('srtl_team_atomic_rollback_os')
elif sys.argv[1]=='interrupt':
    snapshot=evaluate('srtl_pre_kill_snapshot','services/database_service.dart',"(() async {final s=DatabaseService.instance;return jsonEncode({'main':(await s.getShiftSchedule())!.toMap(),'teams':(await s.getTeamScheduleConfig())!.toJson()});})()")
    (OUT/'srtl_team_pre_kill.json').write_text(snapshot,encoding='utf8')
    scenario('srtl_team_waiting_for_commit','services/database_service.dart',setup+'''
      var held=false;
      d.transaction((tx) async {
        await tx.rawUpdate('UPDATE shift_schedule SET today_index=today_index');held=true;
        await Future<void>.delayed(const Duration(seconds:90));
      });
      for(var i=0;i<100 && !held;i++){await Future<void>.delayed(const Duration(milliseconds:20));}
      check(held,'SQLite transaction acquired');
      service.applyTeamScheduleChange(before:before,after:after,expectedTeams:teams,nextTeams:next);
      await Future<void>.delayed(const Duration(milliseconds:300));
      check(held,'real change requested while write queue blocked');
    ''')
    pid=adb('shell','pidof',PACKAGE).decode().strip();assert pid.isdigit()
    adb('shell','run-as',PACKAGE,'kill','-9',pid)
    (OUT/'srtl_team_kill_restart.txt').write_bytes(adb('shell','am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity'))
    print('Dev process interrupted; attach the restarted process, then verify.',flush=True)
elif sys.argv[1]=='verify':
    expected=(OUT/'srtl_team_pre_kill.json').read_text(encoding='utf8')
    actual=evaluate('srtl_post_kill_snapshot','services/database_service.dart',"(() async {final s=DatabaseService.instance;return jsonEncode({'main':(await s.getShiftSchedule())!.toMap(),'teams':(await s.getTeamScheduleConfig())!.toJson()});})()")
    assert json.loads(expected)==json.loads(actual),'Calendar/roster must both retain pre-commit state'
    scenario('srtl_team_restart_consistency','services/database_service.dart','''
      final s=DatabaseService.instance;final m=(await s.getShiftSchedule())!;final t=(await s.getTeamScheduleConfig())!;
      for(var i=-30;i<30;i++){final day=DateTime.now().add(Duration(days:i));check(m.getShiftForDate(day)==t.rules[t.myTeam]!.shiftOn(day),'main/roster date $i');}
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
    ''')
    assert compare_os('srtl_team_restart_os')
    print('PASS: process death before commit retains coherent main/roster; startup reservations agree.',flush=True)
else:raise ValueError(sys.argv[1])
