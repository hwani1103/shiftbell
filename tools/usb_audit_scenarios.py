"""Real-device service checks. UI and hardware-only assertions stay separate."""
from usb_audit_device import evaluate, adb, OUT


def scenario(name, library, body, timeout=90):
    expression = '''(() async {
      final passed=<String>[];
      void check(bool value,String name) {
        if(!value) throw StateError('FAIL: $name; preceding=$passed');
        passed.add(name);
      }
      try {
    ''' + body + '''
        return 'PASS: $passed';
      } catch(e,st) { return 'FAIL: $e; $st'; }
    })()'''
    result = evaluate(name, library, expression.replace('\n', ' '), timeout=timeout)
    if not result.startswith('PASS:'):
        raise RuntimeError(result)
    return result


def one_tap():
    scenario('one_tap_device', 'services/custom_alarm_service.dart', '''
      final now=DateTime.now();
      final tomorrow=DateTime(now.year,now.month,now.day+1);
      final db=await DatabaseService.instance.database;
      check((await db.query('alarms')).isEmpty,'fixture has no original alarms');
      for(var i=0;i<5;i++) {
        final result=await CustomAlarmService.instance.assign(tomorrow,
          CustomAlarmPreset(time:'07:0$i',alarmTypeId:1+i%3),i);
        check(result.result==CustomAlarmAssignResult.scheduled,'slot $i DB and Native scheduling');
      }
      check((await db.query('alarms')).length==5,'five distinct slots');
      final duplicate=await CustomAlarmService.instance.assign(tomorrow,
        const CustomAlarmPreset(time:'07:00'),0);
      check(duplicate.result==CustomAlarmAssignResult.alreadyAssigned,'same slot rejected');
      final past=await CustomAlarmService.instance.assign(now,
        const CustomAlarmPreset(time:'00:00'),0);
      check(past.result==CustomAlarmAssignResult.past,'past today rejected');
      final distant=await CustomAlarmService.instance.assign(
        DateTime(now.year,now.month,now.day+2),const CustomAlarmPreset(time:'07:00'),0);
      check(distant.result==CustomAlarmAssignResult.outsideWindow,'day after tomorrow rejected');
      check((await db.query('alarms')).length==5,'rejected requests have no rows');
      check((await CustomAlarmService.instance.futureAssignments(0)).length==1,'assignment lookup');
    ''')
    (OUT/'one_tap_alarmmanager.txt').write_bytes(adb('shell','dumpsys','alarm'))


def fixed_collision():
    scenario('fixed_collision_device','providers/alarm_provider.dart','''
      final db=await DatabaseService.instance.database;
      final schedule=(await DatabaseService.instance.getShiftSchedule())!;
      final now=DateTime.now(); final tomorrow=DateTime(now.year,now.month,now.day+1);
      final shift=schedule.getShiftForDate(tomorrow);
      await db.insert('shift_alarm_templates',{'shift_type':shift,'time':'07:00','alarm_type_id':1,'day_offset':0});
      await db.insert('shift_alarm_templates',{'shift_type':shift,'time':'07:10','alarm_type_id':2,'day_offset':0});
      final n=AlarmNotifier();
      try {
        final result=await n.regenerateAlarmsAroundDate(tomorrow,schedule);
        check(result.failed==0,'fixed OS registration succeeds');
        final same=await db.query('alarms',where:'date LIKE ? AND time = ?',whereArgs:['${tomorrow.toIso8601String().substring(0,10)}%','07:00']);
        check(same.length==1 && same.single['type']=='custom','custom wins fixed collision');
        final id=same.single['id'] as int;
        final deletion=await n.deleteAlarm(id,tomorrow.add(const Duration(hours:7)));
        check(deletion.fixedReplacement && !deletion.reservationFailed,'custom deletion schedules replacement');
        final replaced=await db.query('alarms',where:'date LIKE ? AND time = ?',whereArgs:['${tomorrow.toIso8601String().substring(0,10)}%','07:00']);
        check(replaced.length==1 && replaced.single['type']=='fixed','one fixed replacement in DB');
        final fixedId=replaced.single['id'] as int;
        await n.updateAlarmType(fixedId,3);
        await n.regenerateAlarmsAroundDate(tomorrow,schedule);
        final changed=await db.query('alarms',where:'id=?',whereArgs:[fixedId]);
        check(changed.length==1 && changed.single['alarm_type_id']==3,'type exception survives refresh with same ID');
        await n.deleteAlarm(fixedId,tomorrow.add(const Duration(hours:7)));
        await n.regenerateAlarmsAroundDate(tomorrow,schedule);
        check((await db.query('alarms',where:'id=?',whereArgs:[fixedId])).isEmpty,'fixed deletion survives refresh');
        check((await db.query('alarm_overrides')).isNotEmpty,'fixed override persisted');
      } finally { n.dispose(); }
    ''')
    (OUT/'fixed_alarmmanager.txt').write_bytes(adb('shell','dumpsys','alarm'))


def native_refresh():
    scenario('native_refresh_device','services/database_service.dart','''
      final db=await DatabaseService.instance.database;
      final customBefore=await db.query('alarms',where:"type='custom'",orderBy:'id');
      final overrides=await db.query('alarm_overrides',orderBy:'rowid');
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      final first=await db.query('alarms',orderBy:'id');
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      final second=await db.query('alarms',orderBy:'id');
      check(jsonEncode(first)==jsonEncode(second),'Native repeated refresh is idempotent');
      check(jsonEncode(customBefore)==jsonEncode(await db.query('alarms',where:"type='custom'",orderBy:'id')),'Native preserves custom rows');
      check(jsonEncode(overrides)==jsonEncode(await db.query('alarm_overrides',orderBy:'rowid')),'Native preserves current overrides');
      check((await db.rawQuery('SELECT date,count(*) n FROM alarms GROUP BY date HAVING n>1')).isEmpty,'no duplicate wall slots');
      check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked') ?? true),'no leaked restore lock');
    ''')
    (OUT/'native_refresh_alarmmanager.txt').write_bytes(adb('shell','dumpsys','alarm'))


def backup_restore():
    import subprocess
    from usb_audit_device import ADB,SERIAL,PACKAGE
    payload=OUT/'restore_payload.json'
    target='/data/user_de/0/'+PACKAGE+'/files/usb_audit_payload.json'
    subprocess.run([ADB,'-s',SERIAL,'shell','-T','run-as',PACKAGE,'tee',target],
                   input=payload.read_bytes(),stdout=subprocess.DEVNULL,check=True)
    scenario('backup_restore_device','services/restore_coordinator.dart',f'''
      final db=await DatabaseService.instance.database;
      final p=BackupPayload.decode(await File('{target}').readAsString());
      check(p.tables['alarms']!.every((r)=>r['type']=='custom'),'export excludes derived fixed and snoozed');
      check(!p.preferences.keys.any(FriendSyncService.backupExcludedPreferenceKeys.contains),'export excludes sharing ownership');
      final before=jsonEncode(await db.query('alarms',orderBy:'id'));
      for(final invalid in ['2026-02-30T07:00:00','2026-13-01T07:00:00','2026-10-01T24:00:00','2026-10-01T07:60:00']) {{
        final copy=BackupPayload.decode(p.encode()); copy.tables['alarms']!.first['date']=invalid;
        var rejected=false;
        try {{await RestoreCoordinator.instance.start(copy,overwrite:true);}} on BackupValidationException {{rejected=true;}}
        check(rejected,'invalid $invalid rejected before native changes');
      }}
      check(before==jsonEncode(await db.query('alarms',orderBy:'id')),'rejected restore keeps all alarm rows');
      check(!await RestoreCoordinator.instance.hasPendingJob(),'rejected restore leaves no pending job');
      await RestoreCoordinator.instance.start(p,overwrite:true);
      check((await db.query('alarms',where:"type='custom'")).length==p.tables['alarms']!.length,'custom alarms restored');
      check(!await RestoreCoordinator.instance.hasPendingJob(),'completed restore removes job');
      check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'Native lock released');
      final historyCount=(await db.query('alarm_history')).length;
      await RestoreCoordinator.instance.start(p,overwrite:true);
      check((await db.query('alarm_history')).length==historyCount,'repeat restore does not duplicate history');
      check(!await RestoreCoordinator.instance.hasPendingJob(),'repeat restore completes');
      check((await db.rawQuery('SELECT date,count(*) n FROM alarms GROUP BY date HAVING n>1')).isEmpty,'restored OS inputs have no duplicate slots');
    ''',timeout=120)
    (OUT/'restore_alarmmanager.txt').write_bytes(adb('shell','dumpsys','alarm'))


def backup_slots():
    scenario('backup_slots_device','services/backup_watcher.dart','''
      check(await BackupWatcher.instance.backupNow(manual:true),'manual MediaStore write');
      check(await BackupWatcher.instance.backupNow(),'automatic MediaStore write');
      final times=await BackupWatcher.instance.lastSavedAtBySlot();
      check(times.manual!=null && times.auto!=null,'both slot times persisted');
      check(await BackupWatcher.instance.backupNow(),'identical automatic request succeeds');
      final unchanged=await BackupWatcher.instance.lastSavedAtBySlot();
      check(times.auto==unchanged.auto,'identical data skips rewriting');
      final prefs=await SharedPreferences.getInstance();
      await prefs.setString('usb_audit_setting','changed');
      check(await BackupWatcher.instance.backupNow(),'preference change triggers auto backup');
      final changed=await BackupWatcher.instance.lastSavedAtBySlot();
      check(changed.auto!=times.auto,'preference-only change updates successful time');
      final outcomes=await Future.wait([BackupWatcher.instance.backupNow(manual:true),BackupWatcher.instance.backupNow(),BackupWatcher.instance.backupNow(manual:true)]);
      check(outcomes.every((x)=>x),'concurrent manual and automatic requests complete');
      await prefs.remove('usb_audit_setting');
    ''')
    (OUT/'downloads_after_slots.txt').write_bytes(adb('shell','ls','-la','/sdcard/Download/ShiftBell'))


def friend_server():
    scenario('friend_server_device','services/friend_sync_service.dart','''
      final s=FriendSyncService.instance; final fs=FirebaseFirestore.instance;
      final uid=await s.getOrCreateOwnerId(); check(uid!=null,'anonymous authentication ready');
      final doc=fs.collection('friend_schedules').doc(uid);
      check(!(await doc.get(const GetOptions(source:Source.server))).exists,'isolated owner has no original document');
      final now=DateTime.now();
      final schedule=ShiftSchedule(isRegular:true,shiftTypes:['Day Shift','Night duty','Day Off'],
        pattern:['Day Shift','Night duty','Day Off'],todayIndex:0,startDate:DateTime(now.year,now.month,now.day),
        shiftColors:{'Day Shift':4281558681,'Night duty':4281558682,'Day Off':4281558683},
        assignedDates:{},shiftDurations:{'Day Shift':480});
      try {
        check(await s.startSharing(schedule:schedule,ownerName:'USB audit temporary')!=null,'start sharing returns code');
        final active=await s.getShareState();
        check(active.isActive && !active.dirty,'server ACK confirms active');
        final first=(await doc.get(const GetOptions(source:Source.server))).data()!;
        check(!first.containsKey('shiftDurations') && !first.containsKey('alarms') && !first.containsKey('memos'),'private fields excluded');
        check((await s.fetchByOwnerIdDetailed(uid!)).status==FriendFetchStatus.found,'server fetch decoder succeeds');
        await s.syncIfEnabled(schedule);
        final same=(await doc.get(const GetOptions(source:Source.server))).data()!;
        check(first['updatedAt']==same['updatedAt'],'same payload avoids redundant server write');
        schedule.assignedDates={'${now.toIso8601String().substring(0,10)}':'Day Off'};
        await s.syncIfEnabled(schedule);
        final changed=(await doc.get(const GetOptions(source:Source.server))).data()!;
        check((changed['assignedDates'] as Map).values.single=='Day Off','assignment changes reach server');
        check(await s.updateMyName(newName:'USB audit renamed',schedule:schedule),'rename ACK');
        check((await s.fetchByOwnerIdDetailed(uid)).data!.ownerName=='USB audit renamed','receiver sees new name');
        await fs.disableNetwork();
        await s.updateMyName(newName:'USB audit offline',schedule:schedule);
        check((await s.getShareState()).dirty,'offline upload remains dirty');
        check((await s.fetchByOwnerIdDetailed(uid)).status==FriendFetchStatus.unavailable,'offline does not become notFound');
        await s.stopSharing();
        check((await s.getShareState()).intent==FriendShareIntent.stopPending,'offline stop remains pending');
        await fs.enableNetwork(); await fs.waitForPendingWrites();
        await s.retryPending(schedule);
        check((await s.getShareState()).intent==FriendShareIntent.off,'online retry confirms off');
        check(!(await doc.get(const GetOptions(source:Source.server))).exists,'late upload cannot survive subsequent stop');
        check((await s.fetchByOwnerIdDetailed(uid)).status==FriendFetchStatus.notFound,'server notFound distinguished');
        await s.startSharing(schedule:schedule,ownerName:'USB audit restart');
        check((await s.getShareState()).generation>active.generation,'restart advances generation');
        await s.onRestoreCompleted(schedule);
        check(!(await s.getShareState()).dirty,'restore callback resubmits and confirms');
        await s.syncIfEnabled(null);
        check((await doc.get(const GetOptions(source:Source.server))).exists,'OBS null schedule leaves previous shared document');
      } finally {
        await fs.enableNetwork(); await s.stopSharing(); await fs.waitForPendingWrites();
      }
      check(!(await doc.get(const GetOptions(source:Source.server))).exists,'temporary remote document cleaned');
    ''',timeout=120)


if __name__ == '__main__':
    import sys
    {'one_tap':one_tap,'fixed_collision':fixed_collision,'native_refresh':native_refresh,
     'backup_restore':backup_restore,'backup_slots':backup_slots}[sys.argv[1]]()
