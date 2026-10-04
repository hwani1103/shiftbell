import json,sys
from usb_audit_device import SERIAL,adb,OUT,PACKAGE,ROOT
assert SERIAL=='emulator-5556','never uninstall the user phone app'
remote='/sdcard/Download/ShiftBell/ShiftBell_Backup_dev_auto_270101_000154.json'
if sys.argv[1]=='prepare':
 raw=adb('exec-out','cat',remote)
 payload=json.loads(raw)
 assert payload['tables']['shift_schedule'][0]['pattern']=='Night'
 assert not payload['tables']['friends']
 (OUT/'reinstall_original_backup.json').write_bytes(raw)
 result=adb('uninstall',PACKAGE);assert b'Success' in result,result
 assert adb('exec-out','cat',remote)==raw,'uninstall must preserve source backup'
 result=adb('install',str(ROOT/'build/app/outputs/flutter-apk/app-dev-debug.apk'),timeout=150)
 assert b'Success' in result,result
 print('PASS emulator dev reinstall preserves original Downloads backup byte-for-byte; restore still pending')
else:raise ValueError(sys.argv[1])
