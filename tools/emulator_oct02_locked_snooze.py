"""Disposable emulator: real lock-screen button reserves one +5m snooze."""

import time

from usb_audit_device import adb, compare_os, connect_vm, evaluate
from usb_audit_scenarios import scenario

connect_vm()
scenario('locked_snooze_clear', 'providers/alarm_provider.dart',
         'final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}')
ident = int(evaluate('locked_snooze_create', 'providers/alarm_provider.dart',
    "(() async {final at=DateTime.now().add(const Duration(seconds:18));"
    "final n=AlarmNotifier();try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',"
    "date:at,type:'snoozed',alarmTypeId:3));}finally{n.dispose();}"
    "return '${(await (await DatabaseService.instance.database).query('alarms')).single['id']}';})()"))
assert compare_os('locked_snooze_before_os')
adb('shell', 'input', 'keyevent', 'KEYCODE_SLEEP')
found = False
for _ in range(30):
    time.sleep(1)
    state = adb('shell', 'dumpsys', 'activity', 'activities').decode(errors='replace')
    if 'topResumedActivity=' in state and 'AlarmActivity' in state.split('topResumedActivity=')[-1].splitlines()[0]:
        found = True
        break
assert found, 'secure lock full-screen activity absent'
adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
time.sleep(2)
adb('shell', 'input', 'tap', '365', '1710')
time.sleep(2)
scenario('locked_snooze_after', 'services/database_service.dart',
    f"final d=await DatabaseService.instance.database;"
    f"final rows=await d.query('alarms',where:'id=?',whereArgs:[{ident}]);"
    f"check(rows.length==1 && rows.single['type']=='snoozed','snooze row retained');"
    f"final remaining=Alarm.fromMap(rows.single).date!.difference(DateTime.now()).inSeconds;"
    f"check(remaining>=290 && remaining<=300,'snooze target near actual press +300s');"
    f"check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one snooze history');")
assert compare_os('locked_snooze_after_os')
scenario('locked_snooze_cleanup', 'providers/alarm_provider.dart',
         'final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}')
assert compare_os('locked_snooze_cleanup_os')
print('PASS actual secure keyguard full-screen +5m button, DB/OS one reservation')
