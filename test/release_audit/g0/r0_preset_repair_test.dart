// test/release_audit/g0/r0_preset_repair_test.dart
//
// G0 R0-03 교차 리뷰 반영 확인 - 프리셋 알람 타입이 일부만 남은 DB를 열면 빠진 프리셋만 채우고,
// 남아 있는 프리셋의 사용자 설정값과 사용자 타입은 건드리지 않는다.
// (예전 구현은 프리셋이 하나라도 있으면 즉시 반환해서 1개만 남은 상태를 정상으로 통과시켰음)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);

  test('프리셋 2·3이 빠진 v23 DB → 업그레이드 후 2·3만 채움, 프리셋 1 사용자 값·사용자 타입 41 보존', () async {
    final dir = await Directory.systemTemp.createTemp('g0_r0_preset_');
    await databaseFactory.setDatabasesPath(dir.path);
    final path = await copyFixture('v23.db', dir, asName: 'shiftbell.db');

    final raw = await openRaw(path);
    final beforePreset1 = (await raw.rawQuery('SELECT * FROM alarm_types WHERE id = 1')).single;
    final beforeCustom = (await raw.rawQuery('SELECT * FROM alarm_types WHERE id = 41')).single;
    await raw.delete('alarm_types', where: 'id IN (2, 3)');
    await raw.close();

    final db = await DatabaseService.instance.database;
    final ids = (await db.rawQuery('SELECT id FROM alarm_types ORDER BY id')).map((r) => r['id']).toList();
    expect(ids, [1, 2, 3, 41], reason: '빠진 프리셋 2·3이 채워져야 함');

    expect(canonicalJson((await db.rawQuery('SELECT * FROM alarm_types WHERE id = 1')).single), canonicalJson(beforePreset1),
        reason: '남아 있던 프리셋의 사용자 설정값을 덮어쓰면 안 됨');
    expect(canonicalJson((await db.rawQuery('SELECT * FROM alarm_types WHERE id = 41')).single), canonicalJson(beforeCustom));
    final presets = await db.rawQuery('SELECT id, is_preset FROM alarm_types WHERE id IN (2, 3) ORDER BY id');
    expect(presets.every((r) => r['is_preset'] == 1), isTrue);
  });
}
