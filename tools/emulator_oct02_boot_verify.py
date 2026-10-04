import io,json,sqlite3,tarfile
from usb_audit_device import SERIAL,adb,OUT,PACKAGE
assert SERIAL=='emulator-5556'
assert adb('shell','getprop','sys.boot_completed').strip()==b'1'
root='/data/user_de/0/'+PACKAGE+'/databases'
blob=adb('exec-out','run-as',PACKAGE,'tar','-C',root,'-cf','-','shiftbell.db','shiftbell.db-wal','shiftbell.db-shm')
(OUT/'dst_boot_db.tar').write_bytes(blob)
target=OUT/'dst_boot_db';target.mkdir(exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
 for member in archive.getmembers():
  assert member.name in ('shiftbell.db','shiftbell.db-wal','shiftbell.db-shm')
  (target/member.name).write_bytes(archive.extractfile(member).read())
db=sqlite3.connect(target/'shiftbell.db');db.row_factory=sqlite3.Row
rows=[dict(r) for r in db.execute('select * from alarms')];db.close()
assert len(rows)==1 and rows[0]['id']==54 and rows[0]['type']=='snoozed'
from datetime import datetime
assert int(datetime.fromisoformat(rows[0]['date']).timestamp()*1000)==1793509440000
dump=adb('shell','dumpsys','alarm').decode()
(OUT/'dst_boot_alarmmanager.txt').write_text(dump,encoding='utf-8')
assert 'origWhen 1793509440000' in dump
(OUT/'dst_boot_result.json').write_text(json.dumps({'rows':rows,'expectedEpoch':1793509440000,'bootCompleted':True,'osReservationPresent':True},indent=2),encoding='utf-8')
print('PASS emulator real reboot retains first-fold snooze ID54 / epoch1793509440000 in DB and OS')
