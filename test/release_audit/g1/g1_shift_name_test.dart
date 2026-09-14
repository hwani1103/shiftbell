// 출시전 감사 G1 #11 / #12 / #28 (docs/release_audit/g1/handoff.md)
//  - #11 근무명 입력 검증(쉼표·예약어·빈 이름·길이·중복), 저장된 값은 D6 로그용 탐지만
//  - #12 근무명 맞바꾸기·순환 rename이 참조를 섞지 않음(2단계), 형식 오류·최종 중복 거부, 중간 실패 롤백
//  - #28 출퇴근 시각·근로시간 한 트랜잭션 저장(DB 최신 맵의 해당 키만), 되돌리기, 실패 롤백
// 실제 SQLite(sqflite_common_ffi) 위에서 제품 DatabaseService를 그대로 사용. 화면 안내 문구는 E/D S8.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#11 validateShiftName', () {
    test('정상 이름', () => expect(validateShiftName('주간', otherNames: ['야간']), isNull));
    test('빈 이름', () => expect(validateShiftName('   '), ShiftNameIssue.empty));
    test('길이 초과', () => expect(validateShiftName('12345678901'), ShiftNameIssue.tooLong));
    test('쉼표', () => expect(validateShiftName('주,간'), ShiftNameIssue.comma));
    test('예약어 미설정', () => expect(validateShiftName('미설정'), ShiftNameIssue.reserved));
    test('예약어 없음', () => expect(validateShiftName(' 없음 '), ShiftNameIssue.reserved));
    test('중복', () => expect(validateShiftName('야간', otherNames: ['주간', '야간']), ShiftNameIssue.duplicate));
  });

  group('#11 D6 invalidStoredShiftNames', () {
    test('정상 근무표는 비어 있음', () {
      expect(invalidStoredShiftNames(ShiftSchedule(isRegular: true, shiftTypes: ['주간', '야간'], pattern: ['주간', '야간'])), isEmpty);
    });
    test('예약어·중복·쉼표로 쪼개진 흔적을 찾되 데이터는 바꾸지 않음', () {
      final s = ShiftSchedule(isRegular: true, shiftTypes: ['미설정', '주간', '주간'], pattern: ['주간', 'A'], todayIndex: 0);
      final issues = invalidStoredShiftNames(s);
      expect(issues, hasLength(3));
      expect(s.shiftTypes, ['미설정', '주간', '주간']);
    });
  });

  late Directory dir;
  late Database db;
  final service = DatabaseService.instance;

  setUpAll(() async {
    initFfi();
    dir = await Directory.systemTemp.createTemp('g1_shift_name_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await service.database;
  });

  tearDownAll(() async {
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  setUp(() async {
    await db.execute('DROP TRIGGER IF EXISTS g1_fail_schedule_update');
    for (final t in ['alarm_overrides', 'alarms', 'shift_alarm_templates', 'shift_schedule', 'alarm_history',
      'alarm_creation_log', 'condition_shift_times']) {
      await db.delete(t);
    }
  });

  Future<int> saveSchedule(List<String> shifts, {Map<String, int>? durations}) =>
      service.saveShiftSchedule(ShiftSchedule(isRegular: false, shiftTypes: shifts, assignedDates: const {}, shiftDurations: durations));

  /// 근무명마다 모든 참조 테이블에 표시용 행을 하나씩 넣음(값에 원래 근무명을 새겨 섞였는지 추적)
  Future<void> seedReferences(List<String> shifts) async {
    var slot = 10;
    for (final s in shifts) {
      await db.insert('alarms', {'time': '06:00', 'date': '2026-09-2${slot - 10}T06:00:00.000', 'type': 'fixed', 'alarm_type_id': 1, 'shift_type': s, 'day_offset': 0});
      await db.insert('shift_alarm_templates', {'shift_type': s, 'time': '06:0${slot - 10}', 'alarm_type_id': 1, 'day_offset': 0});
      await db.insert('alarm_history', {'alarm_id': slot, 'scheduled_time': 'orig=$s', 'scheduled_date': '2026-09-20T06:00:00.000',
        'actual_ring_time': '2026-09-20T06:00:00.000', 'dismiss_type': 'swiped', 'snooze_count': 0, 'shift_type': s,
        'created_at': 'x', 'day_offset': 0});
      await db.insert('alarm_creation_log', {'alarm_id': slot, 'scheduled_date': '2026-09-20T06:00:00.000', 'scheduled_time': 'orig=$s',
        'shift_type': s, 'alarm_type_id': 1, 'source': 'auto', 'created_at': 'x', 'day_offset': 0});
      await db.insert('condition_shift_times', {'shift_name': s, 'start_minutes': slot, 'end_minutes': slot + 100, 'updated_at': 'x'});
      // 같은 시각·오프셋의 예외를 근무마다 둠 - UNIQUE 슬롯 키가 근무명으로만 구분되는 상황
      await db.insert('alarm_overrides', {'slot_time': '2026-09-20T06:00:00', 'shift_type': s, 'day_offset': 0, 'action': 'skip',
        'alarm_type_id': null, 'origin_date': '2026-09-20', 'origin_shift': s, 'created_at': 'orig=$s'});
      slot++;
    }
  }

  /// 원래 근무명(orig) → 지금 붙어 있는 근무명, 테이블별
  Future<Map<String, Map<String, String>>> referenceMap(List<String> originals) async {
    final result = <String, Map<String, String>>{};
    Future<void> collect(String table, String sql) async {
      result[table] = {for (final r in await db.rawQuery(sql)) r['orig'] as String: r['name'] as String};
    }
    final idx = {for (var i = 0; i < originals.length; i++) '${10 + i}': originals[i]};
    final alarms = await db.rawQuery("SELECT substr(date, 10, 1) AS d, shift_type AS name FROM alarms");
    result['alarms'] = {for (final r in alarms) idx['1${r['d']}']!: r['name'] as String};
    final templates = await db.rawQuery("SELECT substr(time, 5, 1) AS d, shift_type AS name FROM shift_alarm_templates");
    result['shift_alarm_templates'] = {for (final r in templates) idx['1${r['d']}']!: r['name'] as String};
    await collect('alarm_history', "SELECT substr(scheduled_time, 6) AS orig, shift_type AS name FROM alarm_history");
    await collect('alarm_creation_log', "SELECT substr(scheduled_time, 6) AS orig, shift_type AS name FROM alarm_creation_log");
    final times = await db.rawQuery('SELECT start_minutes, shift_name AS name FROM condition_shift_times');
    result['condition_shift_times'] = {for (final r in times) idx['${r['start_minutes']}']!: r['name'] as String};
    await collect('alarm_overrides.shift_type', "SELECT substr(created_at, 6) AS orig, shift_type AS name FROM alarm_overrides");
    await collect('alarm_overrides.origin_shift', "SELECT substr(created_at, 6) AS orig, origin_shift AS name FROM alarm_overrides");
    return result;
  }

  Map<String, Map<String, String>> expectedMap(Map<String, String> origToName) => {
        for (final t in ['alarms', 'shift_alarm_templates', 'alarm_history', 'alarm_creation_log', 'condition_shift_times',
          'alarm_overrides.shift_type', 'alarm_overrides.origin_shift'])
          t: origToName,
      };

  group('#12 renameShiftAtomic', () {
    test('A↔B 맞바꾸기 - 모든 참조가 서로 섞이지 않고 이름만 바뀐다', () async {
      final id = await saveSchedule(['A', 'B', 'C']);
      await seedReferences(['A', 'B', 'C']);

      await service.renameShiftAtomic(
        renamedShifts: {'A': 'B', 'B': 'A'},
        newSchedule: ShiftSchedule(id: id, isRegular: false, shiftTypes: ['B', 'A', 'C'], assignedDates: const {}),
      );

      expect(await referenceMap(['A', 'B', 'C']), expectedMap({'A': 'B', 'B': 'A', 'C': 'C'}));
      expect((await service.getShiftSchedule())!.shiftTypes, ['B', 'A', 'C']);
    });

    test('A→B→C→A 순환', () async {
      final id = await saveSchedule(['A', 'B', 'C']);
      await seedReferences(['A', 'B', 'C']);

      await service.renameShiftAtomic(
        renamedShifts: {'A': 'B', 'B': 'C', 'C': 'A'},
        newSchedule: ShiftSchedule(id: id, isRegular: false, shiftTypes: ['B', 'C', 'A'], assignedDates: const {}),
      );

      expect(await referenceMap(['A', 'B', 'C']), expectedMap({'A': 'B', 'B': 'C', 'C': 'A'}));
    });

    test('변경 후 두 근무가 같은 이름이 되면 거부하고 아무것도 바꾸지 않는다', () async {
      final id = await saveSchedule(['A', 'B', 'C']);
      await seedReferences(['A', 'B', 'C']);
      final before = await referenceMap(['A', 'B', 'C']);

      await expectLater(
        service.renameShiftAtomic(
          renamedShifts: {'A': 'B'},
          newSchedule: ShiftSchedule(id: id, isRegular: false, shiftTypes: ['B', 'B', 'C'], assignedDates: const {}),
        ),
        throwsArgumentError,
      );
      expect(await referenceMap(['A', 'B', 'C']), before);
      expect((await service.getShiftSchedule())!.shiftTypes, ['A', 'B', 'C']);
    });

    test('새 이름에 쉼표·예약어가 있으면 거부한다', () async {
      final id = await saveSchedule(['A', 'B']);
      for (final bad in ['X,Y', '미설정']) {
        await expectLater(
          service.renameShiftAtomic(
            renamedShifts: {'A': bad},
            newSchedule: ShiftSchedule(id: id, isRegular: false, shiftTypes: [bad, 'B'], assignedDates: const {}),
          ),
          throwsArgumentError,
        );
      }
      expect((await service.getShiftSchedule())!.shiftTypes, ['A', 'B']);
    });

    test('트랜잭션 마지막 단계(근무표 행)에서 실패하면 앞선 참조 변경까지 모두 롤백된다', () async {
      final id = await saveSchedule(['A', 'B', 'C']);
      await seedReferences(['A', 'B', 'C']);
      final before = await referenceMap(['A', 'B', 'C']);
      await db.execute("CREATE TRIGGER g1_fail_schedule_update BEFORE UPDATE ON shift_schedule BEGIN SELECT RAISE(ABORT, 'injected'); END");

      await expectLater(
        service.renameShiftAtomic(
          renamedShifts: {'A': 'B', 'B': 'A'},
          newSchedule: ShiftSchedule(id: id, isRegular: false, shiftTypes: ['B', 'A', 'C'], assignedDates: const {}),
        ),
        throwsA(anything),
      );
      expect(await referenceMap(['A', 'B', 'C']), before);
    });
  });

  group('#28 saveShiftTimeRange', () {
    Future<Map<String, int>> durations() async => (await service.getShiftSchedule())!.shiftDurations ?? {};
    Future<Map<String, List<int>>> times() async => {
          for (final r in await db.query('condition_shift_times'))
            r['shift_name'] as String: [r['start_minutes'] as int, r['end_minutes'] as int],
        };

    test('두 근무를 연달아 저장해도 DB 최신 맵의 해당 키만 바뀐다(옛 스냅샷 덮어쓰기 없음)', () async {
      await saveSchedule(['A', 'B'], durations: {'A': 1, 'B': 2});

      final first = await service.saveShiftTimeRange('A', const ShiftTimeRange(shiftName: 'A', startMinutes: 540, endMinutes: 1080));
      final second = await service.saveShiftTimeRange('B', const ShiftTimeRange(shiftName: 'B', startMinutes: 1260, endMinutes: 420));

      expect(first!.shiftDurations, {'A': 540, 'B': 2});
      expect(second!.shiftDurations, {'A': 540, 'B': 600});
      expect(await durations(), {'A': 540, 'B': 600});
      expect(await times(), {'A': [540, 1080], 'B': [1260, 420]});
    });

    test('되돌리기는 시각을 지우고 근로시간을 0(설정 안 함)으로 - 다른 근무는 그대로', () async {
      await saveSchedule(['A', 'B']);
      await service.saveShiftTimeRange('A', const ShiftTimeRange(shiftName: 'A', startMinutes: 540, endMinutes: 1080));
      await service.saveShiftTimeRange('B', const ShiftTimeRange(shiftName: 'B', startMinutes: 600, endMinutes: 660));

      await service.saveShiftTimeRange('A', null);

      expect(await durations(), {'A': 0, 'B': 60});
      expect(await times(), {'B': [600, 660]});
    });

    test('근로시간 저장이 실패하면 출퇴근 시각 저장도 함께 롤백된다', () async {
      await saveSchedule(['A'], durations: {'A': 5});
      await db.execute("CREATE TRIGGER g1_fail_schedule_update BEFORE UPDATE ON shift_schedule BEGIN SELECT RAISE(ABORT, 'injected'); END");

      await expectLater(
        service.saveShiftTimeRange('A', const ShiftTimeRange(shiftName: 'A', startMinutes: 540, endMinutes: 1080)),
        throwsA(anything),
      );
      expect(await times(), isEmpty);
      await db.execute('DROP TRIGGER g1_fail_schedule_update');
      expect(await durations(), {'A': 5});
    });

    test('근무표가 없으면 아무것도 저장하지 않는다', () async {
      expect(await service.saveShiftTimeRange('A', const ShiftTimeRange(shiftName: 'A', startMinutes: 1, endMinutes: 2)), isNull);
      expect(await times(), isEmpty);
    });
  });
}
