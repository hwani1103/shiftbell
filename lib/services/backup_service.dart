// lib/services/backup_service.dart
//
// ⭐ 사용자 데이터 백업 - 전체 설계는 백업복구_설계.md 참고.
//
// 이 파일은 "읽기 전용 export"만 담당한다. 복원(DB·설정·OS 교체)은 단계 기록·잠금·재시도가 필요해서
// 2026-09-14(출시전 감사 G4 #19)에 RestoreCoordinator(restore_coordinator.dart)로 옮겼다.
//
// ⭐ 2026-09-14 (G4 #2/#9) 변경:
//  - 모든 테이블을 **하나의 읽기 트랜잭션** 안에서 읽음 → 서로 다른 시점의 테이블이 한 백업에 섞이지 않음.
//    (DB와 SharedPreferences는 저장소가 달라 둘을 한 트랜잭션으로 묶을 수는 없음 - 설정은 직후 한 번에 복사)
//  - 행은 rowid 순으로 읽어 같은 데이터면 항상 같은 순서 → 내용 지문(backup_policy.dart)으로 변경 감지.
//  - alarms는 fixed(파생)·snoozed(D5 제외) 대신 **미래 custom 알람만** 담음(#9 - 사용자가 직접 만든 알람이 복원 후 사라지던 문제).
//  - 친구공유 소유권 7키·설치별 설정은 담지 않음(#25, backup_policy.dart).

import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/backup_payload.dart';
import 'backup_policy.dart';
import 'database_service.dart';

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

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// 현재 사용자 데이터를 [BackupPayload]로 모은다. 읽기 전용 - 어떤 테이블도, 설정 값도 수정하지 않는다.
  Future<BackupPayload> exportAll() async {
    final db = await DatabaseService.instance.database;

    late final Map<String, List<Map<String, dynamic>>> tables;
    await db.transaction((txn) async {
      tables = await readBackupTables(txn);
    });

    final prefs = await SharedPreferences.getInstance();
    final preferences = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (isBackupPreferenceKey(key)) preferences[key] = prefs.get(key);
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

  BackupResult summarize(BackupPayload payload) {
    return BackupResult(
      schemaVersion: payload.schemaVersion,
      exportedAt: payload.exportedAt,
      tableCount: payload.tables.length,
      totalRowCount: payload.totalRowCount,
    );
  }

  /// 백업 대상 테이블 전체를 [executor](트랜잭션) 안에서 rowid 순으로 읽음.
  static Future<Map<String, List<Map<String, dynamic>>>> readBackupTables(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = rows.map((r) => r['name'] as String).where((n) => !kBackupSystemTables.contains(n)).toList()..sort();
    final nowIso = DateTime.now().toIso8601String();
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final name in names) {
      if (name == kBackupAlarmsTable) {
        tables[name] = await executor.query(
          name,
          where: "type = 'custom' AND date > ?",
          whereArgs: [nowIso],
          orderBy: 'rowid',
        );
      } else {
        tables[name] = await executor.query(name, orderBy: 'rowid');
      }
    }
    return tables;
  }
}
