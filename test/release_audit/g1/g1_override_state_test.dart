// 출시전 감사 G1 #31 / D12 - 사용자 변경의 개별 예외 기록과 원본 변경 시 예외 정리 (docs/release_audit/g1/handoff.md)
//
// 실제 SQLite(sqflite_common_ffi) 위에서 제품 DatabaseService를 그대로 사용(_onCreate v24 스키마 = alarm_overrides 포함).
// 기대값: test/release_audit/g1/fixtures/state_change_cases.json(T11a, Codex - contracts §2·v4 #31만 근거)의
// D12_ASSIGNMENT_CHANGE / D12_TEMPLATE_CHANGE / D12_SHIFT_RENAME / D12_ASSIGNMENT_ABA / D12_TEMPLATE_ABA.
// D11 30일 정리는 Native 엔진이 수행 → Kotlin G1GenerationEngineTest.
// "미래" 판정 시각은 fixture now(2026-09-14T10:30:00)로 고정(DatabaseService.debugNowOverride).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases = (jsonDecode(File('test/release_audit/g1/fixtures/state_change_cases.json').readAsStringSync())
          as Map<String, dynamic>)['cases'] as List;
  Map<String, dynamic> caseOf(String id) =>
      cases.cast<Map<String, dynamic>>().firstWhere((c) => c['id'] == id);

  late Directory dir;
  late Database db;
  final service = DatabaseService.instance;

  setUpAll(() async {
    initFfi();
    dir = await Directory.systemTemp.createTemp('g1_override_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    DatabaseService.debugNowOverride = () => DateTime(2026, 9, 14, 10, 30);
    db = await service.database;
  });

  tearDownAll(() async {
    await db.close();
    DatabaseService.debugNowOverride = null;
    DatabaseService.debugIsAndroidOverride = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  setUp(() async {
    for (final t in ['alarm_overrides', 'alarms', 'shift_alarm_templates', 'shift_schedule', 'alarm_history', 'alarm_creation_log']) {
      await db.delete(t);
    }
  });

  Future<void> seedOverrides(List list) async {
    for (final o in list.cast<Map<String, dynamic>>()) {
      await db.insert('alarm_overrides', {
        'id': o['id'],
        'slot_time': o['slot_time'],
        'shift_type': o['shift_type'],
        'day_offset': o['day_offset'],
        'action': o['action'],
        'alarm_type_id': o['alarm_type_id'],
        'origin_date': o['origin_date'],
        'origin_shift': o['origin_shift'],
        'created_at': '2026-09-01T00:00:00',
      });
    }
  }

  Future<List<int>> overrideIds() async =>
      (await db.query('alarm_overrides', orderBy: 'id')).map((r) => r['id'] as int).toList();

  Future<int> insertAlarm({required String date, required String type, String? shift = 'A', int offset = 0, int typeId = 1}) =>
      db.insert('alarms', {
        'time': date.substring(11, 16),
        'date': date,
        'type': type,
        'alarm_type_id': typeId,
        'shift_type': shift,
        'day_offset': offset,
      });

  Future<ShiftSchedule> saveIrregular(Map<String, String> assigned, {List<String> shifts = const ['A', 'B']}) async {
    final id = await service.saveShiftSchedule(
        ShiftSchedule(isRegular: false, shiftTypes: shifts, assignedDates: Map.of(assigned)));
    return ShiftSchedule(id: id, isRegular: false, shiftTypes: shifts, assignedDates: Map.of(assigned));
  }

  Future<void> seedTemplatesDirect(List list) async {
    for (final t in list.cast<Map<String, dynamic>>()) {
      await db.insert('shift_alarm_templates', {
        'shift_type': t['shift_type'],
        'time': t['time'],
        'alarm_type_id': t['alarm_type_id'],
        'day_offset': t['day_offset'],
      });
    }
  }

  List<Map<String, dynamic>> templateMaps(List list) => list
      .cast<Map<String, dynamic>>()
      .map((t) => {'shift_type': t['shift_type'], 'time': t['time'], 'alarm_type_id': t['alarm_type_id'], 'day_offset': t['day_offset']})
      .toList();

  group('#31 사용자 변경 기록', () {
    test('미래 템플릿 알람을 지우면 같은 트랜잭션에서 skip 예외가 남는다(전날 알람의 배정일은 다음날)', () async {
      final id = await insertAlarm(date: '2026-09-17T23:00:00.000', type: 'fixed', offset: -1);
      await service.deleteAlarm(id);

      final rows = await db.query('alarm_overrides');
      expect(rows, hasLength(1));
      expect(rows.single['slot_time'], '2026-09-17T23:00:00');
      expect(rows.single['shift_type'], 'A');
      expect(rows.single['day_offset'], -1);
      expect(rows.single['action'], 'skip');
      expect(rows.single['alarm_type_id'], isNull);
      expect(rows.single['origin_date'], '2026-09-18');
      expect(rows.single['origin_shift'], 'A');
      expect(await db.query('alarms'), isEmpty);
      expect((await db.query('alarm_history')).single['dismiss_type'], 'cancelled_before_ring');
    });

    test('custom 알람·이미 지난 알람을 지우면 예외를 남기지 않는다', () async {
      final custom = await insertAlarm(date: '2026-09-17T07:00:00.000', type: 'custom', shift: null);
      final past = await insertAlarm(date: '2026-09-14T09:00:00.000', type: 'fixed');
      await service.deleteAlarm(custom);
      await service.deleteAlarm(past);
      expect(await db.query('alarm_overrides'), isEmpty);
    });

    test('타입 변경은 set_type 예외로 남고 같은 슬롯을 다시 바꾸면 교체된다', () async {
      final id = await insertAlarm(date: '2026-09-19T01:00:00.000', type: 'fixed', offset: 1);
      await service.updateAlarmTypeWithOverride(id, 2);
      await service.updateAlarmTypeWithOverride(id, 3);

      final rows = await db.query('alarm_overrides');
      expect(rows, hasLength(1));
      expect(rows.single['action'], 'set_type');
      expect(rows.single['alarm_type_id'], 3);
      expect(rows.single['origin_date'], '2026-09-18');
      expect((await db.query('alarms')).single['alarm_type_id'], 3);
    });
  });

  group('D12 원본 변경 시 예외 정리', () {
    test('D12_ASSIGNMENT_CHANGE - 근무가 바뀐 배정일에서 나온 예외만 삭제', () async {
      final c = caseOf('D12_ASSIGNMENT_CHANGE');
      final saved = await saveIrregular({'2026-09-18': 'A', '2026-09-19': 'A'});
      await seedOverrides(c['overrides_before'] as List);

      await service.updateShiftSchedule(ShiftSchedule(
          id: saved.id, isRegular: false, shiftTypes: saved.shiftTypes, assignedDates: {'2026-09-18': 'B', '2026-09-19': 'A'}));

      expect(await overrideIds(), (c['expected'] as Map)['remaining_override_ids']);
      expect((await service.getShiftSchedule())!.assignedDates, (c['expected'] as Map)['assigned_dates']);
    });

    test('D12_ASSIGNMENT_ABA - 되돌려도 삭제된 예외가 부활하지 않는다', () async {
      final c = caseOf('D12_ASSIGNMENT_ABA');
      final saved = await saveIrregular({'2026-09-18': 'A'});
      await seedOverrides(c['overrides_before'] as List);

      await service.updateShiftSchedule(ShiftSchedule(id: saved.id, isRegular: false, shiftTypes: saved.shiftTypes, assignedDates: {'2026-09-18': 'B'}));
      expect(await overrideIds(), (c['expected_after_first_operation'] as Map)['override_ids']);
      await service.updateShiftSchedule(ShiftSchedule(id: saved.id, isRegular: false, shiftTypes: saved.shiftTypes, assignedDates: {'2026-09-18': 'A'}));
      expect(await overrideIds(), (c['expected_after_second_operation'] as Map)['override_ids']);
    });

    test('근무가 안 바뀐 근무표 저장(색상 등)은 예외를 지우지 않는다', () async {
      final saved = await saveIrregular({'2026-09-18': 'A'});
      await seedOverrides((caseOf('D12_ASSIGNMENT_ABA')['overrides_before'] as List));
      await service.updateShiftSchedule(ShiftSchedule(
          id: saved.id, isRegular: false, shiftTypes: saved.shiftTypes, assignedDates: {'2026-09-18': 'A'}, customShiftColors: {'A': 1}));
      expect(await overrideIds(), [901]);
    });

    test('D12_TEMPLATE_CHANGE - 템플릿이 바뀐 근무의 미래 예외만 삭제(과거·다른 근무 보존)', () async {
      final c = caseOf('D12_TEMPLATE_CHANGE');
      await seedTemplatesDirect(c['templates_before'] as List);
      await seedOverrides(c['overrides_before'] as List);

      await service.replaceAllAlarmTemplates(templateMaps(c['templates_after'] as List));

      expect(await overrideIds(), (c['expected'] as Map)['remaining_override_ids']);
    });

    test('D12_TEMPLATE_ABA - 템플릿을 원래대로 되돌려도 예외가 부활하지 않는다', () async {
      final c = caseOf('D12_TEMPLATE_ABA');
      await seedTemplatesDirect([
        {'shift_type': 'A', 'time': '06:00', 'alarm_type_id': 1, 'day_offset': 0}
      ]);
      await seedOverrides(c['overrides_before'] as List);

      await service.replaceAllAlarmTemplates([{'shift_type': 'A', 'time': '06:30', 'alarm_type_id': 1, 'day_offset': 0}]);
      expect(await overrideIds(), (c['expected_after_first_operation'] as Map)['override_ids']);
      await service.replaceAllAlarmTemplates([{'shift_type': 'A', 'time': '06:00', 'alarm_type_id': 1, 'day_offset': 0}]);
      expect(await overrideIds(), (c['expected_after_second_operation'] as Map)['override_ids']);
    });

    test('템플릿 저장이 중간에 실패하면 예외 삭제도 함께 롤백된다(원자성)', () async {
      final c = caseOf('D12_TEMPLATE_CHANGE');
      await seedTemplatesDirect(c['templates_before'] as List);
      await seedOverrides(c['overrides_before'] as List);

      await expectLater(
        service.replaceAllAlarmTemplates([
          {'shift_type': 'A', 'time': '06:30', 'alarm_type_id': 1, 'day_offset': 0},
          {'shift_type': 'B', 'time': '07:00', 'alarm_type_id': 1, 'day_offset': 0, 'no_such_column': 1},  // 실패 주입
        ]),
        throwsA(anything),
      );
      expect(await overrideIds(), [701, 702, 703]);
      expect((await db.query('shift_alarm_templates')).length, 2);
      expect((await db.query('shift_alarm_templates', where: 'shift_type = ?', whereArgs: ['A'])).single['time'], '06:00');
    });

    test('D12_SHIFT_RENAME - 근무명 변경은 예외의 shift_type·origin_shift를 같은 트랜잭션에서 바꾼다', () async {
      final c = caseOf('D12_SHIFT_RENAME');
      final saved = await saveIrregular({}, shifts: const ['A', 'B']);
      await seedOverrides(c['overrides_before'] as List);

      await service.renameShiftAtomic(
        renamedShifts: {'A': 'A2'},
        newSchedule: ShiftSchedule(id: saved.id, isRegular: false, shiftTypes: const ['A2', 'B'], assignedDates: const {}),
      );

      final actual = (await db.query('alarm_overrides', orderBy: 'id'))
          .map((r) => [r['id'], r['shift_type'], r['origin_shift'], r['action'], r['alarm_type_id']])
          .toList();
      final expected = (c['expected_overrides'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => [o['id'], o['shift_type'], o['origin_shift'], o['action'], o['alarm_type_id']])
          .toList();
      expect(actual, expected);
    });
  });

  test('changedTemplateShifts - 시각·타입·오프셋 중 하나라도 바뀐 근무만', () {
    expect(
      DatabaseService.changedTemplateShifts(
        [
          {'shift_type': 'A', 'time': '06:00', 'alarm_type_id': 1, 'day_offset': 0},
          {'shift_type': 'B', 'time': '07:00', 'alarm_type_id': 1, 'day_offset': 0},
          {'shift_type': 'C', 'time': '08:00', 'alarm_type_id': 1, 'day_offset': 0},
        ],
        [
          {'shift_type': 'A', 'time': '06:00', 'alarm_type_id': 2, 'day_offset': 0},
          {'shift_type': 'B', 'time': '07:00', 'alarm_type_id': 1, 'day_offset': 0},
          {'shift_type': 'D', 'time': '09:00', 'alarm_type_id': 1, 'day_offset': 0},
        ],
      ),
      {'A', 'C', 'D'},
    );
  });
}
