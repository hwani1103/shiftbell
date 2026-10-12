import json,sys,time
from datetime import datetime
from usb_audit_device import SERIAL,adb,evaluate,OUT,compare_os,connect_vm
assert SERIAL=='emulator-5556'
mode=sys.argv[1]
expr="(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'overrides':await d.query('alarm_overrides',orderBy:'id')});})()"
if mode=='prepare':
 before=evaluate('mixed_lifecycle_baseline','services/database_service.dart',expr)
 (OUT/'mixed_lifecycle_baseline.json').write_text(before,encoding='utf-8')
elif mode=='guard':
 evaluate('mixed_guard_trigger','services/database_service.dart',"(() async {await kAlarmChannel.invokeMethod('triggerGuardCheck');return 'guard triggered';})()")
 time.sleep(3)
elif mode=='time':
 adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2027-01-01T00:01:00+09:00').timestamp()*1000)))
 time.sleep(4)
elif mode=='cold':connect_vm()
else:raise ValueError(mode)
rows=json.loads(evaluate('mixed_lifecycle_'+mode,'services/database_service.dart',expr))
assert rows==json.loads((OUT/'mixed_lifecycle_baseline.json').read_text(encoding='utf-8'))
assert compare_os('mixed_lifecycle_'+mode+'_os')
print('PASS mixed fixed/custom/snoozed+skip/set_type exact rows and OS retained:',mode)
