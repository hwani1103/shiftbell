// lib/services/backup_service.dart
//
// ⭐ 사용자 데이터 백업/복구 - 전체 설계는 백업복구_설계.md 참고.
//
// ⚠️⚠️ 반드시 지킬 것: 이 파일과 이 파일이 쓰는 코드는 알람 데이터/근무명
// 데이터/근무패턴 데이터, 그리고 알람 갱신·발생·notification 로직을
// **절대 건드리지 않는다**. 여기서 하는 일은 딱 두 가지뿐이다.
//   1) (백업) DB의 테이블들과 SharedPreferences를 "읽기만" 해서 JSON으로 옮겨 담기
//   2) (복구) 완전히 새로 설치된 상태(=shift_schedule이 비어있는 상태)에서만,
//      그 원본 데이터 테이블들에 다시 "써넣기"
//
// alarms 테이블(현재 등록된 실제 알람)은 의도적으로 백업 대상에서 제외한다 -
// shift_schedule + shift_alarm_templates(원본 데이터)로부터 AlarmRefreshEngine.kt
// / alarm_generation_service.dart가 이미 자동으로 재생성하므로, 복구 후 앱이
// 평소처럼 시작되면(CLAUDE.md "알람 갱신 트리거 지점 4. 앱 실행") 알아서 다시
// 채워진다. 이 서비스는 alarms 테이블을 직접 쓰거나 네이티브 알람을 직접
// 등록/취소하지 않는다 - 그래서 기존 알람 로직 파일을 단 한 줄도 import하지 않음.
//
// ⭐ 아직 미완성인 부분(백업복구_설계.md "다음 단계" 참고): 이 파일은 "메모리상
// BackupPayload 조립/복원" 로직까지만 제공함. 실제 파일 저장 위치(MediaStore 등),
// 자동 백업 트리거(PRAGMA data_version 감시), 최초 실행 시 "기존 백업 발견" UI는
// 아직 없음 - 다음 작업에서 이 서비스를 그대로 재사용해서 얹으면 됨.

import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/backup_payload.dart';
import 'database_service.dart';

/// 백업에서 제외할 테이블. 새 "원본 데이터" 테이블(예: 향후 수면 기록)을 추가할
/// 때는 보통 아무 것도 안 해도 자동으로 백업에 포함된다(exportAll이
/// sqlite_master를 그때그때 읽으므로) - 오직 "이 테이블은 다른 테이블로부터
/// 100% 재생성 가능한 파생 데이터다"라고 확신할 때만 여기 추가할 것. (원본
/// vs 파생 데이터 구분은 백업복구_설계.md 2장 참고)
const Set<String> kBackupExcludedTables = {
  // shift_schedule + shift_alarm_templates로부터 AlarmRefreshEngine이 재생성하는
  // "현재 등록된 알람"의 캐시. 원본이 아니라 파생 데이터라 백업 대상이 아님.
  'alarms',
};

/// sqflite/Android가 내부적으로 쓰는 테이블 - 사용자 데이터가 아니므로 항상 제외.
const Set<String> _kSystemTables = {'android_metadata', 'sqlite_sequence'};

class BackupResult {
  final int schemaVersion;
  final DateTime exportedAt;
  final int tableCount;
  final int totalRowCount;

  const BackupResult({
    required this.schemaVersion,
    required this.exportedAt,
    required this.tableCount,
    required this.totalRowCount,
  });
}

class BackupRestoreException implements Exception {
  final String message;
  BackupRestoreException(this.message);
  @override
  String toString() => 'BackupRestoreException: $message';
}

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// 현재 사용자 데이터 전체를 [BackupPayload]로 모은다. 읽기 전용 - 어떤
  /// 테이블도, SharedPreferences 값도 수정하지 않는다.
  Future<BackupPayload> exportAll() async {
    final db = await DatabaseService.instance.database;

    final tableNames = await _listBackupableTables(db);
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final name in tableNames) {
      tables[name] = await db.query(name);
    }

    final prefs = await SharedPreferences.getInstance();
    final preferences = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      preferences[key] = prefs.get(key);
    }

    String appVersionName = '';
    int appVersionCode = 0;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersionName = info.version;
      appVersionCode = int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      // 버전 정보는 부가 정보일 뿐이라 실패해도 백업 자체는 계속 진행
      print('⚠️ 백업용 앱 버전 조회 실패(백업은 계속 진행): $e');
    }

    return BackupPayload(
      schemaVersion: kBackupSchemaVersion,
      exportedAt: DateTime.now(),
      appVersionName: appVersionName,
      appVersionCode: appVersionCode,
      tables: tables,
      preferences: preferences,
    );
  }

  /// [exportAll]과 동일하지만 바로 JSON 문자열로 인코딩해서 반환.
  Future<String> exportAllAsJson() async => (await exportAll()).encode();

  BackupResult summarize(BackupPayload payload) {
    return BackupResult(
      schemaVersion: payload.schemaVersion,
      exportedAt: payload.exportedAt,
      tableCount: payload.tables.length,
      totalRowCount: payload.totalRowCount,
    );
  }

  /// 백업 데이터를 현재 DB에 복원한다.
  ///
  /// ⚠️ 반드시 "완전히 새로 시작하는" 상태(온보딩 전, shift_schedule이 비어있는
  /// 상태)에서만 호출할 것 - 이미 사용 중인 데이터가 있는데 실수로 덮어써서
  /// 잃어버리는 사고를 막기 위해 기본적으로 shift_schedule에 행이 하나라도
  /// 있으면 예외를 던진다. 정말로 강제로 덮어써야 하는 예외적 상황(예: 향후
  /// "백업으로 되돌리기" 기능)에서만 [force]를 true로 넘길 것.
  ///
  /// 복원은 여기 있는 원본 데이터 테이블들에 값을 채워넣는 것으로 끝난다 - 이
  /// 함수는 alarms 테이블을 만들거나 네이티브 알람을 등록하지 않는다. 복원
  /// 직후 앱이 평소처럼 시작되면(또는 재시작되면) 기존 알람 갱신 로직이
  /// shift_schedule/shift_alarm_templates를 읽어 알람을 알아서 다시 채운다.
  Future<void> restoreAll(BackupPayload payload, {bool force = false}) async {
    final db = await DatabaseService.instance.database;

    if (!force) {
      final existing = await db.query('shift_schedule', limit: 1);
      if (existing.isNotEmpty) {
        throw BackupRestoreException(
          '이미 사용 중인 데이터가 있어 복원을 건너뜀(force=true로 강제 가능)',
        );
      }
    }

    if (payload.schemaVersion > kBackupSchemaVersion) {
      // ⭐ 이 앱보다 더 새 버전에서 만든 백업 - 미래 버전에서 봉투 구조 자체가
      // 바뀌었을 수 있어 안전하게 거부. schemaVersion을 올릴 때 여기에 실제
      // 마이그레이션 분기를 추가할 것(백업복구_설계.md 9장 "버전 관리" 참고).
      throw BackupRestoreException(
        '이 앱 버전이 지원하지 않는 백업 형식(schemaVersion=${payload.schemaVersion})',
      );
    }

    final knownTables = await _listBackupableTables(db);

    await db.transaction((txn) async {
      for (final entry in payload.tables.entries) {
        final table = entry.key;
        // ⭐ 백업엔 있지만 현재 앱 스키마엔 없는 테이블(예: 예전 버전 백업의
        // 이미 없어진 테이블)은 조용히 건너뜀 - 예외로 전체 복원이 실패하는
        // 것보다, 알 수 있는 테이블만 최대한 복원하는 쪽이 사용자에게 낫다고
        // 판단.
        if (!knownTables.contains(table)) continue;

        await txn.delete(table);
        for (final row in entry.value) {
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });

    final prefs = await SharedPreferences.getInstance();
    for (final entry in payload.preferences.entries) {
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is List) {
        await prefs.setStringList(entry.key, value.cast<String>());
      }
      // null이거나 알 수 없는 타입은 건너뜀(SharedPreferences가 지원하지 않는 값)
    }
  }

  Future<List<String>> _listBackupableTables(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = rows.map((r) => r['name'] as String).toSet();
    names.removeAll(_kSystemTables);
    names.removeAll(kBackupExcludedTables);
    return names.toList()..sort();
  }
}
