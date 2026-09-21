// lib/providers/sleep_condition_provider.dart
//
// ⭐ 실제 수면 기록을 근무 일정(ShiftPatternAnalyzer, condition_provider.dart)과
// 엮어서 수면·회복 탭에 필요한 파생값을 만드는 Provider들.
//
// ⭐ 2026-09-15 (출시 적합성 재검토 후속) - 컨디션 점수(conditionScoreProvider)·날짜 시드 문구
// (todayForecastProvider)·범용 건강 Tip을 삭제하고 "오늘의 컨디션"을 recoveryBriefingProvider 하나로 대체.
// 화면에서 쓰이지 않던 파생 provider(todayRecoverySleepProvider - 이름과 달리 "회복구간 전체를 감싸는"
// 기록만 찾던 것, recentWorkNights/personalSleepPatterns/sleepShiftRelationSummary/recentSleepCoverage)도
// 같이 정리함. ConditionRuleEngine(3단계 판정)은 여전히 수면을 모른다(판정은 일정 기반).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sleep_record.dart';
import '../services/condition/recovery_briefing_engine.dart';
import '../services/condition/sleep_by_category_stats.dart';
import '../services/condition/sleep_day_slots.dart';
import '../services/condition/sleep_shift_relation.dart';
import 'condition_provider.dart';
import 'current_date_provider.dart';
import 'sleep_record_provider.dart';

/// ⭐ 2026-09-01 - "최근 수면 기록" 미니 달력 카드(condition_tab.dart)가 보여주는
/// 날짜 범위(오늘 포함 최근 N일). 전체보기 화면(sleep_calendar_full_screen.dart)은
/// 이 provider 대신 월 단위로 buildSleepDaySlots()를 직접 호출한다.
const int kSleepMiniCalendarDays = 14;

final recentSleepDaySlotsProvider = Provider<List<SleepDaySlots>>((ref) {
  final records = ref.watch(sleepRecordProvider).value ?? const [];
  final analyzer = ref.watch(conditionAnalyzerProvider);
  // ⭐ 2026-09-15 (AUD-05) - 자정·앱 재개 때 바뀌는 "오늘"을 구독(current_date_provider.dart)
  final today = ref.watch(currentDateProvider);
  return buildSleepDaySlots(
    records: records,
    from: today.subtract(const Duration(days: kSleepMiniCalendarDays - 1)),
    to: today,
    analyzer: analyzer,
  );
});

/// 최근 수면 기록 각각에 대해 근무 겹침 분류(SleepRelation)를 같이 묶어서 제공.
/// analyzer가 아직 없으면(스케줄/근무시간 미설정) 분류 없이 원본만 반환.
final sleepRecordsWithRelationProvider = Provider<List<(SleepRecord, SleepRelation?)>>((ref) {
  final records = ref.watch(sleepRecordProvider).value ?? const [];
  final analyzer = ref.watch(conditionAnalyzerProvider);
  if (analyzer == null) {
    return records.map((r) => (r, null)).toList();
  }
  return records.map((r) => (r, classifySleepRelation(r, analyzer))).toList();
});

/// "오늘의 컨디션"은 "지금 이 시각" 기준(근무 중·퇴근 후 몇 시간·출근까지 몇 시간)이라 날짜만 구독하면
/// 화면을 켜 둔 동안 남은 시간이 멈춰 보인다. 탭이 보이는 동안만 1분마다 갱신(autoDispose - 탭을 떠나면 타이머도 멈춤).
final briefingClockProvider = AutoDisposeNotifierProvider<BriefingClock, DateTime>(BriefingClock.new);

class BriefingClock extends AutoDisposeNotifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => state = appNow());
    ref.onDispose(() => _timer?.cancel());
    return appNow();
  }
}

/// ⭐ P2 #6(2026-09-18) - "근무 종류별 평균 수면"(야간/주간/오후 후, 휴무일). 스케줄이
/// 없으면(analyzer null) 빈 목록 - condition_tab.dart는 빈 목록이면 섹션 자체를 숨긴다.
final sleepCategoryAveragesProvider = Provider<List<SleepCategoryAverage>>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  if (analyzer == null) return const [];
  final records = ref.watch(sleepRecordProvider).value ?? const <SleepRecord>[];
  final today = ref.watch(currentDateProvider);
  return buildSleepCategoryAverages(records: records, analyzer: analyzer, now: today);
});

/// "오늘의 컨디션" - 확인된 사실 / 추천 행동 / 판단 범위(recovery_briefing_engine.dart).
/// 근무시간이 하나도 없거나 스케줄이 없으면 null(화면은 설정 안내를 보여줌).
final recoveryBriefingProvider = Provider.autoDispose<RecoveryBriefing?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  final base = ref.watch(todayConditionResultProvider);
  if (analyzer == null || base == null) return null;
  final now = ref.watch(briefingClockProvider);
  final records = ref.watch(sleepRecordProvider).value ?? const <SleepRecord>[];
  final otMinutes = ref.watch(recentOvertimeMinutesProvider).value ?? const <String, int>{};
  final pendingCount = ref.watch(pendingSleepRecordsProvider).length;
  return buildRecoveryBriefing(
    analyzer: analyzer,
    base: base,
    records: records,
    now: now,
    otMinutesByDate: otMinutes,
    pendingCount: pendingCount,
  );
});
