"""Disposable emulator: one real OS alarm while the screen is locked."""

import json
import time

from usb_audit_device import OUT, adb, compare_os, connect_vm, evaluate
from usb_audit_scenarios import scenario

connect_vm()
scenario('locked_ring_clear', 'providers/alarm_provider.dart',
         'final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}')
ident = int(evaluate('locked_ring_create', 'providers/alarm_provider.dart',
    "(() async {final at=DateTime.now().add(const Duration(seconds:18));"
    "final n=AlarmNotifier();try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',"
    "date:at,type:'snoozed',alarmTypeId:3));}finally{n.dispose();}"
    "return '${(await (await DatabaseService.instance.database).query('alarms')).single['id']}';})()"))
assert compare_os('locked_ring_before_os')
adb('shell', 'input', 'keyevent', 'KEYCODE_SLEEP')
found = False
for _ in range(30):
    time.sleep(1)
    state = adb('shell', 'dumpsys', 'activity', 'activities').decode(errors='replace')
    if 'topResumedActivity=' in state and 'AlarmActivity' in state.split('topResumedActivity=')[-1].splitlines()[0]:
        found = True
        break
(OUT / 'locked_ring_activity.txt').write_text(state, encoding='utf-8')
adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
time.sleep(1)
(OUT / 'locked_ring_screen.png').write_bytes(adb('exec-out', 'screencap', '-p'))
print('actual alarm id', ident, 'full-screen activity while locked', found)
assert found, 'OS ring did not present AlarmActivity while locked'
