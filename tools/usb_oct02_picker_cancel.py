import json,time,re
from usb_audit_device import evaluate,tap_text,adb,capture,compare_os,OUT
def state(tag):
 return json.loads(evaluate('export_picker_'+tag,'services/backup_service.dart',
   '(() async {return (await BackupService.instance.exportAll()).encode();})()'))
before=state('before')
tap_text('^파일 선택하기$');capture('backup_picker_open')
for _ in range(6):
 top=adb('shell','dumpsys','activity','activities').decode('utf-8',errors='replace')
 if re.search(r'topResumedActivity=.*com\.hwani1103\.shiftbell\.dev/',top):break
 adb('shell','input','keyevent','KEYCODE_BACK');time.sleep(.5)
else:raise AssertionError('file picker did not close')
capture('backup_picker_cancelled')
after=state('after')
assert before['tables']==after['tables'] and before['preferences']==after['preferences']
assert compare_os('picker_cancel_os')
print('PASS actual Android file picker cancelled; all exported tables/preferences and OS reservations unchanged')
