// T11-05 — Dart 재생성 DB diff가 동일 입력에서 ID·이력·생성 로그를 보존하는지 검증.
// 독립 기대값: fixtures/review_fixture_additions.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/alarm_generation_service.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Database db;
  late Map<String, dynamic> fixture;

  setUpAll(() async {
    initFfi();
    dir = await Directory.systemTemp.createTemp('g1_regen_diff_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await DatabaseService.instance.database;
    final root = jsonDecode(
      File('test/release_audit/g1/fixtures/review_fixture_additions.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    fixture = (root['cases'] as List).cast<Map<String, dynamic>>().firstWhere(
          (c) => c['id'] == 'DART_REGEN_IDEMPOTENT_EXISTING_ROW',
        );
  });

  tearDownAll(() async {
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  setUp(() async {
    for (final table in [
      'alarm_overrides',
      'alarms',
      'shift_alarm_templates',
      'shift_schedule',
      'alarm_history',
      'alarm_creation_log',
    ]) {
      await db.delete(table);
    }
  });

  test('T11-05 동일 입력 재생성은 두 번 모두 DB와 OS diff가 0이고 ID를 보존한다', () async {
    final template =
        (fixture['templates'] as List).single as Map<String, dynamic>;
    await db.insert('shift_alarm_templates', template);
    final existing =
        (fixture['existing_alarm_rows'] as List).single as Map<String, dynamic>;
    await db.insert('alarms', {
      'id': existing['id'],
      'time': existing['time'],
      'date': existing['slot_time'],
      'type': existing['type'],
      'alarm_type_id': existing['alarm_type_id'],
      'shift_type': existing['shift_type'],
      'day_offset': existing['day_offset'],
    });
    final assigned = ((fixture['schedule'] as Map)['assigned_dates'] as Map)
        .map((key, value) => MapEntry(key as String, value as String));
    final schedule = ShiftSchedule(
      isRegular: false,
      shiftTypes: const ['DAY'],
      assignedDates: assigned,
    );
    final now = DateTime.parse(fixture['now'] as String);
    final date = DateTime(now.year, now.month, now.day);

    Future<RegenerateAlarmsResult> run() => db.transaction(
          (txn) => regenerateFixedAlarmsForDatesTxn(
            txn: txn,
            schedule: schedule,
            dates: {date},
            nowOverride: now,
          ),
        );
    Future<List<int>> alarmIds() async =>
        (await db.query('alarms', orderBy: 'id'))
            .map((r) => r['id'] as int)
            .toList();
    Future<int> rowCount(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
      return rows.single['count'] as int;
    }

    final first = await run();
    // 수정 전 기대 결과: FAIL - ID 1201 삭제, superseded/creation log와 OS cancel·schedule이 생김.
    // 수정 후 기대 결과: PASS - 정확히 같은 행은 그대로 유지.
    expect(await alarmIds(), [1201]);
    expect(first.cancelIds, isEmpty);
    expect(first.scheduled, isEmpty);
    expect(await rowCount('alarm_history'), 0);
    expect(await rowCount('alarm_creation_log'), 0);

    final second = await run();
    expect(await alarmIds(), [1201]);
    expect(second.cancelIds, isEmpty);
    expect(second.scheduled, isEmpty);
    expect(await rowCount('alarm_history'), 0);
    expect(await rowCount('alarm_creation_log'), 0);
  });
}
