// lib/services/backup_watcher.dart
//
// ⭐ 사용자 데이터 백업 - 자동 백업(Layer 3). 앱 시작·재개·배경 전환(main.dart)과 설정 탭 "지금 백업"(force)이 같은 경로를 씀.
//
// ⭐ 2026-09-14 (출시전 감사 G4 #2 C02+M10) - 변경 감지를 `PRAGMA data_version` 숫자 비교에서 **내용 지문 비교**로 교체.
//  - data_version은 같은 연결의 두 시점 사이에서만 비교 의미가 있는데, 예전 코드는 매번 새 연결로 읽은 값을 이전 호출(다른 연결)의
//    값과 비교해서 실제 변경을 놓칠 수 있었고, 설정만 바뀐 경우는 애초에 감지 대상이 아니었음.
//  - 이제 백업 내용(테이블 rowid 순 + 설정 키 정렬, exportedAt 제외)을 정규화한 문자열의 지문을 **파일 저장이 성공한 뒤에만**
//    "마지막 성공 지문"으로 기록하고, 다음 시도에서 같으면 건너뜀. 설정 변경도 감지됨.
//  - single flight: 실행 중에 온 요청은 하나로 합쳐(force는 OR) 끝난 뒤 한 번 더 실행 → 중복 파일 쓰기·UI 대기 없음,
//    실행 중에 생긴 변경도 다음 실행에서 확인됨.
//  - JSON 정규화·인코딩·지문 계산은 별도 isolate, MediaStore 파일 I/O는 네이티브 백그라운드 스레드(MainActivity).
//  - 백업 복원 중(잠금) 또는 중단된 복원 작업이 남아 있으면 쓰지 않음 - 복원 도중 상태로 정상 백업 파일을 덮어쓰지 않게(#19).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/platform_channel.dart';
import 'backup_policy.dart';
import 'backup_service.dart';
import 'backup_storage_service.dart';
import 'database_service.dart';
import 'restore_coordinator.dart';

/// isolate에서 실행 - 파일 내용(JSON)과 내용 지문을 함께 계산.
Map<String, String> _encodeBackupForWrite(Map<String, dynamic> payloadJson) {
  final tables = (payloadJson['tables'] as Map).map(
    (k, v) => MapEntry(k as String, (v as List).map((r) => (r as Map).cast<String, dynamic>()).toList()),
  );
  final prefs = (payloadJson['preferences'] as Map).cast<String, dynamic>();
  return {
    'content': jsonEncode(payloadJson),
    'fingerprint': contentFingerprint(canonicalBackupContent(tables, prefs)),
  };
}

class BackupWatcher {
  BackupWatcher._();
  static final BackupWatcher instance = BackupWatcher._();

  static const _kLastContentHashKey = 'backup_last_content_hash';
  static const _kLegacyDataVersionKey = 'backup_last_data_version';
  static const _kLastSavedAtKey = 'backup_last_saved_at';

  bool _running = false;
  Completer<bool>? _queued;
  bool _queuedForce = false;

  /// 백업을 시도한다. [force]가 false(자동 트리거)면 마지막 성공 이후 내용이 같으면 쓰지 않고 성공으로 취급.
  /// [force]가 true(수동 "지금 백업")면 내용과 무관하게 씀.
  Future<bool> backupNow({bool force = false}) {
    if (_running) {
      _queuedForce = _queuedForce || force;
      return (_queued ??= Completer<bool>()).future;
    }
    return _start(force);
  }

  Future<bool> _start(bool force) async {
    _running = true;
    bool result;
    try {
      result = await _run(force);
    } finally {
      _running = false;
    }
    final queued = _queued;
    if (queued != null) {
      _queued = null;
      final nextForce = _queuedForce;
      _queuedForce = false;
      unawaited(_start(nextForce).then(queued.complete, onError: queued.completeError));
    }
    return result;
  }

  Future<bool> _run(bool force) async {
    try {
      if (await _restoreInProgress()) {
        debugPrint('🗄️ [backup] 스킵 - 백업 복원 진행 중/중단된 복원 작업 있음');
        return !force;
      }

      final db = await DatabaseService.instance.database;
      if (!force) {
        // 근무 일정이 비어 있을 때(설정 전·초기화 직후) 자동 백업이 진짜 백업을 빈 스냅샷으로 덮어쓰지 않게 함(2026-09-01 안전장치 유지)
        final scheduleRows = await db.query('shift_schedule', limit: 1);
        if (scheduleRows.isEmpty) {
          debugPrint('🗄️ [backup] 스킵 - shift_schedule 비어있음');
          return true;
        }
      }

      final payload = await BackupService.instance.exportAll();
      final encoded = await compute(_encodeBackupForWrite, payload.toJson());
      final fingerprint = encoded['fingerprint']!;

      final prefs = await SharedPreferences.getInstance();
      if (!force && prefs.getString(_kLastContentHashKey) == fingerprint) {
        debugPrint('🗄️ [backup] 스킵 - 내용 변경 없음');
        return true;
      }

      debugPrint('🗄️ [backup] 쓰기 시작(force=$force, 테이블 ${payload.tables.length}개, 행 ${payload.totalRowCount}개)');
      final wrote = await BackupStorageService.instance.write(encoded['content']!);
      debugPrint('🗄️ [backup] 쓰기 결과: $wrote');
      if (!wrote) return false;

      // 파일 저장 성공 뒤에만 성공 지문 기록
      await prefs.setString(_kLastContentHashKey, fingerprint);
      await prefs.setString(_kLastSavedAtKey, DateTime.now().toIso8601String());
      await prefs.remove(_kLegacyDataVersionKey);
      return true;
    } catch (e, st) {
      // 백업(특히 자동 트리거) 실패가 앱 사용을 방해하면 안 됨 - 로그만 남김
      debugPrint('🗄️ [backup] ❌ 예외로 실패: $e\n$st');
      return false;
    }
  }

  Future<bool> _restoreInProgress() async {
    if (await RestoreCoordinator.instance.hasPendingJob()) return true;
    try {
      return await kAlarmChannel.invokeMethod<bool>('restoreIsLocked') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 설정 탭에 "마지막 백업: OOOO" 표시용.
  Future<DateTime?> lastSavedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kLastSavedAtKey);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }
}
