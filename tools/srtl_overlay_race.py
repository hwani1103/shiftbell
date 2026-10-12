"""Send both real native button taps; Android input dispatch remains serialized."""
import json,re,time,xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from srtl_ring_checks import prepare,action_point
from usb_audit_device import adb,OUT,PACKAGE,connect_vm,compare_os
from usb_audit_scenarios import scenario

prepare('srtl_overlay_race_visible',False,3)
ident=json.loads((OUT/'ring_current.json').read_text(encoding='utf8'))['id']
points=[]
for name in ['dismiss','snooze']:
    x,y=action_point(name)
    points.append((str(x),str(y)))
with ThreadPoolExecutor(max_workers=2) as pool:
    futures=[pool.submit(adb,'shell','input','tap',x,y) for x,y in points]
    for f in futures:f.result()
time.sleep(1)
adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity');time.sleep(1);connect_vm()
scenario('srtl_overlay_race_contract','services/database_service.dart',f'''
 final d=await DatabaseService.instance.database;
 check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'ring ended');
 check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one winning result');
 final rows=await d.query('alarms',where:'id=?',whereArgs:[{ident}]);
 check(rows.isEmpty || (rows.length==1 && rows.single['type']=='snoozed'),'one valid final state');
''')
assert compare_os('srtl_overlay_race_os')
print('PASS concurrent native button requests; Android dispatch is serialized.',flush=True)
