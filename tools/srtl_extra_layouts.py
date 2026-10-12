import os
"""Read-only UI drafts on the explicitly selected SRTL dev device.

Draft state injection is for layout coverage; it is not counted as user-flow proof.
"""
import time,os
from srtl_current_audit import ev, fold, locale, tab, push, back, inspect, invoke
from usb_audit_device import adb, connect_vm
from usb_team_rules_audit import tap


def keyboard(name):
    tap(name+'_field', 'e.widget is TextField', 'main.dart')
    time.sleep(1)
    inset=ev(name+'_ime','main.dart', "WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom.toString()")
    if float(inset)<=0:raise RuntimeError('Keyboard did not open: '+name)
    inspect(name+'_keyboard')
    adb('shell','input','keyevent','KEYCODE_BACK');time.sleep(.4)


def bottom(name):
    result=ev(name+'_scroll','main.dart',"""(() {
      final positions=<ScrollPosition>[];
      void visit(Element e){
        if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
        if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
        if(e is StatefulElement && e.state is ScrollableState){
          final p=(e.state as ScrollableState).position;
          if(p.hasContentDimensions && p.axis==Axis.vertical && p.maxScrollExtent.isFinite)positions.add(p);
        }e.visitChildren(visit);
      }WidgetsBinding.instance.rootElement!.visitChildren(visit);
      for(final p in positions){p.jumpTo(p.maxScrollExtent);}
      return positions.map((p)=>'${p.pixels}/${p.maxScrollExtent}').join(',');
    })()""")
    time.sleep(.3)
    if any(float(part.split('/')[1]) > .5 for part in result.split(',') if '/' in part):
        inspect(name+'_bottom')
    else:
        print(name, 'no vertical overflow; bottom equals initial viewport', flush=True)
    return result


def run():
    connect_vm()
    ev('layout_tutorials_already_reviewed','main.dart',"""(() async {
      final p=await SharedPreferences.getInstance();
      for(final key in ['welcome_popup_shown','shift_assign_tutorial_shown','condition_tab_tutorial_shown','schedule_tab_tutorial_shown','one_touch_alarm_tutorial_shown'])await p.setBool(key,true);
      return 'hide previously reviewed first-use guidance for unobscured layout checks';
    })()""")
    tab(2)
    ev('extra_five_custom_alarms','screens/calendar_tab.dart',"""(() async {
      _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      final presets=[for(var i=0;i<5;i++)s!.ref.read(customAlarmPresetsProvider)[i].copyWith(time:'23:0$i',alarmTypeId:3)];
      await s!.ref.read(customAlarmPresetsProvider.notifier).saveAll(presets);
      for(var i=0;i<5;i++){await CustomAlarmService.instance.assign(DateTime(2026,10,3),presets[i],i);}
      return 'five preset slots and five custom alarms seeded';
    })()""")
    for lang in ['ko-KR','en-US']:
        locale(lang)
        for opened in [False,True]:
            group=lang+('_open' if opened else '_closed')
            selected=os.environ.get('SRTL_EXTRA_GROUPS')
            if selected and group not in selected.split(','):continue
            fold(opened)
            adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(1)
            prefix=lang+('_open_' if opened else '_closed_')+'extra_'
            tab(4)
            for method,label in [('_showAlarmTypeDialog()','fixed_sound_settings'),('_showEditFixedAlarmsScreen()','fixed_alarm_cards'),('_showScheduleSettingsMenu()','updated_settings_menu')]:
                invoke('screens/settings_tab.dart','_SettingsTabState',method)
                inspect(prefix+label);bottom(prefix+label);back()
            tab(2)
            invoke('screens/calendar_tab.dart','_CalendarTabState',
                   '_showDayDetailPopup(DateTime(2026,10,3),s!.ref.read(scheduleProvider).value!)')
            inspect(prefix+'day_many_alarms');keyboard(prefix+'day_memo');bottom(prefix+'day_many_alarms');back()
            for method,label in [('_showMonthYearPicker()','month_picker'),
                                 ('_showWeeklyWorkHoursSheet()','week_hours'),
                                 ('_showMonthlyOvertimeSheet(DateTimeRange(start:DateTime(2026,10,1),end:DateTime(2026,10,31)))','month_ot')]:
                invoke('screens/calendar_tab.dart','_CalendarTabState',method)
                inspect(prefix+label);bottom(prefix+label);back()
            if lang=='ko-KR':
                invoke('screens/calendar_tab.dart','_CalendarTabState','_selectAlarmPreset(0)')
                invoke('screens/calendar_tab.dart','_CalendarTabState','_editAlarmPreset(delete:false)')
                inspect(prefix+'one_touch_assigned_edit_guard');back()
                invoke('screens/calendar_tab.dart','_CalendarTabState','_backFromAlarmPanel()')
                tab(1);bottom(prefix+'schedule_many')
                invoke('screens/schedule_management_tab.dart','_TimeAxisPickerState','_openCreateSheet(540)')
                inspect(prefix+'schedule_create');keyboard(prefix+'schedule_create');bottom(prefix+'schedule_create');back()
            tab(4);bottom(prefix+'settings')
            invoke('screens/settings_tab.dart','_SettingsTabState','_showEditShiftNamesDialog()')
            keyboard(prefix+'shift_name');back()
            push('screens/friend_list_screen.dart','FriendListScreen()')
            inspect(prefix+'friends');back()
            push('screens/friend_calendar_view.dart',"FriendCalendarView(friendName:'Colleague Work Schedule',data:FriendScheduleData(ownerName:'SRTL',isRegular:true,pattern:['Early Day Shift','Late Night Shift','Day Off'],todayIndex:0,startDate:DateTime(2026,10,3),shiftColors:const {},assignedDates:const {},updatedAt:DateTime.now()))")
            inspect(prefix+'friend_in_app');bottom(prefix+'friend_in_app');back()
            push('screens/my_share_code_screen.dart','MyShareCodeScreen()')
            inspect(prefix+'share_code');bottom(prefix+'share_code');back()
            for library,widget,label in [('permission_intro_screen','PermissionIntroScreen','permissions'),('restore_interrupted_screen','RestoreInterruptedScreen','restore_interrupted')]:
                push('screens/'+library+'.dart',widget+'()');inspect(prefix+label);bottom(prefix+label);back()
            invoke('screens/settings_tab.dart','_SettingsTabState','_restoreFromBackup()')
            inspect(prefix+'restore_warning');bottom(prefix+'restore_warning');back()
            push('screens/onboarding_screen.dart','OnboardingScreen()')
            inspect(prefix+'onboarding_names')
            for step in [1,2,3]:
                ev(prefix+'onboarding_draft_'+str(step),'screens/onboarding_screen.dart',"""(() {
                  _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
                  WidgetsBinding.instance.rootElement!.visitChildren(visit);
                  s!.setState((){s!._pattern=List.generate(40,(i)=>s!._baseShiftTypes[i%s!._baseShiftTypes.length]);s!._todayIndex=39;s!._step=STEP;});
                  return '40-position unsaved draft';
                })()""".replace('STEP',str(step)))
                inspect(prefix+'onboarding_'+str(step));bottom(prefix+'onboarding_'+str(step))
            ev(prefix+'onboarding_draft_exit','screens/onboarding_screen.dart',"""(() {
              _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
              WidgetsBinding.instance.rootElement!.visitChildren(visit);
              s!.setState((){s!._step=0;});return 'unsaved draft returned to exit step';
            })()""")
            time.sleep(.5);back()
    adb('shell','settings','put','system','font_scale','1.0')


if __name__=='__main__':run()
