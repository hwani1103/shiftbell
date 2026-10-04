"""Fresh private baseline before the resumed USB audit; never exports to the repo."""
import json
import sys
from usb_audit_device import adb, OUT, PACKAGE, connect_vm, evaluate, compare_os

assert PACKAGE.endswith('.dev')
for area, root in [('de', '/data/user_de/0/'), ('ce', '/data/user/0/')]:
    path = OUT / f'remaining_before_{area}.tar'
    if '--resume-after-attach' in sys.argv:
        assert path.exists() and path.stat().st_size > 0, 'Original archive must already exist'
    else:
        assert not path.exists(), f'Refusing to overwrite baseline: {path}'
        path.write_bytes(adb('exec-out', 'run-as', PACKAGE, 'tar', '-C', root + PACKAGE,
                             '-cf', '-', 'databases', 'shared_prefs'))
connect_vm()
evaluate('export_remaining_original', 'services/backup_service.dart',
         '(() async {return (await BackupService.instance.exportAll()).encode();})()')
evaluate('export_remaining_original_prefs', 'screens/settings_tab.dart',
         '(() async {final p=await SharedPreferences.getInstance();return jsonEncode({for(final k in p.getKeys()) k:p.get(k)});})()')
evaluate('export_remaining_all_tables', 'services/database_service.dart', """(() async {
 final d=await DatabaseService.instance.database;
 final names=await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
 final result=<String,dynamic>{};
 for(final row in names){final n=row['name'] as String;result[n]=await d.query(n,orderBy:'rowid');}
 return jsonEncode(result);})()""".replace('\n', ' '))
assert compare_os('remaining_baseline_os')
print('Fresh dev baseline saved; DB and OS matched.')
