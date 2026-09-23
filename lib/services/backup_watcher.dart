// lib/services/backup_watcher.dart
//
// ⭐ 사용자 데이터 백업 - 자동 백업(Layer 3). 앱 시작·재개·배경 전환(main.dart)은 자동 슬롯, 설정 탭 "데이터 백업"(manual)은 직접 슬롯에 씀
// (2026-09-23 1.0.24 A - 두 슬롯은 서로를 덮어쓰지 않음).
//
// ⭐ 2026-09-14 (출시전 감사 G4 #2 C02+M10) - 변경 감지를 `PRAGMA data_version` 숫자 비교에서 **내용 지문 비교**로 교체.
//  - data_version은 같은 연결의 두 시점 사이에서만 비교 의미가 있는데, 예전 코드는 매번 새 연결로 읽은 값을 이전 호출(다른 연결)의
//    값과 비교해서 실제 변경을 놓칠 수 있었고, 설정만 바뀐 경우는 애초에 감지 대상이 아니었음.
//  - 이제 백업 내용(테이블 rowid 순 + 설정 키 정렬, exportedAt 제외)을 정규화한 문자열의 지문을 **파일 저장이 성공한 뒤에만**
//    "마지막 성공 지문"으로 기록하고, 다음 시도에서 같으면 건너뜀. 설정 변경도 감지됨.
//  - single flight: 실행 중에 온 요청은 종류(직접/자동)별로 하나씩 모아 끝난 뒤 차례로 실행 → 중복 파일 쓰기·UI 대기 없음,
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

  /// 자동 백업 슬롯의 마지막 성공 지문(키 이름은 1.0.23과 같음 - 의미도 "자동 백업이 마지막으로 쓴 내용").
  static const _kLastContentHashKey = 'backup_last_content_hash';
  static const _kLegacyDataVersionKey = 'backup_last_data_version';

  /// 1.0.23 이하에서 쓰던 "마지막 백업 시각"(직접·자동 구분 없음). 새 키가 없을 때 자동 슬롯 시각의 대체값으로만 읽음.
  static const kLegacyLastSavedAtKey = 'backup_last_saved_at';

  /// ⭐ 2026-09-23 (1.0.24 A) - 슬롯별 마지막 저장 시각. 설치별 값이라 백업 대상 아님(backup_policy.dart).
  static const kLastSavedAtAutoKey = 'backup_last_saved_at_auto';
  static const kLastSavedAtManualKey = 'backup_last_saved_at_manual';

  /// 두 슬롯 형식으로 자동 백업을 한 번이라도 썼는지. 없으면(1.0.23에서 업데이트 직후) 내용이 같아도 자동 백업을 한 번 써서
  /// 네이티브가 옛 형식 파일을 정리하게 함(결정 6).
  static const kSlotFormatKey = 'backup_slot_format_v2';

  bool _running = false;

  /// 실행 중에 들어온 요청 - 종류별로 하나씩만 모아 둠(자동 요청이 직접 요청에 합쳐져 자동 슬롯이 건너뛰어지지 않게).
  Completer<bool>? _queuedManual;
  Completer<bool>? _queuedAuto;

  /// 백업을 시도한다.
  ///  - [manual] false(자동 트리거: 앱 시작·재개·배경 전환): 자동 슬롯에 쓰며, 마지막 자동 백업 이후 내용이 같으면 쓰지 않고 성공으로 취급.
  ///  - [manual] true(설정의 "데이터 백업"): 직접 슬롯에 내용과 무관하게 씀. 자동 슬롯은 건드리지 않음.
  Future<bool> backupNow({bool manual = false}) {
    if (_running) {
      return manual
          ? (_queuedManual ??= Completer<bool>()).future
          : (_queuedAuto ??= Completer<bool>()).future;
    }
    return _start(manual);
  }

  Future<bool> _start(bool manual) async {
    _running = true;
    bool result;
    try {
      result = await _run(manual);
    } finally {
      _running = false;
    }
    _drainQueue();
    return result;
  }

  /// 대기 중인 요청을 직접 → 자동 순서로 하나씩 실행(single flight 유지).
  void _drainQueue() {
    final Completer<bool>? next;
    final bool nextManual;
    if (_queuedManual != null) {
      next = _queuedManual;
      _queuedManual = null;
      nextManual = true;
    } else if (_queuedAuto != null) {
      next = _queuedAuto;
      _queuedAuto = null;
      nextManual = false;
    } else {
      return;
    }
    unawaited(_start(nextManual).then(next!.complete, onError: next.completeError));
  }

  Future<bool> _run(bool manual) async {
    final kind = manual ? BackupKind.manual : BackupKind.auto;
    try {
      if (await _restoreInProgress()) {
        debugPrint('🗄️ [backup] 스킵 - 백업 복원 진행 중/중단된 복원 작업 있음');
        return !manual;
      }

      final db = await DatabaseService.instance.database;
      if (!manual) {
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
      if (!manual &&
          prefs.getBool(kSlotFormatKey) == true &&
          prefs.getString(_kLastContentHashKey) == fingerprint) {
        debugPrint('🗄️ [backup] 스킵 - 내용 변경 없음');
        return true;
      }

      debugPrint('🗄️ [backup] 쓰기 시작(${kind.channelArg}, 테이블 ${payload.tables.length}개, 행 ${payload.totalRowCount}개)');
      final wrote = await BackupStorageService.instance.write(encoded['content']!, kind: kind);
      debugPrint('🗄️ [backup] 쓰기 결과: $wrote');
      if (!wrote) return false;

      // 파일 저장 성공 뒤에만 상태 기록. 지문은 자동 슬롯 기준이라 자동 백업일 때만 갱신.
      final now = DateTime.now().toIso8601String();
      if (manual) {
        await prefs.setString(kLastSavedAtManualKey, now);
      } else {
        await prefs.setString(_kLastContentHashKey, fingerprint);
        await prefs.setString(kLastSavedAtAutoKey, now);
        await prefs.setBool(kSlotFormatKey, true);
        await prefs.remove(kLegacyLastSavedAtKey);
      }
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

  /// 설정 탭 표시용 - 슬롯별 마지막 저장 시각. 자동 슬롯은 새 키가 없으면 1.0.23의 값(구분 없던 마지막 백업)을 대신 씀.
  Future<({DateTime? manual, DateTime? auto})> lastSavedAtBySlot() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? read(String key) {
      final str = prefs.getString(key);
      return str == null ? null : DateTime.tryParse(str);
    }

    return (
      manual: read(kLastSavedAtManualKey),
      auto: read(kLastSavedAtAutoKey) ?? read(kLegacyLastSavedAtKey),
    );
  }
}
