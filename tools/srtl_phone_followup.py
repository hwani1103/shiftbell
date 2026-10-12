"""Open phone viewport checks: narrow headers, memo IME, roster last column.

Synthetic SRTL fixture only. No folding or cover UI operations.
"""
import json,time,os
from usb_audit_device import connect_vm,adb,OUT,capture
from srtl_current_audit import ev,locale,tab,invoke,back,push
from srtl_numbered_captures import seed
from srtl_verified_captures import PROBE
from srtl_extra_layouts import keyboard
assert os.environ.get('SRTL_POSTURE')=='open', 'Set SRTL_POSTURE=open'
connect_vm();results={'headers':[],'keyboard':[],'roster':[]}
def theme(name):
 ev('followup_theme','screens/calendar_tab.dart',"""(() async {_CalendarTabState? s;void visit(Element e){if(e is StatefulElement&&e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.NAME);return 'selected';})()""".replace('NAME',name))
locale('ko-KR');tab(2);seed('ko-KR')
for name in ['underline','editorial']:
 theme(name)
 for scale in ['1.1','1.2']:
  adb('shell','settings','put','system','font_scale',scale);time.sleep(.7)
  r=json.loads(ev('header_intermediate','screens/calendar_tab.dart',PROBE));assert r['memos'] and not r['failures'] and r['headers'][0]['buttons']==4,r
  results['headers'].append({**r,'theme':name,'scale':scale})
for lang in ['ko-KR','en-US']:
 locale(lang);tab(2);seed(lang);theme('mainWhite')
 for scale in ['1.0','1.3']:
  adb('shell','settings','put','system','font_scale',scale);time.sleep(.7)
  invoke('screens/calendar_tab.dart','_CalendarTabState','_showDayDetailPopup(DateTime(2026,10,3),s!.ref.read(scheduleProvider).value!)')
  name=f'memo_popup_{lang}_open_{scale}';capture(name);keyboard(name)
  results['keyboard'].append({'language':lang,'scale':scale,'opened':True});back()
 seed(lang,'individual');adb('shell','settings','put','system','font_scale','1.3');time.sleep(.7)
 push('screens/all_shifts_view.dart','AllShiftsView()')
 scroll=ev('roster_bottom_scroll','main.dart',"""(() {final values=<String>[];void visit(Element e){if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;if(e.widget is TickerMode&&!(e.widget as TickerMode).enabled)return;if(e is StatefulElement&&e.state is ScrollableState){final p=(e.state as ScrollableState).position;if(p.hasContentDimensions&&p.maxScrollExtent.isFinite){p.jumpTo(p.maxScrollExtent);values.add('${p.axis}:${p.pixels}/${p.maxScrollExtent}');}}e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return values.join(',');})()""")
 time.sleep(.5);capture(f'roster_bottom_{lang}_open_1.3');results['roster'].append({'language':lang,'scroll':scroll});back()
(OUT/'followup_checks.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print('Followup checks finished')
