import os
"""Latest-dev SRTL audit. Explicit serial via environment; dev package only."""
import json, sys, time, os
from usb_audit_device import adb, evaluate, capture, connect_vm, OUT, PACKAGE

def ev(name, library, code):
    # VM evaluation may interrupt paint/layout. Run UI mutations after the
    # interrupted frame, rather than pushing routes or jumping scrolls in it.
    deferred = '(() async { await Future<void>.delayed(Duration.zero); return '+code.replace('\n',' ')+'; })()'
    return evaluate(name, library, deferred)

def fold(opened):
    adb('shell','cmd','device_state','state','3' if opened else '0')
    time.sleep(2)
    adb('shell','input','keyevent','KEYCODE_WAKEUP')
    adb('shell','wm','dismiss-keyguard')
    time.sleep(1)

def locale(tag):
    adb('shell','cmd','locale','set-app-locales',PACKAGE,'--locales',tag)
    time.sleep(2)
    connect_vm()

def inspect(name):
    sweep=os.environ.get('SRTL_INSPECT_SCALES')
    if sweep:
        original=adb('shell','settings','get','system','font_scale').decode().strip()
        audit_scale=os.environ.get('SRTL_AUDIT_SCALE','0')
        capture_settle=os.environ.get('SRTL_CAPTURE_SETTLE','.8')
        os.environ['SRTL_CAPTURE_SETTLE']='.2'
        os.environ.pop('SRTL_INSPECT_SCALES')
        try:
            for scale in sweep.split(','):
                adb('shell','settings','put','system','font_scale',scale)
                time.sleep(.45)
                if name.endswith('_bottom'):
                    ev(name+'_rescroll_'+scale,'main.dart',"""(() {
                      void visit(Element e){
                        if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
                        if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
                        if(e is StatefulElement && e.state is ScrollableState){
                          final p=(e.state as ScrollableState).position;
                          if(p.hasContentDimensions && p.axis==Axis.vertical && p.maxScrollExtent.isFinite)p.jumpTo(p.maxScrollExtent);
                        }e.visitChildren(visit);
                      }WidgetsBinding.instance.rootElement!.visitChildren(visit);return 'bottom after scale relayout';
                    })()""")
                os.environ['SRTL_AUDIT_SCALE']=audit_scale if scale=='1.3' else '0'
                inspect(name+'_sweep_'+scale)
        finally:
            adb('shell','settings','put','system','font_scale',original)
            time.sleep(.3)
            os.environ['SRTL_INSPECT_SCALES']=sweep
            os.environ['SRTL_AUDIT_SCALE']=audit_scale
            os.environ['SRTL_CAPTURE_SETTLE']=capture_settle
        return
    if os.environ.get('SRTL_CAPTURE_ONLY') == '1':
        if os.environ.get('SRTL_AUDIT_SCALE') == '1':
            metrics=ev(name+'_scale','main.dart',"""(() {
              final scales=<double>{};var count=0;
              void visit(Element e){
                if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
                if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
                if(e.widget is Text){
                  final media=MediaQuery.maybeOf(e);
                  if(media!=null){scales.add(media.textScaler.scale(16)/16);count++;}
                }e.visitChildren(visit);
              }WidgetsBinding.instance.rootElement!.visitChildren(visit);
              if(scales.any((s)=>s>1.30001))throw StateError('Scale above app maximum: $scales');
              return 'visibleTextCount=$count inheritedScale16=$scales';
            })()""")
            (OUT/(name+'_scale.txt')).write_text(metrics,encoding='utf-8')
        capture(name)
        print('captured',name,flush=True)
        return
    info=ev(name+'_geometry','screens/settings_tab.dart',"""(() {
      final texts=<Map<String,dynamic>>[];
      void visit(Element e){
        if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
        if(e.widget is Text){
          final r=e.findRenderObject();
          if(r is RenderBox && r.hasSize){final p=r.localToGlobal(Offset.zero);
            texts.add({'text':(e.widget as Text).data,'x':p.dx,'y':p.dy,'w':r.size.width,'h':r.size.height});}
        }e.visitChildren(visit);
      }
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      final v=WidgetsBinding.instance.platformDispatcher.views.first;
      return {'size':[v.physicalSize.width,v.physicalSize.height],'ratio':v.devicePixelRatio,'texts':texts}.toString();
    })()""")
    (OUT/(name+'_geometry.txt')).write_text(info,encoding='utf-8')
    capture(name)

def tab(index):
    from usb_team_rules_audit import tap
    labels={0:['다음알람','Next Alarm'],1:['일정관리'],2:['달력','Calendar'],3:['수면·회복'],4:['설정','Settings']}
    values=json.dumps(labels[index],ensure_ascii=False)
    tap('nav_'+str(index), 'e.widget is Text && '+values+'.contains((e.widget as Text).data)', 'main.dart')
    time.sleep(.7)
    result=ev('verify_nav_'+str(index),'main.dart',"""(() {
      String result='missing';void visit(Element e){
        if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
        if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
        if(e is StatefulElement && e.state is _MainScreenState){
          final s=e.state as _MainScreenState;
          result=s._currentIndex.toString();
        }
        if(e.widget is BottomNavigationBar){
          final nav=e.widget as BottomNavigationBar;
          final label=nav.items[nav.currentIndex].label;
          if(!LABELS.contains(label))throw StateError('Rendered tab is '+label.toString());
        }e.visitChildren(visit);
      }WidgetsBinding.instance.rootElement!.visitChildren(visit);return result;
    })()""".replace('LABELS',values))
    if result!=str(index):raise RuntimeError('Navigation failed: '+result)

def push(library, widget):
    ev('push_'+widget.split('(')[0],library,"""(() {
      NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      Future.delayed(Duration.zero,(){nav!.push(MaterialPageRoute(builder:(_)=>WIDGET));});return 'open scheduled after current frame';
    })()""".replace('WIDGET',widget))
    time.sleep(.6)

def back():
    ev('back','main.dart',"""(() {
      NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      Future.delayed(Duration.zero,(){if(nav!.canPop())nav!.pop();});return 'back scheduled after current frame';
    })()""")
    time.sleep(.4)

def invoke(library, state, method):
    ev('open_'+method.split('(')[0],library,"""(() {
      STATE? s;void visit(Element e){if(e is StatefulElement && e.state is STATE)s=e.state as STATE;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      if(s==null)throw StateError('Missing STATE');s!.METHOD;return 'opened';
    })()""".replace('STATE',state).replace('METHOD',method))
    time.sleep(.7)

def screens():
    from srtl_extra_layouts import bottom
    from datetime import datetime
    # Cover both languages and postures at the maximum first when the lease is
    # bounded, rather than finishing every scale in only one language.
    if os.environ.get('SRTL_INSPECT_SCALES') and not os.environ.get('SRTL_SCREENS_PASS'):
        original_sweep = os.environ['SRTL_INSPECT_SCALES']
        try:
            for pass_scale in ['1.3','1.0','1.1','1.2']:
                if pass_scale not in original_sweep.split(','):continue
                os.environ['SRTL_SCREENS_PASS']='1'
                os.environ['SRTL_INSPECT_SCALES']=pass_scale
                screens()
                print('All remaining routes completed at',pass_scale,flush=True)
        finally:
            os.environ.pop('SRTL_SCREENS_PASS',None)
            os.environ['SRTL_INSPECT_SCALES']=original_sweep
        return
    def check_deadline():
        deadline_file = OUT/'screens_deadline.txt'
        if deadline_file.exists() and datetime.now() >= datetime.fromisoformat(deadline_file.read_text().strip()):
            raise TimeoutError('SRTL lease budget reached; remaining routes are NOT marked complete')
    routes=[('history','all_alarms_history_view','AllAlarmsHistoryView'),
      ('memos','memo_list_view','MemoListView'),('work_hours','work_hours_settings_screen','WorkHoursSettingsScreen'),
      ('theme_picker','calendar_theme_picker_screen','CalendarThemePickerScreen'),
      ('help','help_screen','HelpScreen'),('privacy','privacy_policy_screen','PrivacyPolicyScreen'),
      ('roster','all_shifts_view','AllShiftsView')]
    dialogs=['_showScheduleSettingsMenu()','_showChangeScheduleDialog()',
      '_showEditShiftNamesDialog()','_showEditShiftColorsDialog()',
      '_showAlarmTypeDialog()','_showEditFixedAlarmsScreen()']
    tabs=[(0,'next_alarm'),(1,'schedules'),(2,'calendar'),(3,'sleep'),(4,'settings')]
    if os.environ.get('SRTL_INSPECT_SCALES'):
        # Other suite steps cover populated schedules/sleep, main calendar,
        # roster, settings and their nested sound/fixed-alarm editors.
        tabs=[(0,'next_alarm')]
        routes=[r for r in routes if r[0]!='roster']
        dialogs=['_showChangeScheduleDialog()','_showEditShiftNamesDialog()',
                 '_showEditShiftColorsDialog()']
    for lang, postures in [('ko-KR',[False]),('en-US',[False]),('ko-KR',[True]),('en-US',[True])]:
      locale(lang)
      for opened in postures:
        fold(opened)
        for scale in os.environ.get('SRTL_SCALES','1.0,1.3').split(','):
          adb('shell','settings','put','system','font_scale',scale);time.sleep(1)
          prefix=lang+('_open_' if opened else '_closed_')+scale+'_'
          for index,label in tabs:
            check_deadline()
            if lang=='en-US' and index in [1,3]:continue
            tab(index);inspect(prefix+label)
          for label,library,widget in routes:
            check_deadline()
            push('screens/'+library+'.dart',widget+'()');inspect(prefix+label)
            bottom(prefix+label);back()
          tab(4)
          for method in dialogs:
            check_deadline()
            invoke('screens/settings_tab.dart','_SettingsTabState',method)
            inspect(prefix+method.split('(')[0]);bottom(prefix+method.split('(')[0]);back()
    adb('shell','settings','put','system','font_scale','1.0')

def fixture():
    adb('shell','input','keyevent','KEYCODE_WAKEUP')
    adb('shell','wm','dismiss-keyguard')
    adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
    time.sleep(1)
    ev('fixture_reviewed_guidance','main.dart',"""(() async {
      final p=await SharedPreferences.getInstance();
      for(final key in ['permissions_requested','welcome_popup_shown','shift_assign_tutorial_shown','condition_tab_tutorial_shown','schedule_tab_tutorial_shown','one_touch_alarm_tutorial_shown'])await p.setBool(key,true);
      return 'reviewed guidance flags';
    })()""")
    ev('fixture_schedule','services/database_service.dart',"""(() async {
      final s=DatabaseService.instance;
      await s.saveShiftSchedule(ShiftSchedule(id:1,isRegular:true,
        pattern:['주간','주간','휴무','휴무','야간','야간','휴무','휴무'],
        todayIndex:4,startDate:DateTime(2026,10,3),
        shiftTypes:['주간','야간','휴무','근무','연차','오전','오후'],activeShiftTypes:['주간','야간','휴무']));
      await s.replaceAllAlarmTemplates([for(final shift in ['주간','야간','휴무'])for(var i=0;i<5;i++)
        {'shift_type':shift,'time':'23:${40+i}','alarm_type_id':3,'day_offset':0}]);
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      final d=await s.database;
      await d.delete('date_memos',where:'date IN (?,?,?)',whereArgs:['2026-10-02','2026-10-03','2026-10-04']);
      await d.rawUpdate("UPDATE alarm_history SET scheduled_date=scheduled_date || 'T07:11:00' WHERE length(scheduled_date)=10");
      return 'test schedule';
    })()""")
    ev('fixture_main_route','main.dart',"""(() async {
      NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      await ProviderScope.containerOf(nav!.context,listen:false).read(scheduleProvider.notifier).refresh();
      nav!.pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const MainScreen(initialIndex:2)),(_)=>false);return 'main';
    })()""")
    time.sleep(1)
    ev('fixture_refresh','screens/calendar_tab.dart',"""(() async {
      _CalendarTabState? s; void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      await s!.ref.read(scheduleProvider.notifier).refresh();
      for(var day=2;day<=4;day++)for(var n=0;n<day-1;n++){
        await s!.ref.read(memoProvider.notifier).createMemo('2026-10-0$day',['병원 예약 / Clinic','가족 모임 / Family','교육 일정 / Training'][n]);
      }
      return 'schedule and one/two/three memos loaded';
    })()""")

def themes():
    for lang in os.environ.get('SRTL_LANGS','ko-KR,en-US').split(','):
      locale(lang); tab(2)
      if lang=='ko-KR':fixture()
      if lang=='en-US':
        ev('english_long_shift_fixture','screens/calendar_tab.dart',"""(() async {
          final names=['Early Day Shift','Late Night Shift','Day Off'];
          final m=ShiftSchedule(id:1,isRegular:true,pattern:[names[0],names[0],names[2],names[2],names[1],names[1],names[2],names[2]],todayIndex:4,startDate:DateTime(2026,10,3),shiftTypes:names,activeShiftTypes:names);
          await DatabaseService.instance.saveShiftSchedule(m);
          await DatabaseService.instance.replaceAllAlarmTemplates([for(final shift in names)for(var i=0;i<5;i++)
            {'shift_type':shift,'time':'23:${40+i}','alarm_type_id':3,'day_offset':0}]);
          await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
          _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);await s!.ref.read(scheduleProvider.notifier).refresh();return 'English long names';
        })()""")
      ids=['mainWhite','mainDark','minimal','materialCard','boldGrid','initialBadge','underline','eventChip','editorial','diary']
      if lang=='en-US': ids=['mainWhite','mainDark','minimal','materialCard','boldGrid','diary']
      for opened in [False,True]:
        fold(opened)
        for theme in ids:
          ev('theme_'+theme,'screens/calendar_tab.dart',"""(() async {
            _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
            WidgetsBinding.instance.rootElement!.visitChildren(visit);
            await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.THEME);
            return 'theme selected';
          })()""".replace('THEME',theme))
          inspect(lang+('_open_' if opened else '_closed_')+theme)

if __name__=='__main__':
    connect_vm()
    if sys.argv[1]=='fixture': fixture()
    elif sys.argv[1]=='inspect': inspect(sys.argv[2])
    elif sys.argv[1]=='fold': fold(sys.argv[2]=='open')
    elif sys.argv[1]=='locale': locale(sys.argv[2])
    elif sys.argv[1]=='tab': tab(int(sys.argv[2]))
    elif sys.argv[1]=='themes': themes()
    elif sys.argv[1]=='screens': screens()




