// lib/services/backup_policy.dart
//
// ⭐ 2026-09-14 (출시전 감사 G4 #2/#9/#25) - 백업에 무엇을 넣고 무엇을 빼는지, 그리고 "내용이 바뀌었는지"를 판단하는
// 정규화·해시 규칙을 한 곳에 모음. export(BackupService)·자동백업 변경 감지(BackupWatcher)·복원 검증/적용
// (BackupValidator/RestoreCoordinator)이 모두 같은 규칙을 씀.
//
// 원칙(백업복구_설계.md 2장): 새 원본 테이블/설정은 코드 수정 없이 자동으로 백업에 포함된다. 여기에는
// "파생 데이터"와 "이 기기에만 의미 있는 값"만 적는다.

import 'dart:convert';

import 'friend_sync_service.dart';

/// sqflite/Android 내부 테이블 - 사용자 데이터가 아님.
const Set<String> kBackupSystemTables = {'android_metadata', 'sqlite_sequence'};

/// 현재 등록된 알람. fixed는 근무표·템플릿·예외(alarm_overrides)에서 재생성되는 파생 데이터라 백업하지 않고,
/// 사용자가 직접 만든 **미래 custom 알람만** 이 이름으로 담는다(#9). snoozed는 D5로 제외 - 복원 기기에서
/// 진행 중인 스누즈는 별도로 보존함(RestoreCoordinator 이월).
const String kBackupAlarmsTable = 'alarms';

/// 영구 보존 이력 - 복원 시 비우고 교체하지 않고 자연키 기준 중복 제외 병합(#19, 이력 영구 보존 규칙).
const Set<String> kBackupHistoryTables = {'alarm_history', 'alarm_creation_log'};

/// 이 기기(설치)에만 의미 있는 설정 - export하지 않고, 옛 백업에 들어 있어도 import하지 않음.
const Set<String> kDeviceLocalPreferenceKeys = {
  // 자동백업 상태(설치별)
  'backup_last_data_version',
  'backup_last_saved_at',
  'backup_last_content_hash',
  // OS 권한은 설치마다 다시 받아야 함(복원 후 권한 화면 판단은 복원 흐름이 직접 함)
  'permissions_requested',
  // 업데이트 안내 dedupe - 설치·버전별
  'notified_update_version',
  'release_note_last_seen_app_version',
  'release_note_seen_version',
  'update_check_last_checked_at',
  // 웹 뷰어 전용
  'shiftbell_last_owner_id',
};

/// 백업 import/export 대상 설정 키인지. 친구공유 소유권·회차 7키는 G2 계약(#25)대로 항상 제외.
bool isBackupPreferenceKey(String key) =>
    !kDeviceLocalPreferenceKeys.contains(key) &&
    !FriendSyncService.backupExcludedPreferenceKeys.contains(key);

/// 복원 적용 순서상 먼저 비우고 채워야 하는 원본 테이블 판정(시스템·이력·알람 제외).
bool isReplaceableSourceTable(String table) =>
    !kBackupSystemTables.contains(table) &&
    !kBackupHistoryTables.contains(table) &&
    table != kBackupAlarmsTable;

/// 테이블·행·설정을 순서가 고정된 JSON 문자열로 만든다. 테이블명 정렬, 행은 호출부가 rowid 순으로 읽은 순서 유지,
/// 각 행과 설정은 키 정렬. exportedAt 같은 휘발 필드는 넣지 않음 → 같은 데이터면 항상 같은 문자열.
String canonicalBackupContent(
  Map<String, List<Map<String, dynamic>>> tables,
  Map<String, dynamic> preferences,
) {
  final sortedTables = <String, dynamic>{};
  for (final name in tables.keys.toList()..sort()) {
    sortedTables[name] = tables[name]!.map(_sortedMap).toList();
  }
  return jsonEncode({'tables': sortedTables, 'preferences': _sortedMap(preferences)});
}

Map<String, dynamic> _sortedMap(Map<String, dynamic> map) {
  final out = <String, dynamic>{};
  for (final key in map.keys.toList()..sort()) {
    final value = map[key];
    out[key] = value is Map<String, dynamic> ? _sortedMap(value) : value;
  }
  return out;
}

/// 변경 감지용 64비트 FNV-1a(UTF-8) + 길이. 암호학적 용도 아님 - "같은 내용인지"만 판단.
String contentFingerprint(String content) {
  final bytes = utf8.encode(content);
  var hash = -3750763034362895579; // 0xcbf29ce484222325 (64비트 부호 있는 표현)
  const prime = 1099511628211; // 0x100000001b3
  for (final b in bytes) {
    hash ^= b;
    hash *= prime; // Dart VM int는 64비트에서 순환(모바일 전용 코드)
  }
  return '${bytes.length}:${hash.toRadixString(16)}';
}
