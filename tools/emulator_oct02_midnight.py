import time
from datetime import datetime
from usb_audit_device import SERIAL,adb,OUT,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
adb('shell','cmd','alarm','set-timezone','Asia/Seoul')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-06-30T23:58:00+09:00').timestamp()*1000)))
scenario('midnight_delete_prepare','providers/alarm_provider.dart',"""
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final d=await DatabaseService.instance.database;
 check((await d.query('shift_alarm_templates')).isNotEmpty,'fixed templates exist before all-delete');
 check((await d.query('alarms')).isNotEmpty,'alarms exist before all-delete');
 final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}
 check((await d.query('alarms')).isEmpty && (await d.query('shift_alarm_templates')).isEmpty,'all-delete committed');
 await kAlarmChannel.invokeMethod('triggerGuardCheck');
 """)
assert compare_os('midnight_delete_before_os')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-06-30T23:59:55+09:00').timestamp()*1000)))
time.sleep(12)
scenario('midnight_delete_after','services/database_service.dart',"""
 final now=DateTime.now();check(now.month==7 && now.day==1,'real emulator clock crossed month boundary');
 final d=await DatabaseService.instance.database;
 check((await d.query('alarms')).isEmpty && (await d.query('shift_alarm_templates')).isEmpty,'no resurrection after midnight');
 """)
log=adb('logcat','-d','-s','AlarmGuardReceiver','AlarmRefreshUtil','AlarmRefreshEngine').decode('utf-8',errors='replace')
(OUT/'midnight_after_native.log').write_text(log,encoding='utf-8')
assert compare_os('midnight_delete_after_os')
print('PASS no resurrection across actual emulator midnight; inspect native midnight trigger log')
