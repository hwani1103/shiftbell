from pathlib import Path
import time
source=Path(__file__).with_name('usb_oct03_onboarding_flow.py').read_text(encoding='utf-8')
exec(source.split('add(0, 0, -1)')[0])
add(23,59,1)
capture('new_apk_onboarding_boundary')
adb('shell','input','keyevent','KEYCODE_BACK')
time.sleep(.5)
tap_text('^주간')
count('onboarding_back_discards_unsaved',0)
tap_text('^취소$')
for _ in range(5):
    adb('shell','input','keyevent','KEYCODE_BACK')
    time.sleep(.3)
adb('shell','am','start','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.MainActivity')
after=evaluate('export_onboarding_back_after','services/database_service.dart',
    "(() async {final d=await DatabaseService.instance.database;return jsonEncode({'schedule':await d.query('shift_schedule'),'templates':await d.query('shift_alarm_templates'),'alarms':await d.query('alarms')});})()")
assert json.loads(before)==json.loads(after)
print('PASS actual system Back discards draft; original schedule/templates/alarms unchanged.')
