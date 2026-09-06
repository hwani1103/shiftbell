// lib/services/condition/sleep_stats.dart
//
// ⭐ 실제 수면 기록과 근무 일정의 관계 통계(스펙 17장 "야간근무 후 평균 수면" 등).
// 순수 계산만 하는 파일 - ConditionRuleEngine과는 무관하게 독립적으로 존재한다
// (수면기록_자동추정_설계.md 5장 "Sleep Detection과 Shift Health Engine 분리" 원칙).
// UI(condition_tab.dart)가 이 값들을 별도 섹션에서 보여줄 뿐, 상태 판정(🟢/🟡/🔴)에는
// 전혀 관여하지 않는다.

import '../../models/sleep_record.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';
import 'sleep_opportunity.dart';
import 'sleep_shift_relation.dart';

class ShiftSleepStat {
  final int sampleCount;
  final int totalMinutes;
  const ShiftSleepStat({required this.sampleCount, required this.totalMinutes});

  double? get averageMinutes => sampleCount == 0 ? null : totalMinutes / sampleCount;
}

bool isNightShiftInstance(ShiftInstance i) => i.category == ShiftTimeCategory.night;
bool isDayOrEveningShiftInstance(ShiftInstance i) =>
    i.category == ShiftTimeCategory.day || i.category == ShiftTimeCategory.evening;
bool isOffDayInstance(ShiftInstance i) => i.isOff;

/// [referenceDate] 기준 최근 [lookbackDays]일 동안 [matches]에 해당하는 근무(또는
/// 휴무)들 각각에 대해, 그 종료 이후 [searchAheadHours] 이내에 시작하는 "주 수면"
/// (mainSleep으로 분류되는) 기록 중 가장 이른 것의 길이를 표본으로 모아 평균을 낸다.
/// 아직 사용자 확인 전(PENDING_CONFIRMATION)인 자동 감지 기록은 표본에서 제외 -
/// "추정"일 뿐 확정 데이터가 아니므로 통계에 섞지 않는다.
ShiftSleepStat computePostInstanceSleepStat({
  required ShiftPatternAnalyzer analyzer,
  required List<SleepRecord> records,
  required DateTime referenceDate,
  required bool Function(ShiftInstance instance) matches,
  int lookbackDays = 30,
  int searchAheadHours = 16,
}) {
  var sampleCount = 0;
  var totalMinutes = 0;

  final confirmedRecords =
      records.where((r) => !(r.source == SleepSource.autoDetected && r.status == SleepStatus.pendingConfirmation));

  for (var i = 0; i < lookbackDays; i++) {
    final day = referenceDate.subtract(Duration(days: i));
    final inst = analyzer.instanceForDate(day);
    if (!matches(inst) || inst.end == null) continue;

    // ⭐ 2026-09-05 - graceAdjustedShiftEnd 참고(sleep_day_slots.dart/
    // sleep_shift_relation.dart와 동일 원칙) - 실제 퇴근이 설정보다 조금 이르면
    // "아직 근무 중"으로 오판정해서 이 근무 뒤 수면 표본에서 누락되는 걸 방지.
    // searchAheadHours 상한선 자체는 여전히 실제 설정 종료 시각(inst.end) 기준.
    final effectiveEnd = graceAdjustedShiftEnd(inst);
    SleepRecord? nearest;
    for (final r in confirmedRecords) {
      if (r.durationMinutes == null) continue;
      if (r.start.isBefore(effectiveEnd)) continue;
      // ⭐ 2026-09-06 - .inHours truncate 버그 수정(sleep_day_slots.dart/
      // sleep_history.dart와 동일 이유) - Duration 직접 비교로 교체.
      if (r.start.difference(inst.end!) > Duration(hours: searchAheadHours)) continue;
      if (classifySleepRelation(r, analyzer) != SleepRelation.mainSleep) continue;
      if (nearest == null || r.start.isBefore(nearest.start)) nearest = r;
    }

    if (nearest != null) {
      sampleCount++;
      totalMinutes += nearest.durationMinutes!;
    }
  }

  return ShiftSleepStat(sampleCount: sampleCount, totalMinutes: totalMinutes);
}

/// 최근 [days]일 동안의 낮잠(nap 분류) 평균 길이(분). 표본 없으면 null.
double? computeAverageNapMinutes({
  required ShiftPatternAnalyzer analyzer,
  required List<SleepRecord> records,
  required DateTime referenceDate,
  int days = 30,
}) {
  final cutoff = referenceDate.subtract(Duration(days: days));
  var count = 0;
  var total = 0;
  for (final r in records) {
    if (r.source == SleepSource.autoDetected && r.status == SleepStatus.pendingConfirmation) continue;
    if (r.durationMinutes == null) continue;
    if (r.start.isBefore(cutoff)) continue;
    if (classifySleepRelation(r, analyzer) != SleepRelation.nap) continue;
    count++;
    total += r.durationMinutes!;
  }
  return count == 0 ? null : total / count;
}
