import json,time
from usb_audit_device import adb,evaluate,tap_text,capture,OUT,compare_os
from usb_audit_scenarios import scenario
def state(tag):
 return json.loads(evaluate('export_unsupported_'+tag,'services/backup_service.dart','(() async {return (await BackupService.instance.exportAll()).encode();})()'))
before=state('before')
payload=dict(before);payload['schemaVersion']=999
name='000_Audit_unsupported_20261002.json';local=OUT/name
local.write_text(json.dumps(payload,ensure_ascii=False),encoding='utf-8')
remote='/sdcard/Download/ShiftBell/'+name
adb('push',str(local),remote)
try:
 tap_text('^백업 데이터 불러오기');tap_text('^파일 선택하기$');tap_text('^'+name.replace('.','\\.')+'$')
 capture('unsupported_backup_confirmation')
 tap_text('^복구하기$');time.sleep(1)
 capture('unsupported_backup_rejected')
 after=state('after')
 assert before['tables']==after['tables'] and before['preferences']==after['preferences']
 scenario('unsupported_no_job','services/restore_coordinator.dart',"""
 check(!await RestoreCoordinator.instance.hasPendingJob(),'invalid schema creates no restore job');
 check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'invalid schema leaves no gate');
 """)
 assert compare_os('unsupported_backup_os')
 assert adb('exec-out','cat',remote)==local.read_bytes(),'selected source file unchanged'
 print('PASS unsupported schema999 rejected after real confirmation; DB/prefs/OS/source file unchanged')
finally:adb('shell','rm','--',remote)
