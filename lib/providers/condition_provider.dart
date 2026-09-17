// lib/providers/condition_provider.dart
//
// ⭐ 컨디션 매니저 - ShiftSchedule(기존) + condition_shift_times(신규)을 조합해
// ShiftPatternAnalyzer/ConditionRuleEngine을 돌리는 Provider들. 기존
// scheduleProvider는 watch만 하고 전혀 수정하지 않음(컨디션매니저_설계.md 9장).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../services/condition/condition_rule_engine.dart';
import '../services/condition/shift_pattern_analyzer.dart';
import '../services/database_service.dart';
import '../utils/shift_name_util.dart';
import 'condition_shift_time_provider.dart';
import 'current_date_provider.dart';
import 'data_revision_provider.dart';
import 'schedule_provider.dart';

/// 실제로 출퇴근 시각을 입력받아야 하는 근무명 목록(휴무 제외).
List<String> conditionRelevantShiftNames(ShiftSchedule schedule) {
  final names = schedule.activeShiftTypes ?? schedule.shiftTypes;
  return names.where((n) => !isRestShiftName(n)).toList();
}

/// ⭐ 2026-09-01 - 원래는 "사용 중인 근무명 전부"에 출퇴근 시각이 있어야
/// 컨디션 탭이 동작했는데(하나라도 비면 true), 사용자 요청으로 완화함:
/// **한 근무라도 시각이 입력돼 있으면** 그걸 기반으로 판정을 내림(ShiftPatternAnalyzer가
/// 시각 없는 근무를 만나면 알아서 더 앞/뒤 날짜를 탐색하므로 부분 입력도
/// 안전하게 동작함 - shift_pattern_analyzer.dart의 recoveryWindowContaining
/// 참고). 그래서 이 provider의 의미도 "설정이 더 필요하다"가 아니라 "단 하나도
/// 입력된 게 없다"로 바뀜(이름은 호환성 위해 그대로 유지).
/// 입력 자체는 이제 이 탭이 아니라 설정 → 근무시간 및 OT 설정에서 함
/// (work_hours_settings_screen.dart) - 스케줄 자체가 없으면(온보딩 전) false -
/// 그건 이 탭이 아니라 InitialRouter가 처리할 상태라 컨디션 탭에서 또
/// 안내하지 않음.
final conditionSetupNeededProvider = Provider<bool>((ref) {
  ref.watch(dataRevisionProvider(DataDomain.shiftSchedule));
  ref.watch(dataRevisionProvider(DataDomain.shiftTimes));
  final schedule = ref.watch(scheduleProvider).value;
  if (schedule == null) return false;
  final times = ref.watch(conditionShiftTimeProvider).value;
  if (times == null) return true; // 로딩 중엔 일단 설정 필요로 취급(깜빡임 방지)
  final names = conditionRelevantShiftNames(schedule);
  // 입력할 대상(근무일)이 아예 없으면(전부 휴무 등 극단적 케이스) 막을 이유가
  // 없음 - 원래도 이 경우엔 그냥 통과시켰음(값을 유지).
  if (names.isEmpty) return false;
  return names.every((n) => !times.containsKey(n));
});

// ⭐ "C번"(실제 수면 기록) 쪽에서 근무 인스턴스 계산을 재사용해야 해서(수면-근무
// 겹침 분류, 근무 후 평균 수면 통계) public으로 노출함 - 그 전에는 이 파일
// 안에서만 쓰던 private provider였음.
final conditionAnalyzerProvider = Provider<ShiftPatternAnalyzer?>((ref) {
  ref.watch(dataRevisionProvider(DataDomain.shiftSchedule));
  ref.watch(dataRevisionProvider(DataDomain.shiftTimes));
  final schedule = ref.watch(scheduleProvider).value;
  final times = ref.watch(conditionShiftTimeProvider).value;
  if (schedule == null || times == null) return null;
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
});

// ⭐ 2026-09-01 후속5 - "최근 5일 실측 피로도" 축(today_forecast_engine.dart)이
// 쓰는 실제 초과근무(OT) 데이터. 달력 탭이 미리 로드해둔 overtimeProvider 캐시에
// 기대지 않고 직접 불러온다(컨디션 탭을 달력 없이 바로 열어도 항상 정확하게
// 반영되도록) - 엔진의 창(최근 7일)보다 여유 있게 잡음.
// ⭐ 2026-09-04 v2 - 원래 sleep_condition_provider.dart에 있었는데, 이제
// ConditionRuleEngine 자체(RULE_WEEKLY_TOTAL_LOAD, 2026-09-17까지는 RULE_WEEKLY_OVERTIME)도
// 이 데이터가 필요해져서 더 기반 레이어인 이 파일로 옮김 - sleep_condition_provider.dart는
// 이미 이 파일을 import하고 있어서 그대로 재사용 가능(순환 import 방지).
final recentOvertimeMinutesProvider = FutureProvider<Map<String, int>>((ref) async {
  // G1은 date_overtime 저장이 성공한 뒤에만 이 revision을 올린다. 따라서
  // OT 추가/수정/삭제는 DB를 다시 읽고, 실패/롤백은 현재 계산을 유지한다.
  ref.watch(dataRevisionProvider(DataDomain.overtime));
  // ⭐ 2026-09-15 (AUD-05) - 자정·앱 재개 때 바뀌는 "오늘"을 구독(current_date_provider.dart)
  final today = ref.watch(currentDateProvider);
  final start = today.subtract(const Duration(days: 6));
  return DatabaseService.instance.getOvertimeForRange(start, today);
});

/// "오늘"(기기 시각 기준) 컨디션 결과. 근무시간 설정이 안 됐거나 스케줄이 없으면 null.
final todayConditionResultProvider = Provider<ConditionResult?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  if (analyzer == null) return null;
  // ⭐ 2026-09-15 (AUD-05) - 자정·앱 재개 때 바뀌는 "오늘"을 구독. 예전엔 생성 시점 날짜가 캐시에 남아
  // 앱을 밤부터 다음 날까지 살려 두면 전날 기준 판정이 계속 보였음
  final today = ref.watch(currentDateProvider);
  // ⭐ 2026-09-04 v2, 2026-09-17 재설계 - RULE_WEEKLY_TOTAL_LOAD(EVIDENCE-012/014)가
  // 실제 판정에 쓰이도록 OT 데이터를 같이 넘김(기본근무 합산은 엔진이 analyzer로 직접
  // 계산). FutureProvider라 로딩 중엔 빈 맵으로 취급(그 사이엔 OT 부분만 0으로 취급돼
  // 총량이 과소평가되고, 로딩 끝나면 자동 재계산됨 - conditionScoreProvider가 이미 쓰던
  // 것과 동일한 패턴).
  final otMinutes = ref.watch(recentOvertimeMinutesProvider).value ?? const {};
  return ConditionRuleEngine(analyzer).evaluate(
    today,
    otMinutesByDate: otMinutes,
  );
});

/// 이번 주(월~일) 패턴 요약.
final currentWeekSummaryProvider = Provider<WeeklyPatternSummary?>((ref) {
  final analyzer = ref.watch(conditionAnalyzerProvider);
  if (analyzer == null) return null;
  // ⭐ 2026-09-15 (AUD-05) - 자정·앱 재개 때 바뀌는 "오늘"을 구독(current_date_provider.dart)
  final today = ref.watch(currentDateProvider);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  return analyzer.weeklySummary(weekStart);
});
