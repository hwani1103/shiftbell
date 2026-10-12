"""Additional real-device checks; invoke individually against the backed-up dev app."""
from usb_audit_scenarios import scenario
from usb_audit_device import compare_os


def basic_sleep():
    scenario('basic_sleep_device', 'providers/sleep_record_provider.dart', '''
      final n=SleepRecordNotifier(); final db=await DatabaseService.instance.database;
      final now=DateTime.now(); final start=DateTime(now.year,now.month,now.day-3);
      final before=(await db.query('sleep_records')).length;
      try {
        await n.addManual(start:start,end:start.add(const Duration(seconds:30)));
        check((await db.query('sleep_records')).length==before,'short accidental record rejected');
        await n.addManual(start:start,end:start.add(const Duration(hours:7)));
        final record=(await DatabaseService.instance.getSleepRecords()).firstWhere((r)=>r.start==start);
        check(record.status==SleepStatus.confirmed,'manual record confirmed');
        check((await n.findOverlap(start.add(const Duration(hours:1)),start.add(const Duration(hours:2))))?.id==record.id,'overlap lookup');
        await n.updateTimes(record,start:start,end:start.add(const Duration(hours:8)));
        final edited=(await DatabaseService.instance.getSleepRecords()).firstWhere((r)=>r.id==record.id);
        check(edited.end==start.add(const Duration(hours:8)),'time edit persisted');
        await n.deleteRecord(record.id!);
        check((await db.query('sleep_records')).length==before,'delete restores original count');
      } finally {n.dispose();}
    ''')


def delete_all():
    scenario('delete_all_device','providers/alarm_provider.dart','''
      final db=await DatabaseService.instance.database; final n=AlarmNotifier();
      final before=(await db.query('alarm_history')).length;
      check((await db.query('alarms',where:"type='custom'")).isNotEmpty,'custom alarms present before all-delete');
      try {
        await n.deleteAllAlarmsCompletely();
        check((await db.query('alarms')).isEmpty,'all alarm rows removed including custom');
        check((await db.query('shift_alarm_templates')).isEmpty,'templates removed');
        check((await db.query('alarm_history')).length>=before,'history retained');
        await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
        check((await db.query('alarms')).isEmpty,'Native refresh does not resurrect deleted alarms');
      } finally {n.dispose();}
    ''')
    assert compare_os('delete_all_os_match')


def invalid_backups():
    scenario('invalid_backup_matrix_device','services/restore_coordinator.dart','''
      final db=await DatabaseService.instance.database;
      final raw=await File('/data/user_de/0/com.hwani1103.shiftbell.dev/files/usb_audit_payload.json').readAsString();
      final before=jsonEncode(await db.query('alarms',orderBy:'id'));
      final changes=<String,void Function(Map<String,dynamic>)>{
        'future schema':(j)=>j['schemaVersion']=999,
        'missing alarm types':(j)=>(j['tables'] as Map).remove('alarm_types'),
        'system table':(j)=>j['tables']['sqlite_sequence']=[],
        'required field':(j)=>j['tables']['alarm_types'][0].remove('name'),
        'wrong column type':(j)=>j['tables']['alarm_types'][0]['volume']='bad',
        'fixed in backup':(j)=>j['tables']['alarms'][0]['type']='fixed',
        'snoozed in backup':(j)=>j['tables']['alarms'][0]['type']='snoozed',
        'bad preset slot':(j)=>j['tables']['alarms'][0]['preset_slot']=5,
        'missing preset link':(j)=>j['tables']['alarms'][0]['assigned_day']=null,
        'bad assigned day':(j)=>j['tables']['alarms'][0]['assigned_day']='2026-02-30',
        'bad preference type':(j)=>j['preferences']['schedule_tab_enabled']='yes',
      };
      for(final date in ['2026-02-30T07:00:00','2026-13-01T07:00:00','2026-10-01T24:00:00','2026-10-01T07:60:00','2026-10-01T07:00:60']) {
        changes['bad date $date']=(j)=>j['tables']['alarms'][0]['date']=date;
      }
      for(final entry in changes.entries) {
        final json=jsonDecode(raw) as Map<String,dynamic>;entry.value(json);
        var rejected=false;
        try {await RestoreCoordinator.instance.start(BackupPayload.fromJson(json),overwrite:true);}
        on BackupValidationException {rejected=true;}
        check(rejected,entry.key);
      }
      for(final text in ['', '{', raw.substring(0,raw.length~/2)]) {
        check(BackupPayload.tryDecode(text)==null,'empty or truncated JSON rejected');
      }
      check(before==jsonEncode(await db.query('alarms',orderBy:'id')),'all invalid backups leave alarms unchanged');
      check(!await RestoreCoordinator.instance.hasPendingJob(),'invalid backups leave no job');
    ''');
    assert compare_os('invalid_backups_os_match')


def lost_copy():
    scenario('lost_restore_copy_device','services/restore_coordinator.dart','''
      final db=await DatabaseService.instance.database;final r=RestoreCoordinator.instance;
      final payload=BackupPayload.decode(await File('/data/user_de/0/com.hwani1103.shiftbell.dev/files/usb_audit_payload.json').readAsString());
      for(final mode in ['missing','tampered','corruptJob']) {
        await db.execute("CREATE TRIGGER usb_audit_fail BEFORE INSERT ON shift_schedule BEGIN SELECT RAISE(ABORT,'usb audit'); END");
        try {await r.start(payload,overwrite:true);} on RestoreIncompleteException {} finally {await db.execute('DROP TRIGGER IF EXISTS usb_audit_fail');}
        final job=(await r.loadPendingJob())!;
        final before=jsonEncode(await db.query('alarms',orderBy:'id'));
        if(mode=='missing') {await File(job.copyPath).delete();}
        else if(mode=='tampered') {await File(job.copyPath).writeAsString('{}');}
        else {await (await r._jobFile()).writeAsString('{');}
        var lost=false;try {await r.resume();} on RestoreCopyLostException {lost=true;}
        check(lost,'$mode reported as lost copy');
        check(!await r.hasPendingJob(),'$mode safely clears job');
        check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'$mode releases lock');
        check(before==jsonEncode(await db.query('alarms',orderBy:'id')),'$mode preserves current rows');
      }
    ''',timeout=120)
    assert compare_os('lost_copy_os_match')


def pending_backup():
    scenario('pending_backup_block_device','services/restore_coordinator.dart','''
      final db=await DatabaseService.instance.database;
      final p=BackupPayload.decode(await File('/data/user_de/0/com.hwani1103.shiftbell.dev/files/usb_audit_payload.json').readAsString());
      await db.execute("CREATE TRIGGER usb_audit_fail BEFORE INSERT ON shift_schedule BEGIN SELECT RAISE(ABORT,'usb audit'); END");
      try {await RestoreCoordinator.instance.start(p,overwrite:true);} on RestoreIncompleteException {} finally {await db.execute('DROP TRIGGER IF EXISTS usb_audit_fail');}
      check(await RestoreCoordinator.instance.hasPendingJob(),'pending job prepared');
    ''')
    scenario('pending_backup_watcher_device','services/backup_watcher.dart','''
      final before=await BackupWatcher.instance.lastSavedAtBySlot();
      check(!await BackupWatcher.instance.backupNow(manual:true),'manual blocked during pending restore');
      await BackupWatcher.instance.backupNow();
      final after=await BackupWatcher.instance.lastSavedAtBySlot();
      check(before.manual==after.manual && before.auto==after.auto,'neither backup slot overwritten');
      await RestoreCoordinator.instance.safeEnd();
      check(!await RestoreCoordinator.instance.hasPendingJob(),'keep current data clears pending job');
    ''')
    assert compare_os('pending_backup_os_match')


def live_restore():
    from usb_audit_device import evaluate
    import re
    result=scenario('live_restore_start','providers/alarm_provider.dart','''
      final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
      try {await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',date:at,type:'custom',alarmTypeId:3));} finally {n.dispose();}
      final db=await DatabaseService.instance.database;
      final id=(await db.query('alarms',where:'date=?',whereArgs:[at.toIso8601String()])).single['id'] as int;
      var ringing=false;
      for(var i=0;i<40;i++) {ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':id})??false;if(ringing)break;await Future<void>.delayed(const Duration(milliseconds:500));}
      check(ringing,'silent alarm actually delivered');return 'PASS: liveId=$id';
    ''')
    alarm_id=int(re.search(r'liveId=(\d+)',result)[1])
    scenario('live_and_snoozed_restore_device','services/restore_coordinator.dart',f'''
      final id={alarm_id}; final db=await DatabaseService.instance.database;
      final raw=await File('/data/user_de/0/com.hwani1103.shiftbell.dev/files/usb_audit_payload.json').readAsString();
      final p=BackupPayload.decode(raw);p.tables['alarms']!.first['id']=id;
      final prefs=await SharedPreferences.getInstance();
      final generation=prefs.getInt('friend_share_generation');
      final permission=prefs.getBool('permissions_requested');
      p.preferences['friend_share_generation']=99999;p.preferences['permissions_requested']=!(permission??false);
      await prefs.setString('usb_audit_extra','must disappear');
      await RestoreCoordinator.instance.start(p,overwrite:true);
      check(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':id}})??false,'live ring survives DB and OS restore');
      check((await db.query('alarms',where:'id=?',whereArgs:[id])).single['alarm_type_id']==3,'live row keeps silent type and ID');
      check(prefs.getInt('friend_share_generation')==generation && prefs.getBool('permissions_requested')==permission,'foreign ownership and permission keys ignored');
      check(!prefs.containsKey('usb_audit_extra'),'absent normal preference removed');
    ''',timeout=120)
    from usb_audit_device import capture, adb
    # snoozeOverlay is a UI-close notification after DB work, not a snooze
    # command. Exercise the actual native overlay button seen in the capture.
    capture('live_restore_overlay')
    adb('shell','input','tap','720','382')
    scenario('snoozed_restore_collision_device','services/restore_coordinator.dart',f'''
      final id={alarm_id}; final db=await DatabaseService.instance.database;
      final p=BackupPayload.decode(await File('/data/user_de/0/com.hwani1103.shiftbell.dev/files/usb_audit_payload.json').readAsString());
      p.tables['alarms']!.first['id']=id;
      for(var i=0;i<30;i++) {{if((await db.query('alarms',where:'id=?',whereArgs:[id])).single['type']=='snoozed')break;await Future<void>.delayed(const Duration(milliseconds:100));}}
      final snoozed=(await db.query('alarms',where:'id=?',whereArgs:[id])).single;
      check(snoozed['type']=='snoozed','live restored ring can snooze');
      final before=DateTime.parse(snoozed['date'] as String).millisecondsSinceEpoch;
      await RestoreCoordinator.instance.start(p,overwrite:true);
      final carried=(await db.query('alarms',where:'id=?',whereArgs:[id])).single;
      check(carried['type']=='snoozed' && DateTime.parse(carried['date'] as String).millisecondsSinceEpoch==before,'snooze absolute instant and ID survive restore');
      final customs=await db.query('alarms',where:"type='custom'");
      check(customs.length==p.tables['alarms']!.length && customs.every((r)=>r['id']!=id),'colliding backup custom receives separate ID');
      check(!await RestoreCoordinator.instance.hasPendingJob(),'live and snooze restores complete');
    ''',timeout=120)
    assert compare_os('live_snooze_restore_os_match')


if __name__ == '__main__':
    import sys
    {'basic_sleep':basic_sleep,'delete_all':delete_all,
     'invalid_backups':invalid_backups,'lost_copy':lost_copy,'pending_backup':pending_backup}[sys.argv[1]]()
