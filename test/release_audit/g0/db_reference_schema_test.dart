// test/release_audit/g0/db_reference_schema_test.dart
//
// G0(T03) - 실제 DatabaseService 신규 설치(_onCreate)로 만든 v24 DB의 구조를 기준 스냅샷으로 고정한다.
// Kotlin/Dart 마이그레이션 결과는 모두 이 스냅샷(v24_oncreate_schema.json)과 비교한다.
// 스냅샷 갱신: G0_UPDATE_SNAPSHOT=1 flutter test test/release_audit/g0/db_reference_schema_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g0_support.dart';
import 'g0_constraint_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);

  test('신규 설치 v24 구조 = 기준 스냅샷, 프리셋 3종, alarm_overrides 제약', () async {
    final dir = await Directory.systemTemp.createTemp('g0_reference_');
    await databaseFactory.setDatabasesPath(dir.path);

    // 제품 경로: MethodChannel이 없는 테스트 환경이라 Device Protected 경로 조회는 실패하고
    // getDatabasesPath() 폴백 경로(= 위 임시 폴더)에 신규 생성됨.
    final db = await DatabaseService.instance.database;
    expect(await db.getVersion(), 24);

    final snapshot = await schemaSnapshot(db);
    final file = g0File('v24_oncreate_schema.json');
    if (Platform.environment['G0_UPDATE_SNAPSHOT'] == '1') {
      file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(jsonDecode(canonicalJson(snapshot))));
    }
    expect(file.existsSync(), isTrue, reason: '기준 스냅샷 없음 - G0_UPDATE_SNAPSHOT=1로 먼저 생성');
    expect(canonicalJson(snapshot), canonicalJson(jsonDecode(file.readAsStringSync())),
        reason: '_onCreate 구조가 기준 스냅샷과 다름');

    expect(snapshot.keys.toSet(), containsAll(<String>['alarm_overrides', 'alarm_history', 'alarm_creation_log']));

    final presets = await db.rawQuery('SELECT id FROM alarm_types WHERE is_preset = 1 ORDER BY id');
    expect(presets.map((r) => r['id']).toList(), [1, 2, 3]);

    await expectAlarmOverridesConstraints(db);
  });
}
