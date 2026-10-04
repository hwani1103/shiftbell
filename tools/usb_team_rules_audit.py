"""Oct 3 roster audit: dev package only; real screen taps + DB/OS assertions.
Original DB/preferences are captured separately before fixtures and restored at end.
"""
import sys, json, time, base64
from usb_audit_device import adb, evaluate, capture, connect_vm, OUT, PACKAGE, compare_os
from usb_audit_scenarios import scenario

assert PACKAGE == 'com.hwani1103.shiftbell.dev'

def tap(name, predicate, library='screens/all_teams_setup_screen.dart'):
    point=evaluate('tap_'+name,library,"""(() async {
      Element? target;
      final scrolls=<ScrollableState>[];
      void visit(Element e){
        if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
        if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
        {
          if(PREDICATE)target=e;
          if(e is StatefulElement && e.state is ScrollableState){
            final s=e.state as ScrollableState;
            if(s.position.hasContentDimensions && s.position.maxScrollExtent.isFinite)scrolls.add(s);
          }
        }
        e.visitChildren(visit);
      }
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      if(target==null && scrolls.isNotEmpty){
        final scroll=scrolls.first.position; scroll.jumpTo(0);
        for(var i=0;i<80 && target==null;i++){
          await Future<void>.delayed(const Duration(milliseconds:50));
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          if(target==null)scroll.jumpTo((scroll.pixels+scroll.viewportDimension*0.6).clamp(0.0,scroll.maxScrollExtent));
        }
      }
      if(target==null) throw StateError('Missing tap target');
      await Scrollable.ensureVisible(target!,alignment:0.5);
      await Future<void>.delayed(const Duration(milliseconds:350));
      final box=target!.findRenderObject() as RenderBox;
      final p=box.localToGlobal(Offset(box.size.width/2,box.size.height/2));
      return '${p.dx},${p.dy},${WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio}';
    })()""".replace('PREDICATE',predicate).replace('\n',' '))
    x,y,ratio=map(float,point.split(','))
    # VM coordinates are logical pixels; adb takes physical pixels.
    adb('shell','input','tap',str(round(x*ratio)),str(round(y*ratio)))
    time.sleep(.45)

def key(name): tap(name,"e.widget.key == const ValueKey('"+name+"')")
def button(text): tap('button',"e.widget is Text && (e.widget as Text).data == "+json.dumps(text,ensure_ascii=False))
def shift(text): key('rule-shift-'+text)

def open_calendar_roster():
    evaluate('open_roster','screens/calendar_tab.dart',"""(() {
      _CalendarTabState? s;
      void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      s!._openAllShiftsView(); return 'opened roster';
    })()""".replace('\n',' '))
    time.sleep(.7)

def setup_fixture():
    scenario('fixture_main','screens/settings_tab.dart',"""
      final service=DatabaseService.instance; final old=(await service.getShiftSchedule())!;
      final now=DateTime.now();
      final main=ShiftSchedule(id:old.id,isRegular:true,
        pattern:['주간','주간','휴무','휴무','야간','야간','휴무','휴무'],
        todayIndex:4,startDate:DateTime(now.year,now.month,now.day),
        shiftTypes:['주간','야간','휴무','근무','연차'],activeShiftTypes:['주간','야간','휴무']);
      await service.saveTeamScheduleConfig(null);
      await service.updateShiftSchedule(main);
      await service.replaceAllAlarmTemplates([
        {'shift_type':'주간','time':'07:11','alarm_type_id':1,'day_offset':0},
        {'shift_type':'야간','time':'19:12','alarm_type_id':2,'day_offset':0},
        {'shift_type':'근무','time':'08:13','alarm_type_id':3,'day_offset':0}]);
      final d=await service.database;
      await d.delete('alarm_history',where:'alarm_id=?',whereArgs:[987654]);
      await d.insert('alarm_history',{'alarm_id':987654,'scheduled_time':'07:11','scheduled_date':'2026-09-01T07:11:00',
        'actual_ring_time':'2026-09-01T07:11:00','dismiss_type':'dismissed','snooze_count':0,
        'shift_type':'주간','created_at':'2026-09-01T07:11:00','day_offset':0});
      ConsumerState? state;
      void visit(Element e){if(e is StatefulElement && e.state is ConsumerState)state=e.state as ConsumerState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      await state!.ref.read(scheduleProvider.notifier).refresh();
      check((await d.rawQuery('PRAGMA user_version')).single['user_version']==26,'device database upgraded to v26');
    """)

def create_individual():
    open_calendar_roster(); button('전체 교대조 근무표 만들기')
    capture('setup_modes')
    finish_individual()

def finish_individual():
    button('수정')
    tap('add_field','e.widget is TextField')
    adb('shell','input','text','E'); adb('shell','input','keyevent','66'); time.sleep(.5)
    button('완료')
    tap('my_C',"e.widget is AppShiftChip && (e.widget as AppShiftChip).label=='C' && (e.widget as AppShiftChip).onTap!=null")
    key('team-mode-individual')
    capture('setup_individual_roster')
    key('team-setup-rule-A'); key('rule-position-0'); key('rule-save')
    key('team-setup-rule-B'); key('rule-mode-1')
    for s in ['주간','휴무','야간']: shift(s)
    key('rule-position-0'); capture('custom_three_day'); key('rule-save')
    key('team-setup-rule-D'); key('rule-mode-1')
    for s in ['주간']*3+['휴무']*3+['야간']*3+['휴무']*3: shift(s)
    key('rule-position-0'); capture('custom_twelve_day'); key('rule-save')
    key('team-setup-rule-E'); key('rule-mode-2'); shift('근무')
    for i in range(5): key('rule-weekday-'+str(i))
    shift('휴무')
    for i in [5,6]: key('rule-weekday-'+str(i))
    capture('weekly_complete'); key('rule-save')
    button('저장'); capture('roster_review'); key('team-review-save'); time.sleep(.8)
    capture('mixed_roster')
    scenario('created_mixed_roster','services/database_service.dart',"""
      final c=(await DatabaseService.instance.getTeamScheduleConfig())!;
      check(c.individual && c.names.join(',')=='A,B,C,D,E','five-team independent roster');
      check(c.myTeam=='C','main team C');
      check(c.rules['B']!.shifts.length==3 && c.rules['D']!.shifts.length==12,'custom cycles persisted');
      check(c.rules['E']!.shifts.join(',')=='근무,근무,근무,근무,근무,휴무,휴무','all seven weekdays persisted');
      check(c.rules['A']!.shiftOn(DateTime.now())==c.rules['B']!.shiftOn(DateTime.now()),'overlap accepted');
    """)

def switch_team(team):
    tap('open_edit',"e.widget is Icon && (e.widget as Icon).icon==Icons.edit_outlined")
    key('team-edit-switch'); key('team-switch-'+team)
    capture('switch_to_'+team)
    button('저장'); capture('confirm_to_'+team); button('확인'); time.sleep(1)
    scenario('verify_switch_'+team,'services/database_service.dart',"""
      final service=DatabaseService.instance; final c=(await service.getTeamScheduleConfig())!;
      final main=(await service.getShiftSchedule())!; final now=DateTime.now();
      check(c.myTeam=='TEAM','selected identity');
      for(var day=-20;day<30;day++){
        final date=DateTime(now.year,now.month,now.day+day);
        check(main.getShiftForDate(date)==c.rules['TEAM']!.shiftOn(date),'calendar day $day');
      }
      final db=await service.database;
      final history=await db.query('alarm_history',where:'alarm_id=?',whereArgs:[987654]);
      check(history.length==1 && history.single['shift_type']=='주간','existing alarm history preserved');
      final alarms=await db.query('alarms',where:'type=?',whereArgs:['fixed']);
      check(alarms.isNotEmpty,'native fixed alarms created');
      for(final a in alarms){
        final date=DateTime.parse(a['date'] as String);
        check(a['shift_type']==main.getShiftForDate(date),'alarm matches selected team');
      }
      check(c.rules['B']!.shifts.length==3 && c.rules['D']!.shifts.length==12,'other rules unchanged');
    """.replace('TEAM',team))
    assert compare_os('os_after_'+team)
    capture('roster_after_'+team)

def reset_from_settings():
    adb('shell','input','keyevent','4'); time.sleep(.5)
    button('설정')
    evaluate('open_schedule_change','screens/settings_tab.dart',"""(() {
      _SettingsTabState? s; void visit(Element e){if(e is StatefulElement && e.state is _SettingsTabState)s=e.state as _SettingsTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit); s!._showChangeScheduleDialog();return 'opened';
    })()""".replace('\n',' ')); time.sleep(.5)
    key('schedule-slot-1'); button('저장'); capture('reset_warning')
    button('취소')
    scenario('cancel_keeps_roster','services/database_service.dart',"check(await DatabaseService.instance.getTeamScheduleConfig()!=null,'cancel retains roster');")
    button('저장'); button('확인'); time.sleep(1)
    scenario('settings_deletes_roster','services/database_service.dart',"""
      check(await DatabaseService.instance.getTeamScheduleConfig()==null,'settings resets roster');
      final d=await DatabaseService.instance.database;
      check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[987654])).length==1,'history remains');
    """)
    assert compare_os('os_after_settings_reset')

if __name__=='__main__':
    connect_vm()
    if sys.argv[1]=='fixture': setup_fixture()
    elif sys.argv[1]=='create': create_individual()
    elif sys.argv[1]=='finish': finish_individual()
    elif sys.argv[1]=='switch': switch_team(sys.argv[2])
    elif sys.argv[1]=='reset': reset_from_settings()
    else: raise ValueError(sys.argv[1])
