// lib/models/backup_payload.dart
//
// ⭐ 백업/복구 기능(백업복구_설계.md 참고)의 최상위 데이터 형태. 실제 테이블 데이터는
// BackupService(lib/services/backup_service.dart)가 채우고, 이 파일은 "봉투"
// (schemaVersion 등 메타데이터 + 직렬화)만 다룸.
//
// ⚠️ 이 파일은 알람/근무 로직을 전혀 참조하지 않는 완전히 새로운 파일 - 백업
// 기능이 기존 코드(알람 데이터/근무명/근무패턴/알람 갱신·발생·notification
// 로직)에 전혀 영향을 주지 않는다는 설계 원칙(백업복구_설계.md 3장)의 일부.

import 'dart:convert';

/// 백업 데이터 "봉투" 형식(JSON 구조) 버전. DB의 DATABASE_VERSION(현재 20,
/// database_service.dart)과는 완전히 다른 개념 - 테이블이 늘어나는 것 자체는
/// 이 버전을 안 올려도 됨(BackupService가 테이블 목록을 매번 동적으로 읽으므로).
/// 이 값은 오직 봉투 구조 자체(tables/preferences 필드 의미 등)가 바뀔 때만
/// 올린다. DB_스키마_변경_가이드.md의 DATABASE_VERSION과 혼동하지 말 것.
const int kBackupSchemaVersion = 1;

class BackupPayload {
  final int schemaVersion;
  final DateTime exportedAt;
  final String appVersionName;
  final int appVersionCode;

  /// DB 테이블명 → 그 테이블의 전체 행(raw Map, sqflite가 반환하는 그대로).
  final Map<String, List<Map<String, dynamic>>> tables;

  /// SharedPreferences 전체 스냅샷(키 → 값). 의도적으로 선별하지 않고 전체를
  /// 담음 - 새 설정이 추가돼도 이 파일을 손댈 필요가 없게 하기 위함
  /// (백업복구_설계.md 4장 "설정 데이터" 참고).
  final Map<String, dynamic> preferences;

  const BackupPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersionName,
    required this.appVersionCode,
    required this.tables,
    required this.preferences,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersionName': appVersionName,
        'appVersionCode': appVersionCode,
        'tables': tables,
        'preferences': preferences,
      };

  factory BackupPayload.fromJson(Map<String, dynamic> json) {
    final rawTables = (json['tables'] as Map).cast<String, dynamic>();
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawTables.entries) {
      tables[entry.key] = (entry.value as List)
          .map((row) => (row as Map).cast<String, dynamic>())
          .toList();
    }
    return BackupPayload(
      schemaVersion: json['schemaVersion'] as int,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      appVersionName: json['appVersionName'] as String? ?? '',
      appVersionCode: json['appVersionCode'] as int? ?? 0,
      tables: tables,
      preferences: (json['preferences'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  String encode() => jsonEncode(toJson());

  static BackupPayload decode(String jsonStr) =>
      BackupPayload.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  /// 대략적인 규모 요약(디버그/UI 표시용) - 전체 행 개수 합.
  int get totalRowCount =>
      tables.values.fold(0, (sum, rows) => sum + rows.length);
}
