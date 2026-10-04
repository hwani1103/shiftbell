from usb_audit_scenarios import scenario
from usb_audit_device import adb,OUT

scenario('backup_changes_and_queue','services/backup_watcher.dart',"""
final w=BackupWatcher.instance;final d=await DatabaseService.instance.database;
final p=await SharedPreferences.getInstance();
int? memo;
try {
 check(await w.backupNow(manual:true),'manual baseline saved');
 check(await w.backupNow(),'automatic baseline saved');
 final initial=await w.lastSavedAtBySlot();
 check(await w.backupNow(),'unchanged automatic succeeds');
 check((await w.lastSavedAtBySlot()).auto==initial.auto,'unchanged automatic skips write');
 await p.setString('oct02_audit_preference','one');
 check(await w.backupNow(),'preference-only change saved');
 final settingTime=(await w.lastSavedAtBySlot()).auto;
 check(settingTime!=initial.auto,'preference-only fingerprint changed');
 memo=await DatabaseService.instance.createMemo('2035-01-02','Oct02 backup fixture');
 check(memo!=null,'isolated memo created');
 check(await w.backupNow(),'memo-only change saved');
 check((await w.lastSavedAtBySlot()).auto!=settingTime,'memo-only fingerprint changed');
 final inFlight=w.backupNow(manual:true);
 await DatabaseService.instance.updateMemo(memo!,'Oct02 backup updated during save');
 final all=await Future.wait([inFlight,w.backupNow(),w.backupNow(manual:true)]);
 check(all.every((x)=>x),'mixed queued requests complete');
 final raw=await BackupStorageService.instance.read();
 check(raw!=null && raw!.contains('Oct02 backup updated during save'),'newest readable file includes queued edit');
 final rows=(await kAlarmChannel.invokeMethod<String>('readBackupFile',{'skip':0}));
 check(rows!=null,'Native reads verified slot');
 await p.remove(BackupWatcher.kSlotFormatKey);
 await p.remove(BackupWatcher.kLastSavedAtAutoKey);
 await p.setString(BackupWatcher.kLegacyLastSavedAtKey,'2026-01-02T03:04:00');
 check((await w.lastSavedAtBySlot()).auto==DateTime(2026,1,2,3,4),'legacy timestamp fallback');
 check(await w.backupNow(),'legacy metadata migrates on first automatic save');
 check(p.getBool(BackupWatcher.kSlotFormatKey)==true && !p.containsKey(BackupWatcher.kLegacyLastSavedAtKey),'new slot marker replaces legacy key');
} finally {
 if(memo!=null)await DatabaseService.instance.deleteMemo(memo!);
 await p.remove('oct02_audit_preference');
 await w.backupNow();
 await w.backupNow(manual:true);
}
""",timeout=150)
(OUT/'backup_changes_downloads.txt').write_bytes(adb('shell','ls','-la','/sdcard/Download/ShiftBell'))
