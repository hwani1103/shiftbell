import json,time
from pathlib import Path
from usb_audit_device import adb,connect_vm,OUT,capture
from srtl_current_audit import ev,locale,fold,tab,push,back
from srtl_numbered_captures import seed
from srtl_verified_captures import PROBE
connect_vm()
results={'intermediate':[],'postures':{},'transitions':[],'roster':[]}
def theme(name):
 return ev('extra_theme','screens/calendar_tab.dart',"""(() async {
 _CalendarTabState? s;void visit(Element e){if(e is StatefulElement&&e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.NAME);return 'selected';})()""".replace('NAME',name))
for lang in ['ko-KR','en-US']:
 locale(lang);tab(2);seed(lang);fold(False)
 for name in (['diary','underline','editorial'] if lang=='ko-KR' else ['diary']):
  theme(name)
  for scale in ['1.1','1.2']:
   adb('shell','settings','put','system','font_scale',scale);time.sleep(.8)
   value=json.loads(ev('intermediate_probe','screens/calendar_tab.dart',PROBE))
   assert value['memos'] and not value['failures'],value
   if name in ['underline','editorial']:assert value['headers'][0]['buttons']==4
   value.update(language=lang,theme=name,scale=scale)
   results['intermediate'].append(value)
   if name=='diary':capture(f'diary_{lang}_closed_{scale}')
locale('ko-KR');tab(2);theme('diary')
ev('select_fold_fixture','screens/calendar_tab.dart',"""(() {
 _CalendarTabState? s;void visit(Element e){if(e is StatefulElement&&e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);s!.setState(() {s!._focusedDay=DateTime(2026,10,1);s!._selectedDay=DateTime(2026,10,12);});return 'selected October 12 fixture';})()""")
for opened in [False,True,False]:
 fold(opened)
 state=ev('fold_state','screens/calendar_tab.dart',"""(() {
 _CalendarTabState? s;void visit(Element e){if(e is StatefulElement&&e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);final view=WidgetsBinding.instance.platformDispatcher.views.first;
 return '${s!._focusedDay.year}-${s!._focusedDay.month}|${s!._selectedDay}|${view.physicalSize}|${view.devicePixelRatio}';})()""")
 assert state.startswith('2026-10|2026-10-12'),state
 key='open' if opened else 'closed'
 results['transitions'].append({'posture':key,'state':state})
 results['postures'][key]={'state':state,'display':adb('shell','dumpsys','display').decode('utf8',errors='replace'),'window':adb('shell','dumpsys','window').decode('utf8',errors='replace')}
for lang in ['ko-KR','en-US']:
 locale(lang);tab(2);seed(lang,'individual')
 for opened in [False,True]:
  fold(opened);adb('shell','settings','put','system','font_scale','1.3');time.sleep(.7)
  push('screens/all_shifts_view.dart','AllShiftsView()')
  scroll=ev('roster_scroll_targets','main.dart',"""(() {
   final values=<String>[];
   void visit(Element e){if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;if(e.widget is TickerMode&&!(e.widget as TickerMode).enabled)return;
   if(e is StatefulElement&&e.state is ScrollableState){final p=(e.state as ScrollableState).position;if(p.hasContentDimensions&&p.maxScrollExtent.isFinite){p.jumpTo(p.maxScrollExtent);values.add('${p.axis}:${p.pixels}/${p.maxScrollExtent}');}}
   e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return values.join(',');})()""")
  time.sleep(.5)
  texts=ev('roster_visible_end','main.dart',"""(() {
   final values=<String>[];final view=WidgetsBinding.instance.platformDispatcher.views.first;final screen=Offset.zero & (view.physicalSize/view.devicePixelRatio);
   void visit(Element e){if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;if(e.widget is TickerMode&&!(e.widget as TickerMode).enabled)return;
   if(e.widget is Text){final r=e.findRenderObject();if(r is RenderBox&&r.hasSize){final rect=r.localToGlobal(Offset.zero)&r.size;if(screen.overlaps(rect))values.add((e.widget as Text).data??'');}}e.visitChildren(visit);}
   WidgetsBinding.instance.rootElement!.visitChildren(visit);return values.join('|');})()""")
  assert '31' in texts,texts
  capture(f'roster_end_{lang}_{"open" if opened else "closed"}_1.3')
  results['roster'].append({'language':lang,'posture':'open' if opened else 'closed','scroll':scroll,'visibleText':texts})
  back()
adb('shell','settings','put','system','font_scale','1.0')
locale('ko-KR');tab(2);seed('ko-KR');theme('mainWhite');fold(False)
(OUT/'extra_checks.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print('Extra checks completed')
