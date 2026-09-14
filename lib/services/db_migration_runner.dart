// lib/services/db_migration_runner.dart
//
// ⭐ 2026-09-14 (G0) - DB 스키마 SQL 단일 원본(assets/db/migrations.json) 실행기.
// 출시전_코드감사_검토결과_v4 #1(업데이트 후 앱을 열기 전에도 Native가 같은 SQL로
// 마이그레이션) / #8(마이그레이션 실패를 삼키지 않음) / #31(v24 alarm_overrides).
//
// 예전엔 버전별 SQL이 database_service.dart의 _onUpgrade에만 있었고 Native는 "Flutter가
// 먼저 올려줄 때까지" DB를 못 썼음 - 그래서 업데이트 후 앱을 안 열면(또는 잠금 해제 전
// 재부팅) 알람 설정/스누즈/이력을 못 읽었음. 이제 두 언어가 이 파일 하나를 같은 규칙으로
// 실행하므로 어느 쪽이 먼저 열어도 결과가 같다.
//
// ⚠️ Kotlin 쌍: android/app/src/main/kotlin/com/hwani1103/shiftbell/DbMigrationRunner.kt
// 파싱 규칙·실행 규칙(한 항목 = SQL 한 문장, ALTER ADD COLUMN 존재 확인, repair 화이트리스트,
// repair의 CREATE TABLE 선행)을 두 언어가 똑같이 유지해야 함. 바꾸면 같은 커밋에서 양쪽을
// 바꾸고 같은 fixture로 비교할 것.

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:sqflite/sqflite.dart';

const String kDbMigrationAssetPath = 'assets/db/migrations.json';

class DbMigrationException implements Exception {
  DbMigrationException(this.message);

  final String message;

  @override
  String toString() => 'DbMigrationException: $message';
}

final RegExp _alterAddColumn = RegExp(
  r'^ALTER\s+TABLE\s+(\w+)\s+ADD\s+COLUMN\s+(\w+)\b',
  caseSensitive: false,
);
final RegExp _createTable = RegExp(
  r'^CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)\s*\(',
  caseSensitive: false,
);
final RegExp _createIndex = RegExp(
  r'^CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS\s+(\w+)\s+ON\s+(\w+)\s*\(',
  caseSensitive: false,
);

class DbMigrationScript {
  DbMigrationScript._(this.targetVersion, this.migrations, this.repair);

  final int targetVersion;

  /// 버전 → 그 버전으로 올릴 때 실행할 SQL(순서대로). 2..targetVersion 전 구간이 반드시 있음.
  final Map<int, List<String>> migrations;

  /// 현재 스키마의 최종 형태 중 비파괴 SQL만 (CREATE TABLE이 항상 먼저).
  final List<String> repair;

  static Future<DbMigrationScript> loadFromAssets([AssetBundle? bundle]) async {
    final text = await (bundle ?? rootBundle).loadString(kDbMigrationAssetPath, cache: false);
    return parse(text);
  }

  static DbMigrationScript parse(String jsonText) {
    final Object? root;
    try {
      root = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw DbMigrationException('JSON 파싱 실패: ${e.message}');
    }
    if (root is! Map<String, dynamic>) {
      throw DbMigrationException('최상위가 객체가 아님');
    }
    if (root['format'] != 1) {
      throw DbMigrationException('지원하지 않는 format: ${root['format']}');
    }
    final target = root['targetVersion'];
    if (target is! int || target < 2) {
      throw DbMigrationException('targetVersion이 2 이상의 정수가 아님: $target');
    }

    final rawMigrations = root['migrations'];
    if (rawMigrations is! List) {
      throw DbMigrationException('migrations가 배열이 아님');
    }
    final migrations = <int, List<String>>{};
    for (final entry in rawMigrations) {
      if (entry is! Map<String, dynamic>) {
        throw DbMigrationException('migrations 항목이 객체가 아님: $entry');
      }
      final version = entry['version'];
      if (version is! int || version < 2 || version > target) {
        throw DbMigrationException('migrations 항목 version이 2..$target 범위 정수가 아님: $version');
      }
      if (migrations.containsKey(version)) {
        throw DbMigrationException('migrations에 v$version이 중복됨');
      }
      final sql = entry['sql'];
      if (sql is! List || sql.isEmpty) {
        throw DbMigrationException('v$version의 sql이 비어 있음');
      }
      migrations[version] = List<String>.unmodifiable(
        sql.map((s) => _singleStatement(s, 'v$version')),
      );
    }
    for (var v = 2; v <= target; v++) {
      if (!migrations.containsKey(v)) {
        throw DbMigrationException('migrations에 v$v가 없음 (v2..v$target 전 구간이 필요)');
      }
    }

    final rawRepair = root['repair'];
    if (rawRepair is! List) {
      throw DbMigrationException('repair가 배열이 아님');
    }
    final repair = List<String>.unmodifiable(
      rawRepair.map((s) => _singleStatement(s, 'repair')),
    );
    _validateRepair(repair);

    return DbMigrationScript._(target, Map.unmodifiable(migrations), repair);
  }

  static String _singleStatement(Object? value, String where) {
    if (value is! String) {
      throw DbMigrationException('$where: SQL이 문자열이 아님: $value');
    }
    final sql = value.trim();
    if (sql.isEmpty) {
      throw DbMigrationException('$where: 빈 SQL');
    }
    // Android SQLiteDatabase.execSQL은 여러 문장 중 첫 문장만 실행하고 나머지를 조용히
    // 버림 - 두 언어 결과가 달라지지 않게 한 항목에 한 문장만 허용.
    if (sql.contains(';')) {
      throw DbMigrationException('$where: 한 항목에 SQL 한 문장만 허용(; 금지): $sql');
    }
    return sql;
  }

  static void _validateRepair(List<String> repair) {
    final createdTables = <String>{};
    var seenNonCreateTable = false;
    for (final sql in repair) {
      final table = _createTable.firstMatch(sql);
      if (table != null) {
        if (seenNonCreateTable) {
          throw DbMigrationException('repair: CREATE TABLE은 인덱스/ALTER보다 앞에 있어야 함: $sql');
        }
        createdTables.add(table.group(1)!.toLowerCase());
        continue;
      }
      final alter = _alterAddColumn.firstMatch(sql);
      final index = _createIndex.firstMatch(sql);
      final targetTable = alter?.group(1) ?? index?.group(2);
      if (targetTable == null) {
        throw DbMigrationException(
            'repair에 허용되지 않은 SQL(CREATE TABLE/INDEX IF NOT EXISTS, ALTER TABLE ADD COLUMN만 허용): $sql');
      }
      seenNonCreateTable = true;
      if (!createdTables.contains(targetTable.toLowerCase())) {
        throw DbMigrationException('repair: 대상 테이블($targetTable)의 최종 형태 CREATE TABLE이 repair에 없음: $sql');
      }
    }
  }
}

class DbMigrationRunner {
  DbMigrationRunner._();

  /// [fromVersion] 다음 버전부터 [toVersion]까지 전부 순서대로 실행. 실패는 그대로 던짐 -
  /// 호출자(sqflite onUpgrade / SQLiteOpenHelper.onUpgrade)의 트랜잭션이 버전 갱신까지
  /// 함께 롤백하므로 다음 실행 때 같은 구간을 다시 시도하게 됨.
  static Future<void> migrate(
    DatabaseExecutor db,
    DbMigrationScript script,
    int fromVersion,
    int toVersion,
  ) async {
    if (toVersion != script.targetVersion) {
      throw DbMigrationException('목표 버전(v$toVersion)이 SQL 원본 targetVersion(v${script.targetVersion})과 다름');
    }
    if (fromVersion < 1 || fromVersion >= toVersion) {
      throw DbMigrationException('지원하지 않는 업그레이드 구간: v$fromVersion → v$toVersion');
    }
    for (var v = fromVersion + 1; v <= toVersion; v++) {
      for (final sql in script.migrations[v]!) {
        final alter = _alterAddColumn.firstMatch(sql);
        if (alter != null && await _columnExists(db, alter.group(1)!, alter.group(2)!)) {
          continue;
        }
        await db.execute(sql);
      }
      print('✅ DB 업그레이드 v${v - 1} → v$v');
    }
  }

  /// 지금 DB에 없는 repair 항목만 (읽기만 함).
  static Future<List<String>> pendingRepairs(DatabaseExecutor db, DbMigrationScript script) async {
    final pending = <String>[];
    for (final sql in script.repair) {
      final table = _createTable.firstMatch(sql);
      if (table != null) {
        if (!await _schemaObjectExists(db, 'table', table.group(1)!)) pending.add(sql);
        continue;
      }
      final index = _createIndex.firstMatch(sql);
      if (index != null) {
        if (!await _schemaObjectExists(db, 'index', index.group(1)!)) pending.add(sql);
        continue;
      }
      final alter = _alterAddColumn.firstMatch(sql);
      if (alter != null) {
        final tableName = alter.group(1)!;
        // 테이블 자체가 없으면 앞의 CREATE TABLE(최종 형태)이 이 컬럼까지 만들어 줌.
        if (await _schemaObjectExists(db, 'table', tableName) &&
            !await _columnExists(db, tableName, alter.group(2)!)) {
          pending.add(sql);
        }
        continue;
      }
      throw DbMigrationException('repair에 허용되지 않은 SQL: $sql');
    }
    return pending;
  }

  /// 버전은 최신인데 테이블/컬럼/인덱스가 빠진 DB를 비파괴로 채움. 과거 마이그레이션은
  /// 절대 다시 실행하지 않음(v17 DROP TABLE friends, v8~v11 UPDATE 재실행 방지).
  static Future<void> repair(Database db, DbMigrationScript script) async {
    if ((await pendingRepairs(db, script)).isEmpty) return;
    await db.transaction((txn) async {
      // 쓰기 잠금을 잡은 뒤 다시 계산 - 그사이 Native가 먼저 채웠을 수 있음.
      final pending = await pendingRepairs(txn, script);
      for (final sql in pending) {
        await txn.execute(sql);
      }
      print('🛠️ DB 스키마 복구 ${pending.length}건 실행');
    });
  }

  static Future<bool> _schemaObjectExists(DatabaseExecutor db, String type, String name) async {
    final rows = await db.rawQuery(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND lower(name) = lower(?)',
      [type, name],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _columnExists(DatabaseExecutor db, String table, String column) async {
    // table은 정규식 \w+로만 뽑힌 이름이라 그대로 넣어도 안전.
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final wanted = column.toLowerCase();
    return rows.any((row) => (row['name'] as String?)?.toLowerCase() == wanted);
  }
}
