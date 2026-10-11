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
 final painter=TextPainter(text:TextSpan(text:w.data,style:style),textDirection:(e.getInheritedWidgetOfExactType<Directionality>()?.textDirection??TextDirection.ltr),
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
 ('notes','memo_list_view','MemoListView()'),('help','help_screen','HelpScreen()'),('privacy','privacy_policy_screen','PrivacyPolicyScreen()')]
connect_vm()
for tag in os.environ.get('REVIEW_LANGUAGES','de-DE,pt-BR,hi-IN,en-US').split(','):
 adb('shell','cmd','locale','set-app-locales',PACKAGE,'--locales',tag);time.sleep(1);connect_vm()
 for opened in [False,True]:
  if os.environ.get('REVIEW_GROUP') and tag+('_open' if opened else '_closed') not in os.environ['REVIEW_GROUP'].split(','):continue
  adb('shell','cmd','device_state','state','3' if opened else '0');time.sleep(1)
  adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard')
  adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
  prefix=tag+('_open_' if opened else '_closed_')
  for label,lib,widget in ROUTES:
   try:
    route('screens/'+lib+'.dart',widget);check(prefix+label);check(prefix+label+'_bottom',True)
   except Exception as exc:
    (OUT/(prefix+label+'.error')).write_text(str(exc),encoding='utf-8');print('ERROR',prefix+label,str(exc)[:300],flush=True)
  try:
   route('screens/onboarding_screen.dart','OnboardingScreen()')
   for step in [0,1,2,3]:
    ev(prefix+'onboard_step_'+str(step),'screens/onboarding_screen.dart',"""(() {
    _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
    WidgetsBinding.instance.rootElement!.visitChildren(visit);
    s!.setState((){s!._pattern=List.generate(8,(i)=>s!._baseShiftTypes[i%s!._baseShiftTypes.length]);s!._todayIndex=0;s!._step=STEP;});return 'draft only';
    })()""".replace('STEP',str(step)))
    check(prefix+'onboarding_'+str(step));check(prefix+'onboarding_'+str(step)+'_bottom',True)
  except Exception as exc:print('ERROR onboarding',prefix,str(exc)[:300],flush=True)
  for label,method in [('schedule_menu','_showScheduleSettingsMenu()'),('schedule_change','_showChangeScheduleDialog()'),('shift_names','_showEditShiftNamesDialog()'),('shift_colors','_showEditShiftColorsDialog()'),('alarm_sounds','_showAlarmTypeDialog()'),('fixed_alarms','_showEditFixedAlarmsScreen()')]:
   try:
    route('screens/settings_tab.dart','SettingsTab()')
    invoke('screens/settings_tab.dart','_SettingsTabState',method)
    check(prefix+label);check(prefix+label+'_bottom',True)
   except Exception as exc:
    (OUT/(prefix+label+'.error')).write_text(str(exc),encoding='utf-8');print('ERROR',prefix+label,str(exc)[:300],flush=True)
