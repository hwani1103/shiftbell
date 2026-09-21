// lib/providers/sleep_record_provider.dart
//
// ⭐ 실제 수면 기록/자동 추정 전용 - sleep_records 테이블(신규, v22)을 Riverpod으로
// 노출. Native(SleepDetectionReceiver.kt/SleepWidgetActionReceiver.kt)도 같은
// 테이블에 직접 쓰므로, 이 Notifier는 "화면을 열 때마다/필요할 때 다시 읽는" 용도로만
// 쓴다 - 실시간 push 구독은 하지 않음(수면기록_자동추정_설계.md 6~7장).
//
// ⚠️ 자동 감지 결과가 기존 수동 기록을 절대 덮어쓰지 않는다는 원칙(스펙 13장)은
// DB 쓰기 자체가 항상 새 row(insert) 또는 "자기 자신"만 update하는 구조로 지켜짐 -
// 이 Provider가 기존 레코드를 자동으로 병합/치환하는 로직은 없음.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/platform_channel.dart';
import '../models/sleep_record.dart';
import '../services/database_service.dart';
import '../services/app_analytics.dart';

/// ⭐ 2026-09-11(사용자 요청) - "장기간 폰을 안 만지면 몇 시든 무조건 수면으로
/// 잡힌다"는 오탐 문제의 완화책. 근무 중/휴무일 조용한 활동처럼 일정만으로는
/// 구분 불가능한 시간대는, 사용자가 실제로 "이건 수면이 아니었다"고 거부한
/// 기록 자체를 근거로 학습한다(Native SleepDetectionReceiver.kt의 REJECT_* 참고
/// - 같은 시(hour)에서 반복 거부되면 그 시간대의 자동 후보 생성을 건너뜀).
/// 순수 부가 기능이라 실패해도 기록 삭제 자체는 항상 정상 진행되어야 함.
Future<void> _notifyAutoRejection(SleepRecord record) async {
  if (record.source != SleepSource.autoDetected) return;
  try {
    await kAlarmChannel.invokeMethod('recordSleepAutoRejection', {
      'startEpochMillis': record.start.millisecondsSinceEpoch,
    });
  } catch (e) {
    debugPrint('⚠️ recordSleepAutoRejection 실패(무시): $e');
  }
}

final sleepRecordProvider =
    StateNotifierProvider<SleepRecordNotifier, AsyncValue<List<SleepRecord>>>(
        (ref) => SleepRecordNotifier());

/// ⭐ 2026-09-04 - M8 수정(전체_코드_점검_리포트_2026-09-04.md). Kotlin
/// (`SleepWidgetActionReceiver.kt`의 `MIN_MEANINGFUL_MINUTES`)에만 있던 "2분
/// 미만은 의미 있는 수면으로 안 보고 버린다"는 최소 길이 검증이 Dart 쪽(수동
/// 추가/수정, AUTO_DETECTED 후보 확정)엔 전혀 없어서 연타/실수로 몇 초짜리
/// 기록이 그대로 저장될 수 있었음 - 같은 값(2분)으로 맞춤.
const int kMinMeaningfulSleepMinutes = 2;

bool _isMeaningfulSleepDuration(DateTime start, DateTime end) =>
    end.difference(start).inMinutes >= kMinMeaningfulSleepMinutes;

class SleepRecordNotifier extends StateNotifier<AsyncValue<List<SleepRecord>>> {
  SleepRecordNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now();
      final pending = await DatabaseService.instance.getPendingSleepRecords();
      for (final record in pending) {
        if (record.id == null ||
            record.source != SleepSource.autoDetected ||
            record.end != null ||
            !isAutoSleepCandidateExpired(record.start, now)) {
          continue;
        }
        // Native의 9시간 트리거가 지연되거나 앱이 먼저 열린 경우의 동일한
        // 백스톱. 종료 시각은 행의 start에서 파생하며 확인 대기 상태를 유지한다.
        await DatabaseService.instance.updateSleepRecord(record.copyWith(
          end: cappedAutoSleepCandidateEnd(record.start, now),
          confidence: SleepConfidence.low,
        ));
      }
      // ⭐ 2026-09-01 - "오늘의 컨디션 예측"이 최대 8주(56일)치 근무-수면 데이터를
      // 봐야 해서 30일 → 60일로 넓힘(sleep_history.dart/today_forecast_engine.dart
      // 참고). 그 외 화면(최근 수면 기록 리스트 등)은 원래도 "최근 N개/N일"만
      // 뽑아 쓰므로 더 넓게 가져와도 영향 없음.
      final records = await DatabaseService.instance
          .getSleepRecords(since: DateTime.now().subtract(const Duration(days: 60)));
      state = AsyncValue.data(records);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  /// 위젯 토글과 동일한 동작을 앱 안에서도 쓸 수 있게(주로 테스트/보조용) -
  /// 근무 중 여부와 무관하게 항상 허용(설계 문서 2장 - validation 없음).
  Future<void> addManual({required DateTime start, required DateTime end}) async {
    if (!_isMeaningfulSleepDuration(start, end)) return; // M8 - 2분 미만은 버림
    await DatabaseService.instance.insertSleepRecord(SleepRecord(
      start: start,
      end: end,
      source: SleepSource.manual,
      status: SleepStatus.confirmed,
    ));
    AppAnalytics.track(AnalyticsEvent.sleepRecordSaved, params: {'source': 'manual'});
    await refresh();
  }

  /// 자동 감지 후보를 "맞아요"로 확정. 시작/종료 시각을 그대로 또는 사용자가 고친
  /// 값으로 확정한다(스펙 12장 [수정] 포함).
  Future<void> confirmPending(SleepRecord record, {DateTime? overrideStart, DateTime? overrideEnd}) async {
    final effectiveStart = overrideStart ?? record.start;
    final effectiveEnd = overrideEnd ?? record.end;
    // M8 - 확정 결과가 2분 미만이면 버림(Kotlin의 AUTO 확정과 달리 여긴 근무중
    // 낮잠 등도 올 수 있어 2분 기준을 그대로 씀 - MANUAL과 동일).
    if (effectiveEnd != null && !_isMeaningfulSleepDuration(effectiveStart, effectiveEnd)) return;
    final updated = record.copyWith(
      start: overrideStart,
      end: overrideEnd,
      status: SleepStatus.confirmed,
    );
    await DatabaseService.instance.updateSleepRecord(updated);
    AppAnalytics.track(AnalyticsEvent.sleepRecordSaved, params: {'source': 'auto_confirmed'});
    await refresh();
  }

  /// ⭐ P2 #7(2026-09-18, 사용자 요청) - "보이는 기록 모두 확인" 일괄 처리. 여러 건을
  /// confirmPending()으로 하나씩 부르면 매번 DB 갱신 후 `refresh()`가 전체 목록을
  /// 다시 읽어와서(60일치) 건수만큼 DB 왕복이 반복된다 - 여기선 업데이트를 전부
  /// 끝내고 마지막에 한 번만 refresh한다. 시각 수정 없이 "그대로 맞다"만 일괄
  /// 처리하는 용도라 overrideStart/End는 안 받는다(수정이 필요하면 개별 카드의
  /// [수정]을 쓰거나, 확인 뒤 "최근 수면 기록"에서 다시 고치면 됨).
  Future<void> confirmAllPending(List<SleepRecord> records) async {
    for (final record in records) {
      final effectiveEnd = record.end;
      if (effectiveEnd != null && !_isMeaningfulSleepDuration(record.start, effectiveEnd)) continue;
      await DatabaseService.instance.updateSleepRecord(record.copyWith(status: SleepStatus.confirmed));
    }
    await refresh();
  }

  /// "기록하지 않기" - 자동 감지 결과를 완전히 폐기.
  Future<void> discardPending(SleepRecord record) async {
    if (record.id == null) return;
    await _notifyAutoRejection(record);
    await DatabaseService.instance.deleteSleepRecord(record.id!);
    await refresh();
  }

  /// ⭐ 2026-09-01 - "최근 수면 기록" 미니 달력 카드/전체보기 화면에서 이미 저장된
  /// 기록(수동이든, 확정된 자동이든 무관)의 취침/기상 시각을 직접 고쳐 쓸 때 씀 -
  /// confirmPending과 달리 status는 그대로 두고 시각만 갱신한다.
  Future<void> updateTimes(SleepRecord record, {required DateTime start, required DateTime end}) async {
    if (record.id == null) return;
    if (!_isMeaningfulSleepDuration(start, end)) return; // M8 - 2분 미만은 버림
    await DatabaseService.instance.updateSleepRecord(record.copyWith(start: start, end: end));
    await refresh();
  }

  Future<void> deleteRecord(int id) async {
    // ⭐ 2026-09-11 - "최근 수면 기록" 미니 달력/전체보기에서 확정된 AUTO_DETECTED
    // 기록을 나중에 지우는 것도 "이건 수면이 아니었다"는 동일한 신호이므로
    // discardPending과 마찬가지로 거부 학습에 반영한다.
    final current = state.value ?? const [];
    final matches = current.where((r) => r.id == id);
    if (matches.isNotEmpty) await _notifyAutoRejection(matches.first);
    await DatabaseService.instance.deleteSleepRecord(id);
    await refresh();
  }
}

/// 화면 상단 확인 카드에 쓸 PENDING_CONFIRMATION 목록만 뽑아낸 파생 provider.
final pendingSleepRecordsProvider = Provider<List<SleepRecord>>((ref) {
  final records = ref.watch(sleepRecordProvider).value ?? const [];
  return records.where((r) => r.status == SleepStatus.pendingConfirmation).toList();
});
