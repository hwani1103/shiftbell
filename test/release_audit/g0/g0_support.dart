// test/release_audit/g0/g0_support.dart
//
// G0(T03) DB 테스트 공통 도구. 실제 SQLite(sqflite_common_ffi)로 실행한다 - mock 성공 반환으로
// 통과시키지 않기 위함. Kotlin 쪽 쌍: android/app/src/test/.../G0TestSupport.kt (같은 정규화 규칙).
//
// fixture/기대값은 tool/g0/build_fixtures.py가 T01 원본으로 만든다(구현 파일을 읽지 않음).
import 'dart:convert';
import 'dart:io';

import 'package:shiftbell/services/db_migration_runner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Directory g0Dir = Directory('test/release_audit/g0');

File g0File(String relative) => File('${g0Dir.path}/$relative');

void initFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 저장소의 실제 SQL 원본을 파싱 (앱이 번들에서 읽는 것과 같은 파일).
DbMigrationScript loadRepoScript() =>
    DbMigrationScript.parse(File('assets/db/migrations.json').readAsStringSync());

Map<String, dynamic> loadRepoScriptJson() =>
    jsonDecode(File('assets/db/migrations.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> readJson(String relative) =>
    jsonDecode(g0File(relative).readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> fixtureIndex() => (readJson('fixtures_index.json')['fixtures'] as List)
    .cast<Map<String, dynamic>>();

/// fixture DB를 임시 폴더로 복사한 경로. 기준 파일은 절대 직접 열지 않음.
Future<String> copyFixture(String dbName, Directory dir, {String? asName}) async {
  final target = File('${dir.path}/${asName ?? dbName}');
  await g0File('fixtures_db/$dbName').copy(target.path);
  return target.path;
}

const _excludedTables = {'android_metadata'};

/// 구조 비교용 스냅샷: 테이블별 컬럼(이름/타입/NOT NULL/기본값/PK), 인덱스(UNIQUE/생성원인/부분/컬럼 순서),
/// FK. 생성 순서·SQL 공백·자동 인덱스 이름·sqlite_sequence는 비교하지 않음(T01 expected.md 구조 대조).
Future<Map<String, Object?>> schemaSnapshot(DatabaseExecutor db) async {
  final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  final result = <String, Object?>{};
  for (final t in tables) {
    final name = t['name'] as String;
    if (_excludedTables.contains(name)) continue;
    final columns = (await db.rawQuery('PRAGMA table_info($name)'))
        .map((c) => <String, Object?>{
              'name': c['name'],
              'type': (c['type'] as String).toUpperCase(),
              'notnull': c['notnull'],
              'dflt': c['dflt_value'],
              'pk': c['pk'],
            })
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    final indexes = <Map<String, Object?>>[];
    for (final i in await db.rawQuery('PRAGMA index_list($name)')) {
      final indexName = i['name'] as String;
      final info = (await db.rawQuery('PRAGMA index_info("$indexName")')).toList()
        ..sort((a, b) => (a['seqno'] as int).compareTo(b['seqno'] as int));
      indexes.add({
        'unique': i['unique'],
        'origin': i['origin'],
        'partial': i['partial'],
        'columns': info.map((c) => c['name']).toList(),
      });
    }
    indexes.sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
    final fks = (await db.rawQuery('PRAGMA foreign_key_list($name)'))
        .map((f) => <String, Object?>{'table': f['table'], 'from': f['from'], 'to': f['to']})
        .toList()
      ..sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
    result[name] = {'columns': columns, 'indexes': indexes, 'foreign_keys': fks};
  }
  return result;
}

/// 테이블 전체 행 (sqlite_sequence/android_metadata 제외), 행 순서는 정규화 문자열로 정렬.
Future<Map<String, List<Object?>>> dumpTables(DatabaseExecutor db) async {
  final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  final result = <String, List<Object?>>{};
  for (final t in tables) {
    final name = t['name'] as String;
    if (_excludedTables.contains(name)) continue;
    final rows = (await db.rawQuery('SELECT * FROM $name')).map((r) => Map<String, Object?>.from(r)).toList();
    rows.sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
    result[name] = rows;
  }
  return result;
}

/// 키 정렬 + 숫자 정규화(정수값 실수는 정수 표기) JSON. Kotlin G0TestSupport.canonical과 같은 규칙.
String canonicalJson(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) {
    if (value is double && value == value.truncateToDouble() && value.isFinite) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  if (value is String) return jsonEncode(value);
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(value[k])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(canonicalJson).join(',')}]';
  }
  throw ArgumentError('정규화할 수 없는 값: $value (${value.runtimeType})');
}

/// 기대 데이터(expected_v24/*.json)와 실제 DB의 테이블별 불일치 목록. 비어 있으면 일치.
List<String> diffExpectedData(Map<String, List<Object?>> actual, Map<String, dynamic> expected) {
  final problems = <String>[];
  final expTables = (expected['tables'] as Map<String, dynamic>);
  for (final table in expTables.keys) {
    final exp = (expTables[table] as List).map(canonicalJson).toList()..sort();
    final act = (actual[table] ?? const []).map(canonicalJson).toList()..sort();
    if (exp.join('\n') != act.join('\n')) {
      problems.add('$table\n  expected: ${exp.join(' | ')}\n  actual:   ${act.join(' | ')}');
    }
  }
  for (final table in actual.keys) {
    if (!expTables.containsKey(table) && table != 'sqlite_sequence') {
      problems.add('기대 데이터에 없는 테이블: $table');
    }
  }
  return problems;
}

/// 제품 _initDatabase와 같은 openDatabase 옵션(onCreate 제외 - fixture는 항상 기존 DB).
/// ⚠️ 복제본: 실제 DatabaseService 경로는 db_service_upgrade_v*_test.dart가 따로 확인함.
/// 제품 onOpen의 "프리셋 알람 타입이 비었으면 재삽입"은 fixture에 프리셋이 있어 생략.
Future<Database> openLikeProduct(String path, DbMigrationScript script) {
  return openDatabase(
    path,
    version: 24,
    singleInstance: false,
    onCreate: (db, version) async => throw StateError('fixture는 onCreate에 도달하면 안 됨'),
    onUpgrade: (db, oldVersion, newVersion) => DbMigrationRunner.migrate(db, script, oldVersion, newVersion),
    onDowngrade: (db, oldVersion, newVersion) async {
      throw DbMigrationException('DB 다운그레이드 금지: disk v$oldVersion > app v$newVersion');
    },
    onOpen: (db) async => DbMigrationRunner.repair(db, script),
  );
}

/// 버전 확인·마이그레이션 없이 연다(롤백 결과 확인용).
Future<Database> openRaw(String path) => openDatabase(path, singleInstance: false);

/// 규칙 케이스(runner_rule_cases.json)의 변형을 SQL 원본 JSON에 적용. Kotlin 쪽과 같은 연산.
Map<String, dynamic> applyMutation(Map<String, dynamic> script, Map<String, dynamic> mutation) {
  final copy = jsonDecode(jsonEncode(script)) as Map<String, dynamic>;
  final repair = copy['repair'] as List;
  final migrations = copy['migrations'] as List;
  mutation.forEach((op, arg) {
    switch (op) {
      case 'repair_append':
        repair.add(arg);
      case 'migration_append':
        final m = arg as Map<String, dynamic>;
        final entry = migrations.cast<Map<String, dynamic>>().firstWhere((e) => e['version'] == m['version']);
        (entry['sql'] as List).add(m['sql']);
      case 'migration_insert_after':
        final m = arg as Map<String, dynamic>;
        final entry = migrations.cast<Map<String, dynamic>>().firstWhere((e) => e['version'] == m['version']);
        (entry['sql'] as List).insert((m['index'] as int) + 1, m['sql']);
      case 'remove_migration_version':
        migrations.removeWhere((e) => (e as Map)['version'] == arg);
      case 'duplicate_migration_version':
        migrations.add(jsonDecode(jsonEncode(migrations.firstWhere((e) => (e as Map)['version'] == arg))));
      case 'set_target_version':
        copy['targetVersion'] = arg;
      case 'set_format':
        copy['format'] = arg;
      case 'replace_repair':
        final m = arg as Map<String, dynamic>;
        final i = repair.indexOf(m['from']);
        if (i < 0) throw StateError('replace_repair 대상 없음: ${m['from']}');
        repair[i] = m['to'];
      default:
        throw StateError('알 수 없는 변형: $op');
    }
  });
  return copy;
}
