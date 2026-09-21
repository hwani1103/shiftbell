// lib/services/condition/sleep_by_category_stats.dart
//
// ⭐ P2 #6(2026-09-18, 사용자 요청) - "근무 종류별 평균 수면" 인사이트. 야간/주간/
// 오후 근무 뒤나 휴무일에 실제로 얼마나 자는지 - 근무표와 실제 수면 기록을 둘 다
// 가진 이 앱만 만들 수 있는 정보(사용자 표현: "이게 있어야 기록할 이유가 생긴다").
//
// ⚠️ 반드시 buildSleepDaySlots()가 이미 검증된 _attributedDay 귀속 규칙(야간 근무
// 다음날 아침 회복수면은 그 야간 근무일로 귀속 등, 2026-09-18 재검토 완료 - CLAUDE.md
// "설계 기록 › 수면 기록" 참고)을 그대로 재사용한다 - 여기서 귀속 로직을 다시
// 구현하지 않는다. 새로운 점수화·등급화는 하지 않는다(컨디션 매니저 원칙 3 참고).

import '../../models/sleep_record.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';
import 'sleep_day_slots.dart';

/// 표본이 이 개수 미만인 카테고리는 결과에서 뺀다(recovery_briefing_engine.dart의
/// avgRecent가 쓰는 "기록한 날 3일 이상"과 동일 기준 - 근거 부족한 평균을 "평균"이라고
/// 말하지 않기 위함).
const int kMinSampleDaysForCategoryAverage = 3;

/// 통계 조회 기간(일). 30일이면 흔한 3~4조 교대 사이클(6~9일 주기)이 3~5바퀴는
/// 들어와 카테고리별 표본이 웬만하면 쌓이면서도, 너무 길면 스케줄이 바뀌기 전의
/// 오래된 데이터까지 섞이는 걸 피할 수 있는 절충(연구값 아닌 화면 구성용 관례값).
const int kCategoryStatsLookbackDays = 30;

class SleepCategoryAverage {
  final ShiftTimeCategory category;
  final int averageMinutes;
  final int sampleDays;
  const SleepCategoryAverage({required this.category, required this.averageMinutes, required this.sampleDays});
}

int _slotTotal(SleepDaySlots s) =>
    (s.mainSleep?.durationMinutes ?? 0) + (s.nap1?.durationMinutes ?? 0) + (s.nap2?.durationMinutes ?? 0);

/// [now] 기준 최근 [lookbackDays]일(오늘은 아직 끝나지 않아 제외 - recovery_briefing_
/// engine.dart의 최근 7일 평균 수면과 동일 관례)의 수면을, 그 수면이 "귀속된" 날짜
/// (buildSleepDaySlots의 _attributedDay - 예: 야간 근무 다음날 아침 회복수면은 그
/// 야간 근무일로 귀속됨)의 근무 카테고리별로 묶어 평균 수면시간을 낸다.
List<SleepCategoryAverage> buildSleepCategoryAverages({
  required List<SleepRecord> records,
  required ShiftPatternAnalyzer analyzer,
  required DateTime now,
  int lookbackDays = kCategoryStatsLookbackDays,
  int minSampleDays = kMinSampleDaysForCategoryAverage,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(Duration(days: lookbackDays));
  final to = today.subtract(const Duration(days: 1));
  if (to.isBefore(from)) return const [];

  final slots = buildSleepDaySlots(records: records, from: from, to: to, analyzer: analyzer);

  final totalsByCategory = <ShiftTimeCategory, List<int>>{};
  for (final slot in slots) {
    final total = _slotTotal(slot);
    if (total <= 0) continue;
    final category = analyzer.instanceForDate(slot.date).category;
    (totalsByCategory[category] ??= []).add(total);
  }

  final result = <SleepCategoryAverage>[];
  for (final entry in totalsByCategory.entries) {
    if (entry.value.length < minSampleDays) continue;
    final avg = (entry.value.reduce((a, b) => a + b) / entry.value.length).round();
    result.add(SleepCategoryAverage(category: entry.key, averageMinutes: avg, sampleDays: entry.value.length));
  }

  // 화면 표시 순서 - 근무 흐름 순(주간→오후→야간)으로 보여주고 휴무를 마지막에.
  const order = [ShiftTimeCategory.day, ShiftTimeCategory.evening, ShiftTimeCategory.night, ShiftTimeCategory.off];
  result.sort((a, b) => order.indexOf(a.category).compareTo(order.indexOf(b.category)));
  return result;
}
