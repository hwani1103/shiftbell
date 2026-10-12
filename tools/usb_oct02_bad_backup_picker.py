import json,sys,time
from usb_audit_device import adb,evaluate,tap_text,capture,OUT,compare_os

kind=sys.argv[1]
contents={'empty':b'','truncated':b'{"schemaVersion":2,"tables":',
 'foreign':b'{"otherApplication":true}', 'oversized':b' '*(16*1024*1024+1)}
assert kind in contents
name='000_Audit_'+kind+'_20261002.json'
path=OUT/name;path.write_bytes(contents[kind])
remote='/sdcard/Download/ShiftBell/'+name
adb('push',str(path),remote)
def state(tag):
 return json.loads(evaluate('export_bad_picker_'+kind+'_'+tag,'services/backup_service.dart',
   '(() async {return (await BackupService.instance.exportAll()).encode();})()'))
try:
 before=state('before')
 tap_text('^백업 데이터 불러오기');tap_text('^파일 선택하기$')
 tap_text('^'+name.replace('.','\\.')+'$')
 capture('bad_picker_'+kind+'_result')
 screen=(OUT/('bad_picker_'+kind+'_result.xml')).read_text(encoding='utf-8')
 assert '올바른 백업 파일이 아니에요' in screen, 'invalid-file feedback missing'
 after=state('after')
 assert before['tables']==after['tables'] and before['preferences']==after['preferences']
 assert compare_os('bad_picker_'+kind+'_os')
 print('PASS actual SAF selection rejected without data/reservation change:',kind)
finally:
 adb('shell','rm','--',remote)
