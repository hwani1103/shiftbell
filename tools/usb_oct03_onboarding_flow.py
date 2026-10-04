"""Real device onboarding draft edits; no completion/save to user's schedule."""
import json
from usb_audit_device import evaluate, tap_text, adb, capture, OUT

before = evaluate('export_onboarding_before', 'services/database_service.dart',
    "(() async {final d=await DatabaseService.instance.database;return jsonEncode({'schedule':await d.query('shift_schedule'),'templates':await d.query('shift_alarm_templates'),'alarms':await d.query('alarms')});})()")
evaluate('onboarding_open', 'screens/onboarding_screen.dart', """(() {
 NavigatorState? nav;
 void visit(Element e){if(e is StatefulElement && e.state is NavigatorState){nav=e.state as NavigatorState;}e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 nav!.push(MaterialPageRoute(builder:(_)=>const OnboardingScreen()));return 'opened onboarding draft';})()""".replace('\n',' '), wait=False)
tap_text('^다음$')
tap_text('^주간$')
tap_text('^다음$')
tap_text('주간$')
tap_text('^다음$')
tap_text('^주간')
capture('onboarding_alarm_empty')

def count(name, expected):
    result = evaluate(name, 'screens/onboarding_screen.dart', """(() {
      _AlarmTimeDialogState? state;
      void visit(Element e){if(e is StatefulElement && e.state is _AlarmTimeDialogState){state=e.state as _AlarmTimeDialogState;}e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      return '${state!._alarms.length}';})()""".replace('\n',' '), wait=False)
    assert int(result) == expected

def add(hour, minute, offset):
    tap_text('^알람 추가$')
    # Time input control combinations are covered locally; inject the boundary
    # into the real picker state then use its actual visible confirmation button.
    evaluate(f'onboarding_picker_{hour}_{minute}_{offset}', 'widgets/alarm_time_editor.dart', f"""(() {{
      AlarmTimePickerState? state;
      void visit(Element e){{if(e is StatefulElement && e.state is AlarmTimePickerState){{state=e.state as AlarmTimePickerState;}}e.visitChildren(visit);}}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      state!.setState((){{state!._hour={hour};state!._minute={minute};state!._dayOffset={offset};}});
      return 'boundary picker set; confirmation via actual UI';}})()""".replace('\n',' '), wait=False)
    tap_text('^확인$')

add(0, 0, -1)
tap_text('^저장$')
tap_text('^주간')
count('onboarding_saved_one', 1)
add(0, 0, 0)
tap_text('^취소$')
tap_text('^주간')
count('onboarding_cancel_kept_one', 1)
for h, m, offset in [(0,0,0),(0,0,1),(23,59,-1),(23,59,0)]:
    add(h,m,offset)
count('onboarding_limit_five', 5)
capture('onboarding_five_limit')
# Actual delete controls expose a tooltip through semantics.
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
(OUT/'onboarding_five_ui.xml').write_bytes(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
print('Draft has five alarms. Continue deletion checks from captured UI; user DB not saved.')
