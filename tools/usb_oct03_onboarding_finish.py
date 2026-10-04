import json
import time
from usb_audit_device import evaluate, adb, tap_text, capture, compare_os, OUT

def delete_first():
    raw = evaluate('onboarding_delete_position', 'screens/onboarding_screen.dart', """(() {
      final points=<String>[];
      void visit(Element e){if(e.widget is IconButton && (e.widget as IconButton).icon is Icon &&
        ((e.widget as IconButton).icon as Icon).icon==Icons.delete){
          final box=e.findRenderObject() as RenderBox;final p=box.localToGlobal(box.size.center(Offset.zero));
          final ratio=MediaQuery.devicePixelRatioOf(e);points.add('${p.dx*ratio},${p.dy*ratio}');
        }e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);return points.first;})()""".replace('\n',' '), wait=False)
    x, y = [str(round(float(v))) for v in raw.split(',')]
    adb('shell','input','tap',x,y)
    time.sleep(.25)

delete_first()
tap_text('^알람 추가$')
evaluate('onboarding_readd_boundary', 'widgets/alarm_time_editor.dart', """(() {
  void visit(Element e){if(e is StatefulElement && e.state is AlarmTimePickerState){
    final s=e.state as AlarmTimePickerState;s.setState((){s._hour=23;s._minute=59;s._dayOffset=1;});
  }e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return '23:59 next day';})()""".replace('\n',' '),wait=False)
tap_text('^확인$')
capture('onboarding_readded_fifth')
for _ in range(5):
    delete_first()
tap_text('^저장$')
tap_text('^주간')
empty = evaluate('onboarding_empty_saved', 'screens/onboarding_screen.dart', """(() {
  int? count;void visit(Element e){if(e is StatefulElement && e.state is _AlarmTimeDialogState){count=(e.state as _AlarmTimeDialogState)._alarms.length;}e.visitChildren(visit);}
  WidgetsBinding.instance.rootElement!.visitChildren(visit);return '$count';})()""".replace('\n',' '),wait=False)
assert empty == '0'
tap_text('^취소$')
after = evaluate('export_onboarding_draft_after', 'services/database_service.dart',
    "(() async {final d=await DatabaseService.instance.database;return jsonEncode({'schedule':await d.query('shift_schedule'),'templates':await d.query('shift_alarm_templates'),'alarms':await d.query('alarms')});})()")
before = json.loads((OUT/'export_onboarding_before.vm.json').read_text(encoding='utf-8'))['valueAsString']
assert json.loads(after) == json.loads(before)
# One silent 23:59 template, so no fixture will ring before baseline restoration.
tap_text('^주간')
tap_text('^알람 추가$')
evaluate('onboarding_finish_fixture_time','widgets/alarm_time_editor.dart',"""(() {
  void visit(Element e){if(e is StatefulElement && e.state is AlarmTimePickerState){final s=e.state as AlarmTimePickerState;s.setState((){s._hour=23;s._minute=59;s._dayOffset=0;});}e.visitChildren(visit);}
  WidgetsBinding.instance.rootElement!.visitChildren(visit);return 'safe future time';})()""".replace('\n',' '),wait=False)
tap_text('^확인$')
tap_text('무음$')
tap_text('^저장$')
capture('onboarding_before_finish')
print('PASS: boundary draft edits/cancel, five cap, deletion/re-add, empty save, unchanged original DB. Ready for finish double-tap.')
