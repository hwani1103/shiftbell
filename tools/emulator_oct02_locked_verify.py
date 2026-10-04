import json

from usb_audit_device import OUT, compare_os, evaluate
from usb_audit_scenarios import scenario

ident = int(json.loads((OUT / 'locked_ring_create.vm.json').read_text(encoding='utf-8'))['valueAsString'])
scenario('locked_ring_dismiss', 'services/database_service.dart',
    f"final d=await DatabaseService.instance.database;"
    f"check((await d.query('alarms',where:'id=?',whereArgs:[{ident}])).isEmpty,'ring row removed');"
    f"check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one dismissal history');")
assert compare_os('locked_ring_after_os')
print('PASS actual secure keyguard full-screen alarm dismissed through visible button')
