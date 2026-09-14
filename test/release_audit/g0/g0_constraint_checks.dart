// test/release_audit/g0/g0_constraint_checks.dart
//
// alarm_overrides(v24) 제약 동작 확인. PRAGMA로 보이지 않는 CHECK는 실제 INSERT로 검증.
// 슬롯 키 UNIQUE(slot_time, shift_type, day_offset)는 확정 계약(v4 #31)이고, CHECK 3종(day_offset 범위,
// action 값, action↔alarm_type_id 조합)은 G0가 추가한 제약이다(g0/handoff.md 잔여 위험 5).
// 호출한 DB에 행을 남기지 않도록 트랜잭션을 롤백한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Rollback implements Exception {}

Future<void> expectAlarmOverridesConstraints(Database db) async {
  Future<void> insert(Transaction txn, Map<String, Object?> overrides) {
    final row = <String, Object?>{
      'slot_time': '2026-09-15T06:30:00',
      'shift_type': 'Day',
      'day_offset': 0,
      'action': 'skip',
      'alarm_type_id': null,
      'origin_date': '2026-09-15',
      'origin_shift': 'Day',
      'created_at': '2026-09-14T05:00:00',
      ...overrides,
    };
    return txn.insert('alarm_overrides', row);
  }

  Future<bool> rejected(Transaction txn, Map<String, Object?> overrides) async {
    try {
      await txn.execute('SAVEPOINT g0_check');
      await insert(txn, overrides);
      await txn.execute('RELEASE g0_check');
      return false;
    } on DatabaseException {
      await txn.execute('ROLLBACK TO g0_check');
      await txn.execute('RELEASE g0_check');
      return true;
    }
  }

  try {
    await db.transaction((txn) async {
      await insert(txn, {});
      await insert(txn, {'slot_time': '2026-09-15T07:00:00', 'action': 'set_type', 'alarm_type_id': 2});
      await insert(txn, {'day_offset': -1});
      await insert(txn, {'day_offset': 1});

      expect(await rejected(txn, {}), isTrue, reason: '같은 슬롯 중복은 거부돼야 함');
      expect(await rejected(txn, {'slot_time': '2026-09-16T06:30:00', 'day_offset': 2}), isTrue,
          reason: 'day_offset 범위 밖');
      expect(await rejected(txn, {'slot_time': '2026-09-16T06:30:00', 'action': 'delete'}), isTrue,
          reason: 'action 허용 값 밖');
      expect(await rejected(txn, {'slot_time': '2026-09-16T06:30:00', 'alarm_type_id': 1}), isTrue,
          reason: 'skip인데 alarm_type_id 있음');
      expect(await rejected(txn, {'slot_time': '2026-09-16T06:30:00', 'action': 'set_type'}), isTrue,
          reason: 'set_type인데 alarm_type_id 없음');
      expect(await rejected(txn, {'slot_time': '2026-09-16T06:30:00', 'origin_shift': null}), isTrue,
          reason: 'origin_shift NOT NULL');
      expect(await rejected(txn, {'slot_time': '2026-09-15T06:30:00', 'shift_type': 'Night'}), isFalse,
          reason: '근무명이 다르면 다른 슬롯');
      throw _Rollback();
    });
  } on _Rollback {
    // 의도한 롤백 - 확인용 행을 남기지 않음
  }
  final left = await db.rawQuery('SELECT COUNT(*) AS n FROM alarm_overrides');
  expect(left.first['n'], 0, reason: '제약 확인용 행이 남으면 안 됨');
}
