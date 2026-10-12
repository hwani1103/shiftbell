"""Isolated dev-device KO backup -> EN restore -> KO verification probe.

Run stages separately because Android locale changes can restart Flutter. Keeps
the snapshot in private build evidence and only creates a temporary custom alarm.
"""
import json
import sys

from usb_audit_device import OUT, adb, compare_os, connect_vm, evaluate


def data(name):
    return json.loads((OUT / (name + '.vm.json')).read_text(encoding='utf-8'))['valueAsString']


def state(name):
    evaluate(name, 'services/restore_coordinator.dart', '''(() async {
      final d=await DatabaseService.instance.database;
      final p=await SharedPreferences.getInstance();
      return jsonEncode({
        'alarms':await d.query('alarms',orderBy:'id'),
        'dateSchedules':await d.query('date_schedules',orderBy:'id'),
        'sleepRecords':await d.query('sleep_records',orderBy:'id'),
        'scheduleTabEnabled':p.getBool('schedule_tab_enabled'),
        'oneTapPresets':p.getString('custom_alarm_presets'),
      });
    })()'''.replace('\n', ' '))
    compare_os(name + '_os')


def export(name):
    evaluate(name, 'services/backup_service.dart',
             '(() async => (await BackupService.instance.exportAll()).encode())()')
    payload = data(name)
    dest = OUT / 'private' / (name + '.json')
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(payload, encoding='utf-8')
    print(name, 'saved privately', len(payload), 'characters')


def restore_from(name, result):
    path = OUT / 'private' / (name + '.json')
    target = '/data/user_de/0/com.hwani1103.shiftbell.dev/files/r7_locale_restore_snapshot.json'
    import subprocess
    from usb_audit_device import ADB, PACKAGE, SERIAL
    subprocess.run([ADB, '-s', SERIAL, 'shell', '-T', 'run-as', PACKAGE,
                    'tee', target], input=path.read_bytes(),
                   stdout=subprocess.DEVNULL, check=True)
    expression = '''(() async {
      final payload=BackupPayload.decode(await File(''' + repr(target) + ''').readAsString());
      await RestoreCoordinator.instance.start(payload,overwrite:true);
      return jsonEncode({'pending':await RestoreCoordinator.instance.hasPendingJob(),
        'lock':await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')});
    })()'''
    evaluate(result, 'services/restore_coordinator.dart', expression.replace('\n', ' '), timeout=180)


if __name__ == '__main__':
    connect_vm()
    stage = sys.argv[1]
    if stage == 'before_en':
        state('export_r7_before_en_restore')
        export('export_r7_ko_backup_snapshot')
    elif stage == 'restore_en':
        restore_from('export_r7_ko_backup_snapshot', 'export_r7_restore_in_en')
        state('export_r7_after_en_restore')
    elif stage == 'after_ko':
        state('export_r7_after_ko_return')
    elif stage == 'verify':
        names = ['export_r7_before_en_restore', 'export_r7_after_en_restore',
                 'export_r7_after_ko_return']
        values = [json.loads(data(name)) for name in names]
        assert values[0] == values[1] == values[2], 'KO/EN restored data differs'
        outcome = json.loads(data('export_r7_restore_in_en'))
        assert outcome == {'pending': False, 'lock': False}, outcome
        assert all(json.loads((OUT / (name + '_os.json')).read_text())['match']
                   for name in names)
        print('PASS: KO/EN/KO data stable; schedule rows', len(values[0]['dateSchedules']),
              'alarm rows', len(values[0]['alarms']),
              'restore job/lock cleared; OS matches DB')
    elif stage == 'active_ko':
        evaluate('r7_active_assign', 'services/custom_alarm_service.dart',
                 "(() async {final n=DateTime.now(); final d=DateTime(n.year,n.month,n.day+1); final o=await CustomAlarmService.instance.assign(d,const CustomAlarmPreset(time:'23:11',alarmTypeId:3),1); return 'result=${o.result},id=${o.alarmId}';})()")
        state('export_r7_active_before_en')
        export('export_r7_active_ko_backup_snapshot')
    elif stage == 'active_restore_en':
        restore_from('export_r7_active_ko_backup_snapshot', 'export_r7_active_restore_in_en')
        state('export_r7_active_after_en')
    elif stage == 'active_after_ko':
        state('export_r7_active_after_ko')
    elif stage == 'active_verify':
        names = ['export_r7_active_before_en', 'export_r7_active_after_en',
                 'export_r7_active_after_ko']
        values = [json.loads(data(name)) for name in names]
        assert all(len(v['alarms']) == 1 for v in values), 'custom alarm missing'
        assert all(v['dateSchedules'] == values[0]['dateSchedules'] and
                   v['oneTapPresets'] == values[0]['oneTapPresets'] for v in values)
        assert all(v['alarms'][0]['date'] == values[0]['alarms'][0]['date'] and
                   v['alarms'][0]['time'] == values[0]['alarms'][0]['time'] and
                   v['alarms'][0]['type'] == 'custom' for v in values)
        assert json.loads(data('export_r7_active_restore_in_en')) == {
            'pending': False, 'lock': False}
        assert all(json.loads((OUT / (name + '_os.json')).read_text())['match']
                   for name in names)
        print('PASS: active custom alarm 1/1, schedule/preset stable, restore clear')
    elif stage == 'active_cleanup':
        evaluate('r7_active_cleanup', 'providers/alarm_provider.dart',
                 '''(() async {final d=await DatabaseService.instance.database;
                   final rows=await d.query('alarms',where:"type='custom'");
                   if(rows.length!=1) throw StateError('expected one test custom');
                   final n=AlarmNotifier();
                   try {await n.deleteAlarm(rows.single['id'] as int,DateTime.parse(rows.single['date'] as String));}
                   finally {n.dispose();}
                   return 'remaining=${(await d.query('alarms')).length}';
                 })()'''.replace('\n', ' '))
        state('export_r7_active_cleanup_state')
    elif stage == 'sleep_ko':
        evaluate('r7_sleep_assign', 'providers/sleep_record_provider.dart',
                 '''(() async {final n=SleepRecordNotifier();
                   try {final s=DateTime(2020,1,2,3,21);
                     final before=await DatabaseService.instance.getSleepRecords();
                     if(before.isNotEmpty) throw StateError('original sleep records exist');
                     await n.addManual(start:s,end:s.add(const Duration(hours:7)));
                     final after=await DatabaseService.instance.getSleepRecords();
                     return 'sleepCount=${after.length}';
                   } finally {n.dispose();}
                 })()'''.replace('\n', ' '))
        state('export_r7_sleep_before_en')
        export('export_r7_sleep_ko_backup_snapshot')
    elif stage == 'sleep_restore_en':
        restore_from('export_r7_sleep_ko_backup_snapshot', 'export_r7_sleep_restore_in_en')
        state('export_r7_sleep_after_en')
    elif stage == 'sleep_after_ko':
        state('export_r7_sleep_after_ko')
    elif stage == 'sleep_verify':
        names = ['export_r7_sleep_before_en', 'export_r7_sleep_after_en',
                 'export_r7_sleep_after_ko']
        values = [json.loads(data(name)) for name in names]
        assert all(len(v['sleepRecords']) == 1 for v in values)
        assert values[0] == values[1] == values[2], 'sleep/KO data differs'
        assert json.loads(data('export_r7_sleep_restore_in_en')) == {
            'pending': False, 'lock': False}
        assert all(json.loads((OUT / (name + '_os.json')).read_text())['match']
                   for name in names)
        print('PASS: KO sleep record preserved through EN restore and KO return')
    elif stage == 'sleep_cleanup':
        evaluate('r7_sleep_cleanup', 'services/database_service.dart',
                 '''(() async {final rows=await DatabaseService.instance.getSleepRecords();
                   if(rows.length!=1) throw StateError('expected one test sleep');
                   await DatabaseService.instance.deleteSleepRecord(rows.single.id!);
                   return 'remaining=${(await DatabaseService.instance.getSleepRecords()).length}';
                 })()'''.replace('\n', ' '))
        state('export_r7_sleep_cleanup_state')
    elif stage == 'final':
        state('export_r7_final_en_state')
        final = json.loads(data('export_r7_final_en_state'))
        baseline = json.loads(data('export_r7_before_en_restore'))
        assert all(final[key] == baseline[key] for key in baseline), \
            'final state differs from starting user state'
        assert final['sleepRecords'] == [], 'temporary sleep record remains'
        assert json.loads((OUT / 'export_r7_final_en_state_os.json').read_text())['match']
        print('PASS: final dev data same as before, alarms 0/0, sleep',
              len(final['sleepRecords']))
    else:
        raise SystemExit('before_en|restore_en|after_ko|verify|active_ko|active_restore_en|active_after_ko|active_verify|active_cleanup|sleep_ko|sleep_restore_en|sleep_after_ko|sleep_verify|sleep_cleanup|final')
