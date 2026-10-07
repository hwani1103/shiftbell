import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/models/backup_payload.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/alarm_provider.dart';
import 'package:shiftbell/providers/friend_provider.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/services/backup_service.dart';
import 'package:shiftbell/services/backup_validator.dart';
import 'package:shiftbell/services/backup_watcher.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/services/friend_sync_service.dart';
import 'package:shiftbell/services/restore_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  final calls = <MethodCall>[];
  String? failMethod;
  var epochChanges = 0;
  var epoch = 1;
  Completer<void>? writeGate;
  Future<void> Function()? onClearOs;
  Future<void> Function()? onReconcileOs;
  Future<void> Function()? onCancelAlarm;
  int? ringingId;
  final service = DatabaseService.instance;
  final restore = RestoreCoordinator.instance;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('full_audit_critical_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await service.database;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      calls.add(call);
      if (call.method == failMethod) {
        throw PlatformException(code: 'audit_injected_failure');
      }
      switch (call.method) {
        case 'cancelNativeAlarm':
          await onCancelAlarm?.call();
          return null;
        case 'restoreAcquireLock': return true;
        case 'restorePrepareCarryOver': return {'carryIds': <int>[], 'epoch': epoch};
        case 'restoreRingEpoch':
          if (epochChanges > 0) { epochChanges--; epoch++; }
          return epoch;
        case 'restoreClearOs':
          await onClearOs?.call();
          return null;
        case 'restoreReconcileOs':
          await onReconcileOs?.call();
          return {'wakeFailures': 0};
        case 'stopRingingAlarm':
          if ((call.arguments as Map)['alarmId'] != ringingId) return false;
          ringingId = null;
          return true;
        case 'writeBackupFile':
          await writeGate?.future;
          return true;
        default: return null;
      }
    });
  });
  tearDownAll(() async {
    messenger.setMockMethodCallHandler(kAlarmChannel, null);
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });
  setUp(() async {
    failMethod = null;
    epochChanges = 0;
    epoch = 1;
    writeGate = null;
    onClearOs = null;
    onReconcileOs = null;
    onCancelAlarm = null;
    ringingId = null;
    calls.clear();
    firebaseReady = false;
    SharedPreferences.setMockInitialValues({});
    if (await restore.hasPendingJob()) await restore.safeEnd();
    await db.execute('DROP TRIGGER IF EXISTS audit_restore_failure');
    for (final table in ['alarms', 'alarm_history', 'alarm_creation_log',
      'shift_schedule', 'shift_alarm_templates', 'alarm_overrides', 'friends', 'date_memos',
      'fixed_alarm_consumptions']) {
      await db.delete(table);
    }
  });

  Map<String, dynamic> row(int id, String type, DateTime date) =>
      Alarm(id: id, time: '07:00', date: date, type: type, alarmTypeId: 1).toMap();
  Future<BackupPayload> payload({List<Map<String, dynamic>> alarms = const [],
    Map<String, dynamic> preferences = const {}}) async => BackupPayload(
      schemaVersion: kBackupSchemaVersion, exportedAt: DateTime.now(),
      appVersionName: 'audit', appVersionCode: 25,
      tables: {'alarm_types': await db.query('alarm_types'), 'alarms': alarms},
      preferences: preferences);

  test('AUD-A01 all-alarm deletion cancels fixed custom snoozed and keeps history', () async {
    for (final item in [(1, 'fixed'), (2, 'custom'), (3, 'snoozed')]) {
      await service.insertAlarm(Alarm.fromMap(row(item.$1, item.$2, DateTime.now().add(const Duration(days: 1)))));
    }
    final ids = (await db.query('alarms')).map((r) => r['id']).toSet();
    ringingId = ids.last as int;
    await service.insertAlarmTemplate(shiftType: 'Day', time: '07:00', alarmTypeId: 1);
    onCancelAlarm = () async {
      // Native cancelIfGone keeps/re-schedules any row still in the DB.
      expect(await db.query('alarms'), isEmpty);
      expect(await db.query('shift_alarm_templates'), isEmpty);
      expect(await db.query('alarm_history'), hasLength(3));
    };
    final notifier = AlarmNotifier();
    addTearDown(notifier.dispose);
    await notifier.refresh();
    await notifier.deleteAllAlarmsCompletely();
    expect(ringingId, isNull, reason: 'Deleting reservations must also end the active ring');
    expect(await db.query('alarms'), isEmpty);
    expect(await db.query('alarm_history'), hasLength(3));
    expect(await db.query('alarm_creation_log'), hasLength(3));
    expect(calls.where((c) => c.method == 'cancelNativeAlarm').map((c) => (c.arguments as Map)['id']).toSet(), ids);
    expect(await db.query('shift_alarm_templates'), isEmpty);
  });

  test('AUD-A01b schedule reset commits deletion before Native cancellation', () async {
    SharedPreferences.setMockInitialValues({'friend_share_enabled':true,
      'friend_share_my_name':'Owner', 'friend_share_generation':3});
    await service.insertAlarm(Alarm.fromMap(row(42, 'custom', DateTime.now().add(const Duration(days: 1)))));
    await service.insertAlarmTemplate(shiftType: 'Day', time: '07:00', alarmTypeId: 1);
    onCancelAlarm = () async {
      expect(await db.query('alarms'), isEmpty);
      expect(await db.query('shift_alarm_templates'), isEmpty);
    };
    final notifier = ScheduleNotifier();
    addTearDown(notifier.dispose);
    await notifier.refresh();
    await notifier.resetSchedule();
    expect((await FriendSyncService.instance.getShareState()).intent,
      FriendShareIntent.stopPending, reason: 'Offline reset persists revocation');
    await FriendSyncService.instance.onAppStarted(null);
    expect(await FriendSyncService.instance.isSharingEnabled(), false);
    expect(calls.where((c) => c.method == 'cancelNativeAlarm'), hasLength(1));
    expect(await db.query('alarms'), isEmpty);
  });

  test('AUD-A01c failed all-delete transaction preserves rows templates and history', () async {
    await service.insertAlarm(Alarm.fromMap(row(42, 'custom', DateTime.now().add(const Duration(days: 1)))));
    await service.insertAlarmTemplate(shiftType: 'Day', time: '07:00', alarmTypeId: 1);
    await db.execute("CREATE TRIGGER audit_delete_failure BEFORE DELETE ON shift_alarm_templates BEGIN SELECT RAISE(ABORT, 'injected'); END");
    try {
      await expectLater(service.deleteAllAlarms(clearTemplates: true), throwsA(anything));
      expect(await db.query('alarms'), hasLength(1));
      expect(await db.query('shift_alarm_templates'), hasLength(1));
      expect(await db.query('alarm_history'), isEmpty);
    } finally {
      await db.execute('DROP TRIGGER audit_delete_failure');
    }
  });

  test('AUD-A03 custom type change then delete preserves source log without fixed override', () async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final alarmId = await service.insertAlarm(Alarm.fromMap(row(42, 'custom', tomorrow)));
    final notifier = AlarmNotifier();
    addTearDown(notifier.dispose);
    await notifier.refresh();
    await notifier.updateAlarmType(alarmId, 2);
    expect((await db.query('alarms')).single['alarm_type_id'], 2);
    expect(await db.query('alarm_overrides'), isEmpty);
    await notifier.deleteAlarm(alarmId, tomorrow);
    expect(await db.query('alarms'), isEmpty);
    expect(await db.query('alarm_history'), hasLength(1));
    expect(await db.query('alarm_creation_log'), hasLength(1));
  });

  test('AUD-B01 export includes only future custom plus permanent history', () async {
    final future = DateTime.now().add(const Duration(days: 2));
    for (final item in [(1, 'fixed'), (2, 'custom'), (3, 'snoozed')]) {
      await db.insert('alarms', row(item.$1, item.$2, future));
    }
    await db.insert('alarms', row(4, 'custom', DateTime.now().subtract(const Duration(days: 2))));
    final before = await db.query('alarms');
    final exported = await db.transaction(BackupService.readBackupTables);
    expect(exported['alarms']!.map((r) => r['id']), [2]);
    expect(exported, contains('alarm_history'));
    expect(exported, isNot(contains('sqlite_sequence')));
    expect(await db.query('alarms'), before);
  });

  for (final invalid in ['2030-02-30T07:00:00', '2030-13-01T07:00:00',
    '2030-01-01T24:00:00', '2030-01-01T07:60:00', '2030-01-01T07:00:60']) {
    test('AUD-B02 rejects normalized invalid backup date $invalid before any mutation', () async {
      final alarm = row(1, 'custom', DateTime(2030, 1, 1))..['date'] = invalid;
      final data = await payload(alarms: [alarm]);
      final before = await db.query('alarm_types');
      await expectLater(restore.start(data, overwrite: true), throwsA(isA<BackupValidationException>()));
      expect(await db.query('alarm_types'), before);
      expect(calls.where((c) => c.method.startsWith('restore')), isEmpty);
      expect(await restore.hasPendingJob(), isFalse);
    });
  }

  test('AUD-B03 invalid assigned day is rejected instead of normalized', () async {
    final alarm = row(1, 'custom', DateTime(2030, 1, 1))
      ..['preset_slot'] = 0 ..['assigned_day'] = '2030-02-30';
    expect(await BackupValidator.validate(await payload(alarms: [alarm]), db), isNotEmpty);
  });

  for (final valid in ['2032-02-29T07:00:00', '2030-02-28T23:59:59.123456',
    '2026-03-08T02:30:00', '2026-11-01T01:30:00']) {
    test('AUD-B16 valid calendar and DST wall time stays restorable $valid', () async {
      final alarm = row(1, 'custom', DateTime(2030, 1, 1))..['date'] = valid;
      expect(await BackupValidator.validate(await payload(alarms: [alarm]), db), isEmpty);
    });
  }

  for (final mutation in <String, Map<String, dynamic>>{
    'non-custom fixed': {'type': 'fixed'},
    'non-custom snoozed': {'type': 'snoozed'},
    'unknown alarm type': {'alarm_type_id': 9999},
    'invalid clock': {'time': '24:00'},
    'invalid column': {'unexpected': 1},
    'invalid column type': {'alarm_type_id': '1'},
    'incomplete preset link': {'preset_slot': 0},
    'preset outside five slots': {'preset_slot': 5, 'assigned_day': '2030-01-01'},
  }.entries) {
    test('AUD-B14 backup rejects ${mutation.key} before OS changes', () async {
      final alarm = row(1, 'custom', DateTime(2030, 1, 1))..addAll(mutation.value);
      await expectLater(restore.start(await payload(alarms: [alarm]), overwrite: true), throwsA(isA<BackupValidationException>()));
      expect(calls.where((c) => c.method.startsWith('restore')), isEmpty);
    });
  }

  test('AUD-B04 restore preserves local snooze on colliding backup ID and keeps local share intent', () async {
    final future = DateTime.now().add(const Duration(days: 2));
    await db.insert('alarms', row(7, 'snoozed', future)..['date'] = future.toUtc().toIso8601String());
    SharedPreferences.setMockInitialValues({'friend_share_intent': 'stop_pending', 'friend_share_enabled': false, 'calendar_theme_id': 'old'});
    await restore.start(await payload(alarms: [row(7, 'custom', future)], preferences: {'friend_share_intent': 'active', 'schedule_tab_enabled': false}), overwrite: true);
    final alarms = await db.query('alarms');
    expect(alarms, hasLength(2));
    expect(alarms.singleWhere((a) => a['type'] == 'snoozed')['id'], 7);
    expect(alarms.singleWhere((a) => a['type'] == 'custom')['id'], isNot(7));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('friend_share_intent'), 'stop_pending');
    expect(prefs.getString('calendar_theme_id'), isNull);
    expect(prefs.getBool('schedule_tab_enabled'), false);
    expect(await restore.hasPendingJob(), isFalse);
  });

  for (final method in ['restoreClearOs', 'restoreReconcileOs']) {
    test('AUD-B05 $method failure retains resumable job and retry converges', () async {
      final data = await payload(alarms: [row(9, 'custom', DateTime.now().add(const Duration(days: 2)))]);
      failMethod = method;
      await expectLater(restore.start(data, overwrite: true), throwsA(isA<RestoreIncompleteException>()));
      expect(await restore.hasPendingJob(), isTrue);
      failMethod = null;
      await restore.resume();
      expect(await restore.hasPendingJob(), isFalse);
      expect(await db.query('alarms'), hasLength(1));
      expect(calls.where((c) => c.method == 'restoreReleaseLock'), isNotEmpty);
    });
  }

  test('AUD-B06 ring epoch changes during restore rollback then retry without duplicate alarms', () async {
    epochChanges = 1;
    await restore.start(await payload(alarms: [row(9, 'custom', DateTime.now().add(const Duration(days: 2)))]), overwrite: true);
    expect(await db.query('alarms'), hasLength(1));
    expect(calls.where((c) => c.method == 'restoreRingEpoch'), hasLength(2));
    expect(await restore.hasPendingJob(), isFalse);
  });

  test('AUD-B07 repeated ring epoch changes stop after bounded attempts and remain resumable', () async {
    epochChanges = 10;
    await expectLater(restore.start(await payload(), overwrite: true), throwsA(isA<RestoreIncompleteException>()));
    expect(calls.where((c) => c.method == 'restoreRingEpoch'), hasLength(5));
    expect(await restore.hasPendingJob(), isTrue);
    epochChanges = 0;
    await restore.resume();
    expect(await restore.hasPendingJob(), isFalse);
  });

  test('AUD-B07b repeated epochs with snooze collision and stop_pending converge on resume', () async {
    final future = DateTime.now().add(const Duration(days: 2));
    await db.insert('alarms', row(7, 'snoozed', future));
    SharedPreferences.setMockInitialValues({
      'friend_share_intent': 'stop_pending',
      'friend_share_generation': 12,
    });
    final osIds = <int>{7};
    onClearOs = () async => osIds.clear();
    onReconcileOs = () async {
      osIds.addAll((await db.query('alarms')).map((r) => r['id'] as int));
    };
    epochChanges = 10;
    await expectLater(
      restore.start(await payload(alarms: [row(7, 'custom', future)],
        preferences: {'friend_share_intent': 'active'}), overwrite: true),
      throwsA(isA<RestoreIncompleteException>()),
    );
    expect(calls.where((c) => c.method == 'restoreRingEpoch'), hasLength(5));
    expect((await db.query('alarms')).single['type'], 'snoozed');
    expect(await restore.hasPendingJob(), isTrue);
    epochChanges = 0;
    await restore.resume();
    final rows = await db.query('alarms');
    expect(rows, hasLength(2));
    expect(rows.singleWhere((r) => r['type'] == 'snoozed')['id'], 7);
    expect(rows.singleWhere((r) => r['type'] == 'custom')['id'], isNot(7));
    expect(osIds, rows.map((r) => r['id'] as int).toSet());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('friend_share_intent'), 'stop_pending');
    expect(prefs.getInt('friend_share_generation'), 12);
    expect(await restore.hasPendingJob(), isFalse);
  });

  test('AUD-B08 lost restore copy reconciles existing data and clears pending job', () async {
    failMethod = 'restoreClearOs';
    await expectLater(restore.start(await payload(), overwrite: true), throwsA(isA<RestoreIncompleteException>()));
    final job = (await restore.loadPendingJob())!;
    await File(job.copyPath).delete();
    failMethod = null;
    await expectLater(restore.resume(), throwsA(isA<RestoreCopyLostException>()));
    expect(await restore.hasPendingJob(), isFalse);
  });

  test('AUD-B09 DB insertion failure rolls back all source tables and resumes', () async {
    await service.createMemo('2030-01-01', 'keep original');
    await db.execute("CREATE TRIGGER audit_restore_failure BEFORE INSERT ON alarms BEGIN SELECT RAISE(ABORT, 'injected'); END");
    await expectLater(restore.start(await payload(alarms: [row(9, 'custom', DateTime.now().add(const Duration(days: 2)))]), overwrite: true), throwsA(isA<RestoreIncompleteException>()));
    expect((await db.query('date_memos')).single['memo_text'], 'keep original');
    await db.execute('DROP TRIGGER audit_restore_failure');
    await restore.resume();
    expect(await db.query('alarms'), hasLength(1));
    expect(await restore.hasPendingJob(), isFalse);
  });

  test('AUD-B09b resume clears reservations recreated by failure recovery before replacing DB', () async {
    final future = DateTime.now().add(const Duration(days: 2));
    await db.insert('alarms', row(800, 'fixed', future));
    final osIds = <int>{800};
    onClearOs = () async {
      for (final item in await db.query('alarms')) {
        osIds.remove(item['id']);
      }
    };
    onReconcileOs = () async {
      // Native failure recovery re-registers the old DB. After a successful
      // replacement it generates a new fixed ID, as observed on the USB phone.
      if ((await db.query('alarms', where: "type='fixed'")).isEmpty) {
        await db.insert('alarms', row(801, 'fixed', future));
      }
      osIds.addAll((await db.query('alarms')).map((r) => r['id'] as int));
    };
    await db.execute("CREATE TRIGGER audit_restore_failure BEFORE INSERT ON alarms WHEN NEW.type='custom' BEGIN SELECT RAISE(ABORT, 'injected'); END");
    await expectLater(
        restore.start(await payload(alarms: [row(9, 'custom', future)]), overwrite: true),
        throwsA(isA<RestoreIncompleteException>()));
    expect((await restore.loadPendingJob())!.phase, RestorePhase.osCleared);
    expect(osIds, {800});
    await db.execute('DROP TRIGGER audit_restore_failure');
    await restore.resume();
    expect(osIds, (await db.query('alarms')).map((r) => r['id'] as int).toSet());
    expect(osIds, isNot(contains(800)));
    expect(await restore.hasPendingJob(), isFalse);
  });

  Future<void> seedSchedule() => service.saveShiftSchedule(ShiftSchedule(
      isRegular: true, shiftTypes: ['Day', 'Off'], pattern: ['Day', 'Off'],
      todayIndex: 0, startDate: DateTime(2026, 9, 1))).then((_) {});

  test('AUD-B10 automatic backup skips identical content but captures preference changes', () async {
    await seedSchedule();
    expect(await BackupWatcher.instance.backupNow(), true);
    expect(await BackupWatcher.instance.backupNow(), true);
    expect(calls.where((c) => c.method == 'writeBackupFile'), hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('schedule_tab_enabled', false);
    expect(await BackupWatcher.instance.backupNow(), true);
    expect(calls.where((c) => c.method == 'writeBackupFile'), hasLength(2));
    expect(prefs.getString(BackupWatcher.kLastSavedAtAutoKey), isNotNull);
    expect(prefs.getString(BackupWatcher.kLastSavedAtManualKey), isNull);
  });

  test('AUD-B11 failed manual write preserves last-success metadata and auto slot', () async {
    await seedSchedule();
    expect(await BackupWatcher.instance.backupNow(), true);
    final prefs = await SharedPreferences.getInstance();
    final autoHash = prefs.getString('backup_last_content_hash');
    final autoTime = prefs.getString(BackupWatcher.kLastSavedAtAutoKey);
    failMethod = 'writeBackupFile';
    expect(await BackupWatcher.instance.backupNow(manual: true), false);
    expect(prefs.getString(BackupWatcher.kLastSavedAtManualKey), isNull);
    expect(prefs.getString('backup_last_content_hash'), autoHash);
    expect(prefs.getString(BackupWatcher.kLastSavedAtAutoKey), autoTime);
  });

  test('AUD-B12 simultaneous manual and auto requests drain both slots after changed data', () async {
    await seedSchedule();
    writeGate = Completer<void>();
    final first = BackupWatcher.instance.backupNow();
    for (var i = 0; i < 200 && !calls.any((c) => c.method == 'writeBackupFile'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(calls.where((c) => c.method == 'writeBackupFile'), hasLength(1));
    final manual = BackupWatcher.instance.backupNow(manual: true);
    final auto = BackupWatcher.instance.backupNow();
    await service.createMemo('2030-01-01', 'changed during write');
    writeGate!.complete();
    expect(await Future.wait([first, manual, auto]), everyElement(true));
    expect(calls.where((c) => c.method == 'writeBackupFile').map((c) => (c.arguments as Map)['kind']), ['auto','manual','auto']);
  });

  test('AUD-B13 same backup restored twice merges permanent history once', () async {
    final scheduled = DateTime.now().add(const Duration(days: 2));
    final id = await service.insertAlarm(Alarm(time: '07:00', date: scheduled, type: 'custom', alarmTypeId: 1));
    await service.deleteAlarm(id);
    final data = await BackupService.instance.exportAll();
    expect(data.tables['alarm_history'], hasLength(1));
    await restore.start(data, overwrite: true);
    await restore.start(data, overwrite: true);
    expect(await db.query('alarm_history'), hasLength(1));
    expect(await db.query('alarm_creation_log'), hasLength(1));
  });

  test('AUD-B15 empty schedule and pending restore never overwrite automatic backup', () async {
    expect(await BackupWatcher.instance.backupNow(), true);
    expect(calls.where((c) => c.method == 'writeBackupFile'), isEmpty);
    await seedSchedule();
    failMethod = 'restoreClearOs';
    await expectLater(restore.start(await payload(), overwrite: true), throwsA(isA<RestoreIncompleteException>()));
    expect(await BackupWatcher.instance.backupNow(), true);
    expect(await BackupWatcher.instance.backupNow(manual: true), false);
    expect(calls.where((c) => c.method == 'writeBackupFile'), isEmpty);
    failMethod = null;
    await restore.safeEnd();
  });

  test('AUD-F01 100 offline friends retain cache and database counts after refresh rename delete', () async {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.localeTestValue = const Locale('ko');
    addTearDown(dispatcher.clearLocaleTestValue);
    for (var i = 0; i < 100; i++) {
      await service.insertFriend(name: 'Friend $i', ownerId: 'audit_$i', dataJson: null);
    }
    final notifier = FriendNotifier();
    addTearDown(notifier.dispose);
    await notifier.refreshAll(force: true);
    expect(notifier.state, hasLength(100));
    expect(notifier.state.every((f) => f.availability == FriendAvailability.unconfirmed), true);
    final last = notifier.state.last;
    await notifier.renameFriend(last.id, 'Last friend');
    expect(notifier.state.singleWhere((f) => f.id == last.id).name, 'Last friend');
    await notifier.removeFriend(last.id);
    expect(await db.query('friends'), hasLength(99));
    expect(notifier.state, hasLength(99));
  });

  test('TZ-B01 consumed state round-trips after visible history was cleared', () async {
    await db.insert('fixed_alarm_consumptions', {'slot_time': '2026-10-05T16:40:00',
      'shift_type': 'Night', 'day_offset': 0, 'recorded_at': '2026-10-05T07:40:34Z'});
    final data = await BackupService.instance.exportAll();
    expect(data.tables['fixed_alarm_consumptions'], hasLength(1));
    expect(await BackupValidator.validate(data, db), isEmpty);
    await db.delete('fixed_alarm_consumptions');
    await restore.start(data, overwrite: true);
    await restore.start(data, overwrite: true);
    expect(await db.query('fixed_alarm_consumptions'), hasLength(1));
    expect(await db.query('alarm_history'), isEmpty);
  });

  test('TZ-B02 old backup history supplies consumed state without suppressing custom history', () async {
    final history = <String, dynamic>{'id': 1, 'alarm_id': 43,
      'scheduled_date': '2026-10-05T16:40:00', 'scheduled_time': '16:40',
      'shift_type': 'Night', 'day_offset': 0, 'actual_ring_time': '2026-10-05T16:40:34',
      'created_at': '2026-10-05T16:40:34', 'dismiss_type': 'swiped', 'snooze_count': 0};
    final data = await payload();
    data.tables['alarm_history'] = [history];
    data.tables['alarm_creation_log'] = [{
      'id': 1, 'alarm_id': 43, 'scheduled_date': history['scheduled_date'],
      'scheduled_time': '16:40', 'shift_type': 'Night', 'day_offset': 0,
      'alarm_type_id': 1, 'source': 'auto', 'created_at': '2026-10-01T00:00:00',
    }];
    await restore.start(data, overwrite: true);
    expect((await db.query('fixed_alarm_consumptions')).single['slot_time'], '2026-10-05T16:40:00');
    await restore.start(await payload(), overwrite: true);
    expect(await db.query('fixed_alarm_consumptions'), hasLength(1),
      reason: 'An older backup with no ledger must not erase locally consumed slots');
  });

  test('TZ-B03 newer backup enriches an identical legacy history with its nominal DST slot', () async {
    final history = <String, dynamic>{'id': 1, 'alarm_id': 43,
      'scheduled_date': '2026-03-08T03:30:00', 'scheduled_time': '03:30',
      'shift_type': 'Night', 'day_offset': 0, 'actual_ring_time': '2026-03-08T03:30:34',
      'created_at': '2026-03-08T03:30:34', 'dismiss_type': 'swiped', 'snooze_count': 0};
    await db.insert('alarm_history', history);
    final data = await payload();
    data.tables['alarm_history'] = [{...history, 'fixed_slot_time': '2026-03-08T02:30:00'}];
    await restore.start(data, overwrite: true);
    expect((await db.query('alarm_history')).single['fixed_slot_time'], '2026-03-08T02:30:00');
    expect((await db.query('fixed_alarm_consumptions')).single['slot_time'], '2026-03-08T02:30:00');
  });

  test('TZ-B04 restore carries snooze origin and target without replacing the consumed ledger', () async {
    final target = DateTime.now().add(const Duration(minutes: 15));
    final alarm = Alarm(id: 43, time: '07:15', date: target, type: 'snoozed',
      alarmTypeId: 1, shiftType: 'Night', fixedSlotTime: '2026-10-05T16:40:00');
    await db.insert('alarms', alarm.toMap());
    await db.insert('fixed_alarm_consumptions', {'slot_time': alarm.fixedSlotTime,
      'shift_type': 'Night', 'day_offset': 0, 'recorded_at': '2026-10-05T07:40:34Z'});
    await restore.start(await payload(), overwrite: true);
    final carried = (await db.query('alarms')).single;
    expect(carried['id'], 43);
    expect(carried['date'], alarm.toMap()['date']);
    expect(carried['fixed_slot_time'], alarm.fixedSlotTime);
    expect(await db.query('fixed_alarm_consumptions'), hasLength(1));
  });

  test('TZ-B05 consumed backup keys distinguish shift suffix from signed day offset', () async {
    for (final pair in [('Night-', 1), ('Night', -1)]) {
      await db.insert('fixed_alarm_consumptions', {
        'slot_time': '2026-10-05T16:40:00', 'shift_type': pair.$1,
        'day_offset': pair.$2, 'recorded_at': '2026-10-05T07:40:34Z',
      });
    }
    final data = await BackupService.instance.exportAll();
    expect(await BackupValidator.validate(data, db), isEmpty);
    await db.delete('fixed_alarm_consumptions');
    await restore.start(data, overwrite: true);
    await restore.start(data, overwrite: true);
    final rows = await db.query('fixed_alarm_consumptions');
    expect(rows.map((r) => (r['shift_type'], r['day_offset'])).toSet(),
        {('Night-', 1), ('Night', -1)});
  });
}
