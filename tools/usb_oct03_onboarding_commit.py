import time
from usb_audit_device import evaluate, adb, compare_os, capture
from usb_audit_scenarios import scenario

# A fresh-install schedule table is required to test onboarding itself.
# Original source tables are already in the private snapshot and restored below.
evaluate('onboarding_commit_prepare','services/database_service.dart',
    "(() async {final d=await DatabaseService.instance.database;await d.delete('shift_schedule');return 'fresh onboarding schedule fixture';})()")
try:
    adb('shell','input','tap','540','2070')
    adb('shell','input','tap','540','2070')
    adb('shell','input','keyevent','KEYCODE_HOME')
    time.sleep(2)
    scenario('onboarding_double_finish_background','services/database_service.dart',"""
      final d=await DatabaseService.instance.database;
      check((await d.query('shift_schedule')).length==1,'one schedule after repeated finish');
      final templates=await d.query('shift_alarm_templates');
      check(templates.length==1 && templates.single['time']=='23:59','one template after repeated finish');
      final alarms=await d.query('alarms');
      check(alarms.length>=9,'ten-day future reservations generated');
      check((await d.rawQuery('SELECT date,count(*) n FROM alarms GROUP BY date HAVING n>1')).isEmpty,'no duplicate alarm slots');
    """)
    assert compare_os('onboarding_double_finish_os')
    adb('shell','am','start','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.MainActivity')
    capture('onboarding_double_finish_resumed')
finally:
    import usb_oct03_restore_baseline
print('PASS onboarding finish double tap/background; original DB restored.')
