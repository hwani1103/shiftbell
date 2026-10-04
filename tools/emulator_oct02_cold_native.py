import io,json,re,sqlite3,tarfile,time
from datetime import datetime,timezone,timedelta
from usb_audit_device import SERIAL,adb,OUT,PACKAGE
assert SERIAL=='emulator-5556'
adb('shell','cmd','alarm','set-time',str(1798729200000))
adb('shell','am','force-stop',PACKAGE)
stopped=adb('shell','dumpsys','alarm').decode()
(OUT/'startup_fixed_stopped_alarmmanager.txt').write_text(stopped,encoding='utf-8')
pattern=r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver'
assert not re.findall(pattern,stopped),'force-stop clears all wake reservations'
adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
baseline=json.loads((OUT/'mixed_lifecycle_baseline.json').read_text(encoding='utf-8'))
expected=[]
for r in baseline['alarms']:
 date=datetime.fromisoformat(r['date'])
 if date.tzinfo is None:date=date.replace(tzinfo=timezone(timedelta(hours=9)))
 expected.append(int(date.timestamp())*1000)
expected.sort()
for _ in range(30):
 dump=adb('shell','dumpsys','alarm').decode()
 actual=sorted(map(int,re.findall(pattern,dump)))
 if actual==expected:break
 time.sleep(1)
(OUT/'startup_fixed_alarmmanager.txt').write_text(dump,encoding='utf-8')
assert actual==expected,(expected,actual)
blob=adb('exec-out','run-as',PACKAGE,'tar','-C','/data/user_de/0/'+PACKAGE+'/databases','-cf','-','shiftbell.db','shiftbell.db-wal','shiftbell.db-shm')
target=OUT/'startup_fixed_db';target.mkdir(exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
 for member in archive.getmembers():
  assert member.name in ('shiftbell.db','shiftbell.db-wal','shiftbell.db-shm')
  (target/member.name).write_bytes(archive.extractfile(member).read())
db=sqlite3.connect(target/'shiftbell.db');db.row_factory=sqlite3.Row
rows={'alarms':[dict(r) for r in db.execute('select * from alarms order by id')],
      'overrides':[dict(r) for r in db.execute('select * from alarm_overrides order by id')]}
db.close();assert rows==baseline
(OUT/'startup_fixed_result.json').write_text(json.dumps({'dbRowsUnchanged':True,'beforeOs':0,'afterOs':actual,'expected':expected},indent=2),encoding='utf-8')
print('PASS force-stop OS0 -> real activity restart -> OS11; all mixed alarm and override DB rows unchanged')
