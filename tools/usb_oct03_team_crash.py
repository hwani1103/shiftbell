"""Characterize the existing two-store crash window in the real settings handler."""
import sys
from usb_audit_device import adb, evaluate, tap_text, connect_vm, OUT, PACKAGE
from usb_audit_scenarios import scenario

if sys.argv[1]=='interrupt':
    evaluate('team_crash_semantics','main.dart',"(() {WidgetsBinding.instance.ensureSemantics();return 'semantics retained';})()",wait=False)
    tap_text('^설정')
    scenario('team_crash_fixture','screens/settings_tab.dart',"""
      final service=DatabaseService.instance;final original=(await service.getShiftSchedule())!;
      await service.updateShiftSchedule(ShiftSchedule(id:original.id,isRegular:true,
        shiftTypes:['AuditDay','AuditNight'],pattern:['AuditDay','AuditNight'],todayIndex:0,startDate:DateTime.now()));
      final prefs=await SharedPreferences.getInstance();
      await prefs.setStringList('all_teams_names',['A','B']);
      await prefs.setString('all_teams_offsets',jsonEncode({'A':0,'B':1}));
      await prefs.setString('all_teams_my_team','A');
      _SettingsTabState? state;
      void visit(Element e){if(e is StatefulElement && e.state is _SettingsTabState)state=e.state as _SettingsTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      check(state!=null,'actual settings state mounted');
      await state!.ref.read(scheduleProvider.notifier).refresh();
      check((await service.getShiftSchedule())!.todayIndex==0,'old schedule fixture committed');
    """)
    scenario('team_crash_handler_waiting_after_prefs','screens/settings_tab.dart',"""
      final d=await DatabaseService.instance.database;final prefs=await SharedPreferences.getInstance();
      d.transaction((tx) async {
        await tx.rawUpdate('UPDATE shift_schedule SET today_index=today_index');
        await prefs.setBool('oct03_audit_db_held',true);
        await Future<void>.delayed(const Duration(seconds:90));
      });
      for(var i=0;i<50 && prefs.getBool('oct03_audit_db_held')!=true;i++){await Future<void>.delayed(const Duration(milliseconds:20));}
      check(prefs.getBool('oct03_audit_db_held')==true,'DB write transaction held');
      _SettingsTabState? state;
      void visit(Element e){if(e is StatefulElement && e.state is _SettingsTabState)state=e.state as _SettingsTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      state!._applyScheduleChange(const ScheduleChangeSelection(1,'B'),DateTime.now(),TeamScheduleConfig.read(prefs));
      for(var i=0;i<50 && prefs.getString('all_teams_my_team')!='B';i++){await Future<void>.delayed(const Duration(milliseconds:20));}
      check(prefs.getString('all_teams_my_team')=='B','real settings handler persisted team before blocked DB write');
    """)
    pid=adb('shell','pidof',PACKAGE).decode().strip()
    assert pid.isdigit()
    adb('shell','run-as',PACKAGE,'kill','-9',pid)
    log=adb('shell','am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
    (OUT/'team_crash_restart.txt').write_bytes(log)
    print('Interrupted only the dev app between preference and DB commits; phone remains on. Reattach and verify.')
elif sys.argv[1]=='verify':
    connect_vm()
    try:
        scenario('OBS_team_crash_persistent_mismatch','screens/settings_tab.dart',"""
          final prefs=await SharedPreferences.getInstance();
          final s=(await DatabaseService.instance.getShiftSchedule())!;
          check(prefs.getString('all_teams_my_team')=='B','new team preference survived process death');
          check(s.todayIndex==0,'old DB schedule survived process death');
          check(s.pattern!.join(',')=='AuditDay,AuditNight','same controlled schedule fixture');
        """)
        print('OBS CONFIRMED: preferences B / DB index 0 after restart. This is an unresolved consistency window, not a product PASS.')
    finally:
        import usb_oct03_restore_baseline
else:raise ValueError(sys.argv[1])
