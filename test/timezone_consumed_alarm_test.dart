import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/alarm_generation_service.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/fixed_alarm_occurrence.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'release_audit/g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Database db;
  final schedule = ShiftSchedule(
    isRegular: false,
    shiftTypes: const ['Night'],
    assignedDates: const {'2026-10-05': 'Night', '2026-10-06': 'Night'},
  );

  setUpAll(() async {
    initFfi();
    dir = await Directory.systemTemp.createTemp('timezone_consumed_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await DatabaseService.instance.database;
  });
  tearDownAll(() async {
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    await dir.delete(recursive: true);
  });
  setUp(() async {
    for (final table in ['alarms', 'alarm_history', 'alarm_creation_log',
      'alarm_overrides', 'shift_alarm_templates', 'fixed_alarm_consumptions']) {
      await db.delete(table);
    }
    for (final time in ['16:40', '17:10']) {
      await db.insert('shift_alarm_templates', {
        'shift_type': 'Night', 'time': time, 'alarm_type_id': 3, 'day_offset': 0,
      });
    }
  });

  Future<void> seedEnded({String reason = 'swiped', String source = 'auto',
    String? explicitSlot}) async {
    await db.insert('alarm_creation_log', {
      'alarm_id': 43, 'scheduled_date': '2026-10-05T16:40:00',
      'scheduled_time': '16:40', 'shift_type': 'Night', 'alarm_type_id': 3,
      'source': source, 'created_at': '2026-10-01T00:00:00', 'day_offset': 0,
    });
    await db.insert('alarm_history', {
      'alarm_id': 43, 'scheduled_date': '2026-10-05T16:40:00',
      'scheduled_time': '16:40', 'shift_type': 'Night', 'day_offset': 0,
      'actual_ring_time': '2026-10-05T16:40:34+09:00',
      'dismiss_type': reason, 'created_at': '2026-10-05T16:40:34+09:00',
      'fixed_slot_time': explicitSlot,
    });
  }

  // This exercises the actual SQLite diff using Honolulu's post-move wall fields.
  // The host clock/time zone is never changed. Native has an actual ZoneId test.
  Future<RegenerateAlarmsResult> regenerate() => db.transaction((txn) =>
      regenerateFixedAlarmsForDatesTxn(txn: txn, schedule: schedule,
        dates: {DateTime(2026, 10, 5), DateTime(2026, 10, 6)},
        nowOverride: DateTime(2026, 10, 5, 16, 20)));

  test('TZ01 ended Seoul slot must not reappear in a new western-zone day', () async {
    await seedEnded();
    final result = await regenerate();
    final slots = (await db.query('alarms')).map((r) =>
        (r['date'] as String).substring(0, 16)).toList();
    expect(slots, isNot(contains('2026-10-05T16:40')));
    expect(slots, containsAll(['2026-10-05T17:10', '2026-10-06T16:40', '2026-10-06T17:10']));
    expect(result.scheduled, hasLength(3));
    expect(await db.query('alarm_history'), hasLength(1));
  });

  test('TZ02 unhandled slots must still be generated', () async {
    final result = await regenerate();
    expect(result.scheduled, hasLength(4));
    expect(await db.query('alarms'), hasLength(4));
  });

  for (final reason in ['timeout', 'snoozed', 'snooze_skipped_existing_alarm',
    'superseded_by_next_alarm']) {
    test('TZ03 $reason consumes the original occurrence', () async {
      await seedEnded(reason: reason);
      expect((await regenerate()).scheduled, hasLength(3));
    });
  }
  for (final reason in ['superseded', 'cancelled_before_ring']) {
    test('TZ04 $reason is not a completed ring', () async {
      await seedEnded(reason: reason);
      expect((await regenerate()).scheduled, hasLength(4));
    });
  }
  test('TZ05 custom history and ID-only matches cannot suppress fixed alarms', () async {
    await seedEnded(source: 'manual');
    expect((await regenerate()).scheduled, hasLength(4));
    await db.delete('alarms');
    await db.update('alarm_creation_log', {'source': 'auto', 'scheduled_date': '2026-10-04T16:40:00'});
    expect((await regenerate()).scheduled, hasLength(4));
  });
  test('TZ06 explicit slot survives missing creation logs and history clearing', () async {
    await seedEnded(source: 'manual', explicitSlot: '2026-10-05T16:40:00');
    await db.delete('alarm_creation_log');
    await DatabaseService.instance.resetAllAlarmHistoryAndLog();
    expect(await db.query('alarm_history'), isEmpty);
    expect(await db.query('fixed_alarm_consumptions'), hasLength(1));
    expect((await regenerate()).scheduled, hasLength(3));
  });
  test('TZ07 full schedule reset explicitly starts a new consumption lifetime', () async {
    await seedEnded();
    await regenerate();
    await DatabaseService.instance.deleteAllAlarms(resetSchedule: true);
    expect(await db.query('fixed_alarm_consumptions'), isEmpty);
    expect(await db.query('alarm_history'), isEmpty);
  });
  test('TZ08 snoozed row retains its absolute target while original stays consumed', () async {
    await seedEnded(reason: 'snoozed');
    const target = '2026-10-06T02:55:00+00:00';
    await db.insert('alarms', {'id': 43, 'type': 'snoozed', 'date': target,
      'time': '11:55', 'shift_type': 'Night', 'day_offset': 0, 'alarm_type_id': 3});
    expect((await regenerate()).scheduled, hasLength(3));
    expect((await db.query('alarms', where: 'id = 43')).single['date'], target);
    expect((await regenerate()).scheduled, isEmpty);
  });
  test('TZ09 end record failure rolls back deletion and successful retry records origin', () async {
    final id = await DatabaseService.instance.insertAlarm(Alarm(
      date: DateTime(2026, 10, 5, 16, 40), time: '16:40', type: 'fixed',
      alarmTypeId: 3, shiftType: 'Night', fixedSlotTime: '2026-10-05T16:40:00'), source: 'auto');
    await db.execute("CREATE TRIGGER reject_consumption BEFORE INSERT ON fixed_alarm_consumptions BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");
    try {
      await expectLater(DatabaseService.instance.deleteAlarm(id, dismissType: 'swiped'), throwsA(anything));
      expect(await db.query('alarms', where: 'id = ?', whereArgs: [id]), hasLength(1));
      expect(await db.query('alarm_history'), isEmpty);
      expect(await db.query('fixed_alarm_consumptions'), isEmpty);
    } finally { await db.execute('DROP TRIGGER reject_consumption'); }
    await DatabaseService.instance.deleteAlarm(id, dismissType: 'swiped');
    expect(await db.query('fixed_alarm_consumptions'), hasLength(1));
    expect((await regenerate()).scheduled, hasLength(3));
  });
  test('TZ10 a failed consumed-slot read/import cannot be treated as empty history', () async {
    await seedEnded();
    await db.execute("CREATE TRIGGER reject_consumption BEFORE INSERT ON fixed_alarm_consumptions BEGIN SELECT RAISE(ABORT, 'injected read-import failure'); END");
    try {
      await expectLater(regenerate(), throwsA(anything));
      expect(await db.query('alarms'), isEmpty);
      expect(await db.query('alarm_creation_log'), hasLength(1));
    } finally { await db.execute('DROP TRIGGER reject_consumption'); }
  });
  test('TZ11 slot identity includes shift and day offset', () async {
    await seedEnded();
    await db.update('alarm_history', {'day_offset': 1});
    expect((await regenerate()).scheduled, hasLength(4));
    await db.delete('alarms');
    await db.update('alarm_history', {'day_offset': 0, 'shift_type': 'Day'});
    expect((await regenerate()).scheduled, hasLength(4));
  });
  test('TZ12 metadata backfill keeps existing ID and has no OS diff', () async {
    await regenerate();
    final before = await db.query('alarms', orderBy: 'id');
    await db.update('alarms', {'fixed_slot_time': null});
    final result = await regenerate();
    expect(result.cancelIds, isEmpty);
    expect(result.scheduled, isEmpty);
    final after = await db.query('alarms', orderBy: 'id');
    expect(after, before);
    expect(await readConsumedFixedOccurrences(db, '2026-10-05', '2026-10-07'), isEmpty);
  });
  test('TZ13 legacy ID reused by a custom backup is ambiguous even at the same slot', () async {
    await seedEnded();
    final auto = (await db.query('alarm_creation_log')).single;
    await db.insert('alarm_creation_log', {...auto, 'id': null,
      'source': 'custom_preset', 'created_at': '2026-10-05T15:00:00'});
    expect((await regenerate()).scheduled, hasLength(4),
        reason: 'A custom end must not consume an unrelated fixed occurrence with a reused ID');
    expect(await db.query('fixed_alarm_consumptions'), isEmpty);
  });
}
