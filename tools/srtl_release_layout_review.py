"""Layout-only SRTL review; route and onboarding draft changes, no saves."""
import os,json,time
from pathlib import Path
assert os.environ['SHIFTBELL_AUDIT_SERIAL'].startswith('localhost:')
from usb_audit_device import OUT,adb,connect_vm,capture,PACKAGE
from srtl_current_audit import ev,invoke,back
MANIFEST=json.loads((OUT/'manifest.json').read_text()) if (OUT/'manifest.json').exists() else []
GEOMETRY=r"""(() {
 final rows=<String>[];
 final win=WidgetsBinding.instance.platformDispatcher.views.first;
 final screenH=win.physicalSize.height/win.devicePixelRatio;
 final screenW=win.physicalSize.width/win.devicePixelRatio;
 void visit(Element e){
 if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
 if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;

 if(e.widget is Text){final w=e.widget as Text;final r=e.findRenderObject();
 if(w.data!=null && r is RenderBox && r.hasSize){
 final pos=r.localToGlobal(Offset.zero);
 if(pos.dy>=0 && pos.dy<screenH && pos.dx<screenW){
 final defaults=e.getInheritedWidgetOfExactType<DefaultTextStyle>();
 final style=(defaults?.style??const TextStyle()).merge(w.style);
 final painter=TextPainter(text:TextSpan(text:w.data,style:style),textDirection:e.getInheritedWidgetOfExactType<Directionality>()!.textDirection,
 textScaler:w.textScaler??(e.getInheritedWidgetOfExactType<MediaQuery>()?.data.textScaler??TextScaler.noScaling),maxLines:w.maxLines??defaults?.maxLines,
 ellipsis:w.overflow==TextOverflow.ellipsis?'…':null)..layout(maxWidth:(w.softWrap??defaults?.softWrap??true)?r.size.width:double.infinity);
 final lines=painter.computeLineMetrics();
 final orphan=lines.length>1 && lines.last.width<(style.fontSize??14)*2.2;
 rows.add([w.data!.replaceAll('\n',' ').replaceAll('\t',' '),pos.dx,pos.dy,r.size.width,r.size.height,lines.length,orphan,painter.didExceedMaxLines].join('\t'));
 painter.dispose();
 }}
 }
 e.visitChildren(visit);
 }
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 return rows.join('\n');
})()"""
def check(name, bottom=False):
 if bottom:
  moved=ev(name+'_scroll','main.dart',r"""(() {
  var moved=false;void visit(Element e){
   if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
   if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
  
   if(e is StatefulElement && e.state is ScrollableState){final p=(e.state as ScrollableState).position;
   if(p.hasContentDimensions && p.axis==Axis.vertical && p.maxScrollExtent.isFinite && p.maxScrollExtent>5){p.jumpTo(p.maxScrollExtent);moved=true;}}
   e.visitChildren(visit);
  }WidgetsBinding.instance.rootElement!.visitChildren(visit);return moved.toString();
  })()""")
  if moved!='true':return
  time.sleep(.15)
 text=ev(name+'_geometry','screens/settings_tab.dart',GEOMETRY)
 (OUT/(name+'.tsv')).write_text(text,encoding='utf-8')
 capture(name)
 MANIFEST[:]=[r for r in MANIFEST if r['screen']!=name]
 MANIFEST.append({'screen':name,'file':name+'.png','geometry':name+'.tsv'})
 (OUT/'manifest.json').write_text(json.dumps(MANIFEST,indent=2),encoding='utf-8')
 print('CHECKED',len(MANIFEST),name,flush=True)
def route(lib,widget):
 ev('route_'+widget.split('(')[0],lib,"""(() {
 NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 nav!.pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>WIDGET),(_)=>false);
 return 'layout route';
 })()""".replace('WIDGET',widget));time.sleep(.65)
ROUTES=[('settings','settings_tab','SettingsTab()'),('next_alarm','next_alarm_tab','NextAlarmTab()'),
 ('work_hours','work_hours_settings_screen','WorkHoursSettingsScreen()'),
 ('theme_picker','calendar_theme_picker_screen','CalendarThemePickerScreen()'),
 ('roster','all_shifts_view','AllShiftsView()'),('history','all_alarms_history_view','AllAlarmsHistoryView()'),
 ('notes','memo_list_view','MemoListView()'),('help','help_screen','HelpScreen()'),('privacy','privacy_policy_screen','PrivacyPolicyScreen()'),('backup','settings_tab','SettingsTab(backupOnly:true)'),('additional','settings_tab','SettingsTab(additionalFeatures:true)')]

def modal(lib,widget):
 ev('modal_'+widget.split('(')[0],lib,"""(() {
 NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 showDialog(context:nav!.context,builder:(_)=>WIDGET);return 'draft dialog';
 })()""".replace('WIDGET',widget));time.sleep(.65)

def seed(tag):
 names={'en-US':['Day','Night','Afternoon Shift','Off'],'de-DE':['Tag','Nacht','Spätschicht','Frei'],'pt-BR':['Dia','Noite','Turno da tarde','Folga'],'hi-IN':['दिन','रात्रि','दोपहर की पाली','छुट्टी'],'ko-KR':['주간','야간','오후근무','휴무']}[tag]
 ev('fixture_guidance','main.dart',"""(() async {final p=await SharedPreferences.getInstance();for(final key in ['permissions_requested','welcome_popup_shown','shift_assign_tutorial_shown','condition_tab_tutorial_shown','schedule_tab_tutorial_shown','one_touch_alarm_tutorial_shown'])await p.setBool(key,true);return 'guidance flags only';})()""")
 ev('fixture_schedule','services/database_service.dart',"""(() async {final names=NAMES;await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(id:1,isRegular:true,pattern:[names[0],names[0],names[3],names[3],names[1],names[1],names[3],names[3],names[2],names[2],names[3],names[3]],todayIndex:0,startDate:DateTime(2026,10,1),shiftTypes:names,activeShiftTypes:names));return 'localized schedule; no alarm registrations';})()""".replace('NAMES',json.dumps(names,ensure_ascii=False)))
 route('main.dart','const MainScreen(initialIndex:2)')
 ev('fixture_refresh','main.dart',"""(() async {NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);await ProviderScope.containerOf(nav!.context,listen:false).read(scheduleProvider.notifier).refresh();return 'refreshed';})()""")

def run():
 connect_vm()
 os.environ['SHIFTBELL_AUDIT_DDS_URL']=json.loads((OUT/'vm.json').read_text())['uri']
 for tag in os.environ.get('REVIEW_LANGUAGES','de-DE,pt-BR,hi-IN,en-US,ko-KR').split(','):
  adb('shell','cmd','locale','set-app-locales',PACKAGE,'--locales',tag);time.sleep(1);connect_vm();seed(tag)
  for opened in [False,True]:
   if os.environ.get('REVIEW_GROUP') and tag+('_open' if opened else '_closed') not in os.environ['REVIEW_GROUP'].split(','):continue
   adb('shell','cmd','device_state','state','3' if opened else '0');time.sleep(1)
   adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard')
   prefix=tag+('_open_' if opened else '_closed_')
   tasks=os.environ.get('REVIEW_TASKS','alarm,onboarding,routes,dialogs').split(',')
   if 'alarm' in tasks:
    route('screens/settings_tab.dart','SettingsTab()')
    modal('screens/settings_tab.dart',"_ShiftAlarmEditDialog(shift:'Afternoon Shift',initialAlarms:[AlarmSetting(time:const TimeOfDay(hour:8,minute:30),alarmTypeId:1)],onSave:(_){})")
    check(prefix+'alarm_edit');check(prefix+'alarm_edit_bottom',True)
    route('screens/settings_tab.dart','SettingsTab()')
    modal('widgets/alarm_time_editor.dart',"AlarmTimePicker(shiftName:'Afternoon Shift',initialTime:const TimeOfDay(hour:8,minute:30),alarmTypeId:1,onTypeChanged:(_){},onTimeSelected:(_,__)async{})")
    check(prefix+'alarm_time');check(prefix+'alarm_time_bottom',True)
   if 'onboarding' in tasks:
    route('screens/onboarding_screen.dart','OnboardingScreen()')
    for step in [0,1,2,3]:
     ev(prefix+'onboard_step_'+str(step),'screens/onboarding_screen.dart',"""(() {
     _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
     WidgetsBinding.instance.rootElement!.visitChildren(visit);
     s!.setState((){s!._pattern=List.generate(8,(i)=>s!._baseShiftTypes[i%s!._baseShiftTypes.length]);s!._todayIndex=0;s!._step=STEP;});return 'draft only';
     })()""".replace('STEP',str(step)))
     time.sleep(.3);check(prefix+'onboarding_'+str(step));check(prefix+'onboarding_'+str(step)+'_bottom',True)
   if 'routes' in tasks:
    for label,lib,widget in ROUTES+[('permissions','permission_intro_screen','PermissionIntroScreen()')]:
     route('screens/'+lib+'.dart',widget);check(prefix+label);check(prefix+label+'_bottom',True)
   if 'dialogs' in tasks:
    for label,method in [('schedule_menu','_showScheduleSettingsMenu()'),('schedule_change','_showChangeScheduleDialog()'),('shift_names','_showEditShiftNamesDialog()'),('shift_colors','_showEditShiftColorsDialog()'),('alarm_sounds','_showAlarmTypeDialog()'),('fixed_alarms','_showEditFixedAlarmsScreen()')]:
     route('screens/settings_tab.dart','SettingsTab()')
     invoke('screens/settings_tab.dart','_SettingsTabState',method)
     check(prefix+label);check(prefix+label+'_bottom',True)
if __name__=='__main__':run()
