// test/release_audit/g0/db_migration_dart_test.dart
//
// G0(T03) Dart 쪽 마이그레이션 검증 - 실제 SQLite(sqflite_common_ffi) + T01 역사 fixture 23개.
// 케이스 이름은 T01 expected.md 표(MIG-ALL, ROLLBACK, ...)를 따른다.
// ⚠️ openLikeProduct는 제품 _initDatabase의 openDatabase 옵션 복제본이다. 실제 DatabaseService 경로는
//    db_service_upgrade_v18_test.dart / db_service_upgrade_v12_test.dart가 확인한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/db_migration_runner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g0_constraint_checks.dart';
import 'g0_support.dart';

void main() {
  setUpAll(initFfi);

  late Directory tmp;
  late Map<String, dynamic> referenceSchema;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('g0_dart_mig_');
    referenceSchema = readJson('v24_oncreate_schema.json');
  });

  DbMigrationScript mutated(Map<String, dynamic> mutation) =>
      DbMigrationScript.parse(jsonEncode(applyMutation(loadRepoScriptJson(), mutation)));

  test('MIG-ALL + REOPEN: v1~v23 fixture를 v24로 올리면 기대 데이터·기준 구조와 같고, 다시 열어도 변화 0', () async {
    final script = loadRepoScript();
    final failures = <String>[];
    for (final fx in fixtureIndex()) {
      final dbName = fx['db'] as String;
      final path = await copyFixture(dbName, tmp);
      try {
        var db = await openLikeProduct(path, script);
        final version = await db.getVersion();
        final data = await dumpTables(db);
        final schema = await schemaSnapshot(db);
        await db.close();

        final problems = <String>[
          if (version != 24) 'user_version=$version',
          ...diffExpectedData(data, readJson('expected_v24/${fx['expected']}')),
          if (canonicalJson(schema) != canonicalJson(referenceSchema)) 'schema != v24_oncreate_schema.json: ${_schemaDiff(schema, referenceSchema)}',
        ];

        db = await openLikeProduct(path, script);
        if (canonicalJson(await dumpTables(db)) != canonicalJson(data)) problems.add('두 번째 open에서 데이터 변화');
        await expectAlarmOverridesConstraints(db);
        await db.close();

        if (problems.isNotEmpty) failures.add('$dbName (start v${fx['start_version']}):\n  ${problems.join('\n  ')}');
      } catch (e, st) {
        failures.add('$dbName: 예외 $e\n$st');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n\n'));
  });

  test('음성 대조: fixture가 23개이고, 비교기가 틀린 기대값·다른 구조를 실제로 잡아냄', () async {
    expect(fixtureIndex().length, 23);
    final path = await copyFixture('v18.db', tmp);
    final db = await openLikeProduct(path, loadRepoScript());
    final data = await dumpTables(db);
    final schema = await schemaSnapshot(db);
    await db.close();

    final wrong = readJson('expected_v24/v18.json');
    ((wrong['tables'] as Map<String, dynamic>)['alarm_types'] as List).first['volume'] = 0.99;
    expect(diffExpectedData(data, wrong), isNotEmpty, reason: '값 하나를 바꾼 기대값을 통과시키면 안 됨');

    final wrongFriends = readJson('expected_v24/v18.json');
    ((wrongFriends['tables'] as Map<String, dynamic>)['friends'] as List).removeLast();
    expect(diffExpectedData(data, wrongFriends), isNotEmpty, reason: '행 하나 누락을 통과시키면 안 됨');

    final v17 = await copyFixture('v17.db', tmp);
    final raw = await openRaw(v17);
    expect(canonicalJson(await schemaSnapshot(raw)), isNot(canonicalJson(schema)), reason: '구버전 구조를 v24와 같다고 보면 안 됨');
    await raw.close();
  });

  test('ROLLBACK: v12→v24 중 v20에서 SQL 실패 → 스키마·데이터·user_version 전부 시작 상태, 원인 제거 후 성공', () async {
    final path = await copyFixture('v12.db', tmp);
    var raw = await openRaw(path);
    final beforeSchema = canonicalJson(await schemaSnapshot(raw));
    final beforeData = canonicalJson(await dumpTables(raw));
    await raw.close();

    final broken = mutated({
      'migration_append': {'version': 20, 'sql': 'CREATE TABLE alarm_types(x INTEGER)'}
    });
    await expectLater(openLikeProduct(path, broken), throwsA(anything));

    raw = await openRaw(path);
    expect(await raw.getVersion(), 12);
    expect(canonicalJson(await schemaSnapshot(raw)), beforeSchema);
    expect(canonicalJson(await dumpTables(raw)), beforeData);
    await raw.close();

    final db = await openLikeProduct(path, loadRepoScript());
    expect(await db.getVersion(), 24);
    expect(diffExpectedData(await dumpTables(db), readJson('expected_v24/v12.json')), isEmpty);
    await db.close();
  });

  test('FRIEND-ROLLBACK: v16에서 v17 DROP·CREATE 직후 실패 → 옛 friends 스키마와 701 행 복원', () async {
    final path = await copyFixture('v16.db', tmp);
    final broken = mutated({
      'migration_insert_after': {'version': 17, 'index': 1, 'sql': 'CREATE TABLE friends(x INTEGER)'}
    });
    await expectLater(openLikeProduct(path, broken), throwsA(anything));

    final raw = await openRaw(path);
    expect(await raw.getVersion(), 16);
    final columns = (await raw.rawQuery('PRAGMA table_info(friends)')).map((c) => c['name']).toSet();
    expect(columns, contains('has_memos'));
    expect(columns, isNot(contains('owner_id')));
    final rows = await raw.rawQuery('SELECT id FROM friends');
    expect(rows.map((r) => r['id']).toList(), [701]);
    await raw.close();
  });

  test('MISSING-COLUMN: 버전만 24로 선행하고 컬럼·인덱스·테이블이 빠진 DB를 repair가 채우고 데이터 보존', () async {
    final path = await copyFixture('variant_v23_stamped24_missing.db', tmp);
    final db = await openLikeProduct(path, loadRepoScript());
    expect(await db.getVersion(), 24);
    expect(canonicalJson(await schemaSnapshot(db)), canonicalJson(referenceSchema));
    expect(diffExpectedData(await dumpTables(db), readJson('expected_v24/variant_v23_stamped24_missing.json')), isEmpty);
    await db.close();
  });

  test('ALTER-FAIL(repair): 누락 컬럼 ALTER가 실패하면 예외 전파, 같은 트랜잭션의 다른 복구도 롤백', () async {
    final path = await copyFixture('variant_v23_stamped24_missing.db', tmp);
    final broken = mutated({
      'replace_repair': {
        'from': 'ALTER TABLE date_schedules ADD COLUMN notify_offset_minutes INTEGER NOT NULL DEFAULT 0',
        'to': 'ALTER TABLE date_schedules ADD COLUMN notify_offset_minutes INTEGER NOT NULL',
      }
    });
    await expectLater(openLikeProduct(path, broken), throwsA(anything));

    final raw = await openRaw(path);
    final columns = (await raw.rawQuery('PRAGMA table_info(date_schedules)')).map((c) => c['name']).toSet();
    expect(columns, isNot(contains('notify_offset_minutes')));
    final overrides = await raw.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='alarm_overrides'");
    expect(overrides, isEmpty, reason: '실패한 repair 트랜잭션의 CREATE TABLE도 롤백돼야 함');
    await raw.close();
  });

  test('ALTER-FAIL(migration): 없는 테이블에 대한 ALTER는 건너뛰지 않고 실패', () async {
    final path = await copyFixture('v18.db', tmp);
    final broken = mutated({
      'migration_append': {'version': 19, 'sql': 'ALTER TABLE no_such_table ADD COLUMN day_offset INTEGER NOT NULL DEFAULT 0'}
    });
    await expectLater(openLikeProduct(path, broken), throwsA(anything));
    final raw = await openRaw(path);
    expect(await raw.getVersion(), 18);
    await raw.close();
  });

  test('FUTURE-VERSION: user_version 25 DB는 다운그레이드 거부, 버전·데이터 무변경', () async {
    final path = await copyFixture('variant_v23_stamped25.db', tmp);
    var raw = await openRaw(path);
    final before = canonicalJson(await dumpTables(raw));
    await raw.close();

    await expectLater(openLikeProduct(path, loadRepoScript()), throwsA(isA<DbMigrationException>()));

    raw = await openRaw(path);
    expect(await raw.getVersion(), 25);
    expect(canonicalJson(await dumpTables(raw)), before);
    await raw.close();
  });

  test('REPAIR-REJECT (현재 동작 기록): v17 전환 없이 24로 찍힌 옛 friends DB', () async {
    final path = await copyFixture('variant_v16_stamped24_oldfriends.db', tmp);
    Object? error;
    Database? db;
    try {
      db = await openLikeProduct(path, loadRepoScript());
    } catch (e) {
      error = e;
    }
    if (db != null) {
      final schema = await schemaSnapshot(db);
      final friendsColumns = (await db.rawQuery('PRAGMA table_info(friends)')).map((c) => c['name']).toSet();
      final rows = await db.rawQuery('SELECT id FROM friends');
      await db.close();
      // ignore: avoid_print
      print('REPAIR-REJECT 관찰: open 성공, schema==reference ${canonicalJson(schema) == canonicalJson(referenceSchema)}, '
          'friends 컬럼 $friendsColumns, 행 ${rows.map((r) => r['id']).toList()}');
      // 과거 DROP을 재실행해 정상처럼 숨기지 않았는지(701 보존)만 단정한다. 실패 전파 여부는 test_results에 판정.
      expect(rows.map((r) => r['id']).toList(), [701]);
      expect(friendsColumns, isNot(contains('owner_id')));
    } else {
      // ignore: avoid_print
      print('REPAIR-REJECT 관찰: open 실패 $error');
    }
  });

  group('파싱 규칙 케이스 (runner_rule_cases.json, Kotlin과 공유)', () {
    final cases = (readJson('runner_rule_cases.json')['cases'] as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      test('${c['name']} → ${c['expect']}', () {
        final json = jsonEncode(applyMutation(loadRepoScriptJson(), c['mutation'] as Map<String, dynamic>));
        if (c['expect'] == 'accept') {
          expect(() => DbMigrationScript.parse(json), returnsNormally);
        } else {
          expect(() => DbMigrationScript.parse(json), throwsA(isA<DbMigrationException>()));
        }
      });
    }
  });
}

String _schemaDiff(Map<String, Object?> actual, Map<String, dynamic> reference) {
  final out = <String>[];
  final names = {...actual.keys, ...reference.keys}.toList()..sort();
  for (final n in names) {
    final a = actual.containsKey(n) ? canonicalJson(actual[n]) : '(없음)';
    final r = reference.containsKey(n) ? canonicalJson(reference[n]) : '(없음)';
    if (a != r) out.add('$n\n    actual:    $a\n    reference: $r');
  }
  return out.join('\n  ');
}
