import json
import re
import time
from usb_audit_device import OUT, adb, evaluate, compare_os
from usb_audit_scenarios import scenario

def notification(name):
    dump=adb('shell','dumpsys','notification','--noredact').decode('utf-8',errors='replace')
    active=dump.split('Notification List:',1)[-1].split('History Notification List:')[0]
    rows=[line.strip() for line in active.splitlines() if 'NotificationRecord(' in line and 'pkg=com.hwani1103.shiftbell.dev ' in line and 'id=8888 ' in line]
    (OUT/(name+'.json')).write_text(json.dumps({'active_pre_alarm_count':len(rows)}),encoding='utf-8')
    print(name,len(rows),flush=True)
    return len(rows)

scenario('r3_guard_boundary_create','providers/alarm_provider.dart','''
final now=DateTime.now();final at=now.add(const Duration(minutes:20,seconds:18));
final n=AlarmNotifier();try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
check(at.isAfter(now.add(const Duration(minutes:20))),'future alarm outside 20 minute window');
''')
try:
    assert notification('r3_guard_outside')==0
    time.sleep(22)
    assert notification('r3_guard_inside')==1
finally:
    scenario('r3_guard_boundary_delete','providers/alarm_provider.dart','''
final d=await DatabaseService.instance.database;final n=AlarmNotifier();
try{for(final r in await d.query('alarms',where:"type='custom' AND preset_slot IS NULL")){await n.deleteAlarm(r['id'] as int,DateTime.parse(r['date'] as String));}
check((await d.query('alarms',where:"type='custom' AND preset_slot IS NULL")).isEmpty,'boundary fixture removed');}finally{n.dispose();}
''')
assert notification('r3_guard_deleted')==0
assert compare_os('r3_guard_boundary_os')
