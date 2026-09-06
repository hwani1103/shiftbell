// lib/providers/sleep_condition_provider.dart
//
// ⭐ 실제 수면 기록을 근무 일정(ShiftPatternAnalyzer, condition_provider.dart)과
// 엮어서 화면에 필요한 파생값을 만드는 Provider들. ConditionRuleEngine(B번)은
// 여기서 전혀 참조하지 않는다 - "Sleep Detection/통계는 판정 엔진과 분리"라는
// 원칙(수면기록_자동추정_설계.md 5장)을 Provider 레이어에서도 그대로 지킴.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sleep_record.dart';
import '../services/condition/condition_score.dart';
import '../services/condition/sleep_day_slots.dart';
import '../services/condition/sleep_history.dart';
import '../services/condition/sleep_shift_relation.dart';
import '../services/condition/sleep_stats.dart';
import '../services/condition/today_forecast_engine.dart';
import 'condition_provider.dart';
import 'schedule_provider.dart';
import 'sleep_record_provider.dart';

/// ⭐ 2026-09-01 - "최근 수면 기록" 미니 달력 카드(condition_tab.dart)가 보여주는
/// 날짜 범위(오늘 포함 최근 N일). 전체보기 화면(sleep_calendar_full_screen.dart)은
/// 이 provider 대신 월 단위로 buildSleepDaySlots()를 직접 호출한다.
const int kSleepMiniCalendarDays = 14;

final recentSleepDaySlotsProvider = Provider<List<SleepDaySlots>>((ref) {
  final records = ref.watch(sleepRecordProvider).value ?? const [];
  final analyzer = ref.watch(conditionAnalyzerProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return buildSleepDaySlots(
    records: records,
    from: today.subtract(const Duration(days: kSleepMiniCalendarDays - 1)),
    to: today,
    analyzer: analyzer,
  );
});

/// ⭐ 2026-09-01 후속18(사용자 재지적) - "오늘의 컨디션" 카드 하단의 "최근 N일
/// 중 수면 기록 M일 반영" 캡션 전용. 처음엔 today_forecast_engine.dart의
/// trackedNightCount/nightsWithSleepData(=collectRecentWorkNights 기반, 근무일만
/// 셈)를 그대로 썼는데, 사용자가 "근무일인지 휴무일인지는 안 중요하다, 그냥
/// 최근 30일 중 수면 기록이 있냐 없냐만 보면 된다"고 명확히 정정함 - 그래서
/// 근무 스케줄과 완전히 무관하게, "최근 수면 기록" 미니 달력과 동일한
/// buildSleepDaySlots()(이미 검증된 로직 - 어느 날짜에 수면이 귀속되는지도
/// 이미 정확히 계산해줌)로 최근 30일 중 확정 수면 기록이 하루라도 있는 날의
/// 수만 센다. 근무일 커버리지 개념(SleepDataCoverage/trend)은 여기서 전혀
/// 안 건드림 - 그건 여전히 today_forecast_engine.dart가 따로 판단.
const int kRecentSleepCoverageDays = 30;

class RecentSleepCoverage {
  final int trackedDays;
  final int daysWithSleep;
  const RecentSleepCoverage({required this.trackedDays, required this.daysWithSleep});
}

final recentSleepCoverageProvider = Provider<RecentSleepCoverage>((ref) {
  final records = ref.watch(sleepRecordProvider).value ?? const [];
  final analyzer = ref.watch(conditionAnalyzerProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final slots = buildSleepDaySlots(
    records: records,
    from: today.subtract(const Duration(days: kRecentSleepCoverageDays - 1)),
    to: today,
    analyzer: analyzer,
  );
  return RecentSleepCoverage(
    trackedDays: slots.length,
    daysWithSleep: slots.where((s) => !s.isEmpty).length,
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

/// 스펙 17장 "야간근무 후 평균 수면" 등 - analyzer/기록이 없으면 null.
class SleepShiftRelationSummary {
  final ShiftSleepStat afterNight;
  final ShiftSleepStat afterDayOrEvening;
  final ShiftSleepStat onOffDay;
  final double? averageNapMinutes;

  const SleepShiftRelationSummary({
    required this.afterNight,
    required this.afterDayOrEvening,
    required this.onOffDay,
    required this.averageNapMinutes,
  });
}

// ⭐ 2026-09-01 - "실제 수면 기록이 있으면 오늘의 컨디션 문구를 그걸로 다듬어달라"
// 요청으로 추가. 오늘의 회복구간(어제 근무 종료~오늘/다음 근무 시작)과 겹치는
// 확정(CONFIRMED) 수면 기록을 찾는다 - sleep_condition_extras.dart의 순수 비교
// 함수와 짝을 이룸. 없으면 null(그 경우 화면은 기존처럼 이론적 권장 수면
// 시간대만 보여줌 - ConditionRuleEngine은 이 provider를 전혀 모름, 완전 분리
// 원칙 그대로).
final todayRecoverySleepProvider = Provider<SleepRecord?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  if (analyzer == null) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final window = analyzer.recoveryWindowContaining(today);
  if (window == null) return null;

  final records = ref.watch(sleepRecordProvider).value ?? const [];

  SleepRecord? best;
  for (final r in records) {
    if (r.status != SleepStatus.confirmed) continue;
    final end = r.end;
    if (end == null) continue;
    // sleep_shift_relation.dart와 동일한 스타일의 구간 겹침 판정.
    final overlaps = r.start.isBefore(window.start) && end.isAfter(window.end);
    if (!overlaps) continue;
    if (best == null || (r.durationMinutes ?? 0) > (best.durationMinutes ?? 0)) {
      best = r;
    }
  }
  return best;
});

// ⭐ 2026-09-01 - "오늘의 컨디션 예측"(킬러 기능, 컨디션매니저_설계.md 12장)의
// 데이터 준비 provider들. 최근 최대 28일(≈4주)의 근무-수면 짝을 만들고
// (sleep_history.dart), 근무명별 "평소 패턴"을 계산한 뒤, today_forecast_engine.dart가
// 우선순위 기반으로 문구 하나를 골라낸다. ConditionRuleEngine은 baseResult로만
// 읽기 참조하고 수정하지 않음(완전 분리 원칙 유지).
final recentWorkNightsProvider = Provider<List<SleepHistoryNight>>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  if (analyzer == null) return const [];
  final records = ref.watch(sleepRecordProvider).value ?? const [];
  final now = DateTime.now();
  return collectRecentWorkNights(
    analyzer: analyzer,
    records: records,
    referenceDate: DateTime(now.year, now.month, now.day),
  );
});

final personalSleepPatternsProvider = Provider<Map<String, PersonalSleepPattern>>((ref) {
  final nights = ref.watch(recentWorkNightsProvider);
  return buildPersonalSleepPatterns(nights);
});

// ⭐ 2026-09-04 v2 - recentOvertimeMinutesProvider는 condition_provider.dart로
// 옮김(ConditionRuleEngine의 RULE_WEEKLY_OVERTIME도 이제 이 데이터가 필요해져서
// 더 기반 레이어로 이동 - 이 파일은 아래에서 condition_provider.dart를 통해
// 그대로 재사용).

final todayForecastProvider = Provider<TodayForecast?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  final baseResult = ref.watch(todayConditionResultProvider);
  if (analyzer == null || baseResult == null) return null;
  final nights = ref.watch(recentWorkNightsProvider);
  final patterns = ref.watch(personalSleepPatternsProvider);
  final otMinutes = ref.watch(recentOvertimeMinutesProvider).value ?? const {};
  final now = DateTime.now();
  return buildTodayForecast(
    baseResult: baseResult,
    analyzer: analyzer,
    nights: nights,
    personalPatterns: patterns,
    otMinutesByDate: otMinutes,
    today: DateTime(now.year, now.month, now.day),
  );
});

// ⭐ 2026-09-01 후속10 - "오늘의 컨디션 점수"(0~100, 사용자 명시 요청 -
// condition_score.dart 상단 주석 참고). todayForecastProvider와 같은 입력을
// 재사용하되, 최근 평균 수면(분)과 "로테이션 스케줄인지"만 추가로 계산.
// ⭐ 후속21 - 이 창도 condition_score.dart의 _kScoreWindowDays(=7,
// today_forecast_engine.dart의 _kFatigueWindowDays와 동일)와 맞춤 - 원래 5일로
// 따로 하드코딩돼 있었는데, 점수 내부 계산은 7일 창을 쓰면서 "수면 데이터
// 완전성" 비율만 5일 기준으로 넘기면 같은 점수 안에서 "최근"의 정의가
// 어긋나 보임(그 팩터의 doc comment도 원래부터 _kScoreWindowDays 기준이라고
// 되어 있었음).
final conditionScoreProvider = Provider<ConditionScoreResult?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  final baseResult = ref.watch(todayConditionResultProvider);
  final schedule = ref.watch(scheduleProvider).value;
  if (analyzer == null || baseResult == null || schedule == null) return null;
  final nights = ref.watch(recentWorkNightsProvider);
  final otMinutes = ref.watch(recentOvertimeMinutesProvider).value ?? const {};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final windowStart = today.subtract(const Duration(days: 6)); // 오늘 포함 7일
  // ⭐ 2026-09-01 후속12 - recentWorkNightsProvider(=collectRecentWorkNights)가
  // 이제 휴무/미배정일도 빠짐없이 반환하므로(sleep_history.dart 버그 수정
  // 참고), windowDays는 이 7일 창에 실제로 걸리는 날짜 수를 그대로 세면 됨
  // (전에는 근무일만 있어서 7일 미만일 수 있었지만 이제 항상 7).
  final windowDays = nights.where((n) => !n.date.isBefore(windowStart) && !n.date.isAfter(today)).toList();
  final recentSleep = windowDays.where((n) => n.hasSleepData);
  final avgSleep = recentSleep.isEmpty
      ? null
      : recentSleep.fold<int>(0, (sum, n) => sum + n.sleepMinutes!) / recentSleep.length;

  final isRotating = conditionRelevantShiftNames(schedule).length > 1;

  return computeConditionScore(
    baseResult: baseResult,
    analyzer: analyzer,
    today: today,
    otMinutesByDate: otMinutes,
    avgRecentSleepMinutes: avgSleep,
    isRotatingSchedule: isRotating,
    recentSleepTrackedDays: windowDays.length,
    recentSleepDaysWithData: recentSleep.length,
  );
});

final sleepShiftRelationSummaryProvider = Provider<SleepShiftRelationSummary?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  final records = ref.watch(sleepRecordProvider).value;
  if (analyzer == null || records == null) return null;

  final now = DateTime.now();
  return SleepShiftRelationSummary(
    afterNight: computePostInstanceSleepStat(
      analyzer: analyzer,
      records: records,
      referenceDate: now,
      matches: isNightShiftInstance,
    ),
    afterDayOrEvening: computePostInstanceSleepStat(
      analyzer: analyzer,
      records: records,
      referenceDate: now,
      matches: isDayOrEveningShiftInstance,
    ),
    onOffDay: computePostInstanceSleepStat(
      analyzer: analyzer,
      records: records,
      referenceDate: now,
      matches: isOffDayInstance,
      searchAheadHours: 24,
    ),
    averageNapMinutes: computeAverageNapMinutes(analyzer: analyzer, records: records, referenceDate: now),
  );
});
