import io,json,re,sqlite3,tarfile
from datetime import datetime,timezone,timedelta
from usb_audit_device import SERIAL,adb,OUT,PACKAGE
assert SERIAL=='emulator-5556'
blob=adb('exec-out','run-as',PACKAGE,'tar','-C','/data/user_de/0/'+PACKAGE+'/databases','-cf','-','shiftbell.db','shiftbell.db-wal','shiftbell.db-shm')
target=OUT/'reinstall_restored_db';target.mkdir(exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
 for member in archive.getmembers():
  assert member.name in ('shiftbell.db','shiftbell.db-wal','shiftbell.db-shm')
  (target/member.name).write_bytes(archive.extractfile(member).read())
db=sqlite3.connect(target/'shiftbell.db');db.row_factory=sqlite3.Row
source=json.loads((OUT/'reinstall_original_backup.json').read_bytes())
for table in ['shift_schedule','shift_alarm_templates','alarm_overrides','date_memos','date_schedules','sleep_records','friends']:
 rows=[dict(r) for r in db.execute('select * from '+table+' order by rowid')]
 assert rows==source['tables'][table],table
rows=[dict(r) for r in db.execute('select * from alarms order by id')];db.close()
now=int(adb('shell','date','+%s').strip())*1000
expected=[]
for r in rows:
 date=datetime.fromisoformat(r['date'])
 if date.tzinfo is None:date=date.replace(tzinfo=timezone(timedelta(hours=9)))
 epoch=int(date.timestamp())*1000
 if epoch>now:expected.append(epoch)
dump=adb('shell','dumpsys','alarm').decode()
(OUT/'reinstall_restored_alarmmanager.txt').write_text(dump,encoding='utf-8')
pattern=r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver'
actual=sorted(map(int,re.findall(pattern,dump)))
assert sorted(expected)==actual,(expected,actual)
assert not adb('shell','run-as',PACKAGE,'find','/data/user_de/0/'+PACKAGE+'/databases/restore_work','-name','job.json').strip(),'restore job must finish'
(OUT/'reinstall_restore_result.json').write_text(json.dumps({'tablesMatch':True,'alarms':rows,'expected':sorted(expected),'actual':actual,'jobComplete':True},indent=2),encoding='utf-8')
print('PASS reinstall -> actual onboarding SAF file pick -> restore; schedule/templates/overrides/memos/sleep/friends match source, DB/OS',len(actual),'job complete')
