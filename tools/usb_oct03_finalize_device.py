import json,tarfile,sqlite3,time,pathlib,xml.etree.ElementTree as ET
from usb_audit_device import evaluate,adb,OUT,PACKAGE,compare_os
import usb_oct03_restore_baseline

result=evaluate('final_backup_slots','services/backup_watcher.dart',"""(() async {
 final prefs=await SharedPreferences.getInstance();await prefs.remove(BackupWatcher._kLastContentHashKey);
 final auto=await BackupWatcher.instance.backupNow();final manual=await BackupWatcher.instance.backupNow(manual:true);
 if(!auto || !manual)throw StateError('Backup slots not saved');
 final live=(await BackupService.instance.exportAll()).toJson();
 for(var i=0;i<2;i++){
  final content=await kAlarmChannel.invokeMethod<String>('readBackupFile',{'skip':i});
  if(content==null)throw StateError('Missing backup slot $i');
  final value=jsonDecode(content) as Map;
  if(jsonEncode(value['tables'])!=jsonEncode(live['tables']) || jsonEncode(value['preferences'])!=jsonEncode(live['preferences']))throw StateError('Backup differs from restored user data');
 }
 return 'auto and manual slots saved and both read back equal restored user tables/preferences';})()""".replace('\n',' '),timeout=120)
assert compare_os('final_before_restart_os')
adb('shell','am','force-stop',PACKAGE)
adb('shell','am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
time.sleep(5)
archive=OUT/'remaining_final_de.tar'
archive.write_bytes(adb('exec-out','run-as',PACKAGE,'tar','-C','/data/user_de/0/'+PACKAGE,'-cf','-','databases','shared_prefs'))
dbdir=OUT/'final_database_readback';dbdir.mkdir(exist_ok=True)
with tarfile.open(archive) as tar:
    for name in ['databases/shiftbell.db','databases/shiftbell.db-wal','databases/shiftbell.db-shm']:
        try: member=tar.extractfile(name)
        except KeyError:continue
        if member:(dbdir/pathlib.PurePosixPath(name).name).write_bytes(member.read())
source=json.loads(json.loads((OUT/'export_remaining_all_tables.vm.json').read_text(encoding='utf-8'))['valueAsString'])
db=sqlite3.connect(str(dbdir/'shiftbell.db'));db.row_factory=sqlite3.Row
differences=[]
for name,expected in source.items():
    if name=='android_metadata':continue
    actual=[dict(r) for r in db.execute('SELECT * FROM "'+name.replace('"','""')+'" ORDER BY rowid')]
    if actual!=expected:differences.append(name)
integrity=db.execute('PRAGMA integrity_check').fetchone()[0];db.close()
assert not differences,differences
assert integrity=='ok'
dump=adb('shell','dumpsys','alarm').decode('utf-8',errors='replace');(OUT/'final_alarmmanager.txt').write_text(dump,encoding='utf-8')
import re
actual=sorted(map(int,re.findall(r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver',dump)))
assert actual==[1790970600000],actual
power=adb('shell','dumpsys','power').decode(errors='replace');battery=adb('shell','dumpsys','battery').decode(errors='replace')
stay=adb('shell','settings','get','global','stay_on_while_plugged_in').decode().strip()
zone=adb('shell','getprop','persist.sys.timezone').decode().strip();auto=adb('shell','settings','get','global','auto_time_zone').decode().strip()
assert stay=='7' and zone=='Asia/Seoul' and auto=='1'
assert 'mWakefulness=Awake' in power and 'mStayOn=true' in power
assert 'USB powered: true' in battery
values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as',PACKAGE,'cat','/data/user_de/0/'+PACKAGE+'/shared_prefs/alarm_state.xml'))}
assert int(values.get('currently_ringing_alarm_id','-1'))<0
result={'original_user_tables_equal':True,'integrity':integrity,'original_alarm_id':2,'original_alarm_epoch':1790970600000,'os_epochs':actual,'timezone':zone,'auto_timezone':auto,'stay_awake':stay,'awake':True,'usb_charging':True,'battery_level':int(re.search(r'level: (\d+)',battery)[1]),'phone_power_off':False,'backup_slots_verified':True}
(OUT/'final_device_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
