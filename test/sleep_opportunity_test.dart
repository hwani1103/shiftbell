// test/sleep_opportunity_test.dart
//
// ⭐ 2026-09-06(사용자 논의) - "그 외(주간/오후/휴무)"는 무조건 21시부터 창이
// 열리다 보니, 21시를 넘겨 끝나는 주간/오후 근무(예: 12시간 주간 10~22시)에서
// 아직 근무 중에 창이 열려버리는 구멍이 있었다. "21시와 실제 종료시각 중 더
// 늦은 쪽"으로 고친 걸 검증(SleepScheduleResolver.kt도 동일하게 고쳤으나
// Kotlin은 별도 계측 없이는 유닛테스트하기 어려워 Dart 쪽만 검증).

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_opportunity.dart';

const _kDay = '주간';
const _kOff = '휴무';

void main() {
  final today = DateTime(2026, 9, 6);
  // now = 06시 - 아직 오늘 창이 시작 전(미래)이라 반환된 window.start를 그대로
  // "오늘의 창 시작 시각"으로 관찰할 수 있음.
  final now = DateTime(today.year, today.month, today.day, 6);

  ShiftPatternAnalyzer buildAnalyzer(ShiftTimeRange dayRange) {
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: [_kDay, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff],
      todayIndex: 0,
      startDate: today,
      shiftTypes: const [_kDay, _kOff],
    );
    return ShiftPatternAnalyzer(
      schedule: schedule,
      shiftTimes: {_kDay: dayRange},
    );
  }

  test('1. 주간 07~19시(21시 이전 퇴근) - 창은 그대로 21시부터(회귀 확인)', () {
    final analyzer = buildAnalyzer(
      const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60),
    );
    final window = sleepOpportunityWindowFor(now, analyzer: analyzer);
    expect(window, isNotNull);
    expect(window!.start, DateTime(today.year, today.month, today.day, 21),
        reason: '평소처럼 21시 이전에 끝나는 주간은 21시 고정이 그대로 맞음');
  });

  test('2. 주간 10~22시(21시를 넘겨 끝나는 12시간 근무) - 창이 실제 퇴근(22시)까지 밀려야 함', () {
    final analyzer = buildAnalyzer(
      const ShiftTimeRange(shiftName: _kDay, startMinutes: 10 * 60, endMinutes: 22 * 60),
    );
    final window = sleepOpportunityWindowFor(now, analyzer: analyzer);
    expect(window, isNotNull);
    expect(window!.start, DateTime(today.year, today.month, today.day, 22),
        reason: '21시 고정이면 아직 근무 중(22시 퇴근)인데 창이 열려버림 - 실제 퇴근시각까지 밀려야 함');
  });

  test('3. 휴무일 - 비교할 종료시각이 없으니 그대로 21시', () {
    final offDay = today.add(const Duration(days: 1));
    final nowOnOffDay = DateTime(offDay.year, offDay.month, offDay.day, 6);
    final analyzer = buildAnalyzer(
      const ShiftTimeRange(shiftName: _kDay, startMinutes: 10 * 60, endMinutes: 22 * 60),
    );
    final window = sleepOpportunityWindowFor(nowOnOffDay, analyzer: analyzer);
    expect(window, isNotNull);
    expect(window!.start, DateTime(offDay.year, offDay.month, offDay.day, 21),
        reason: '휴무일은 근무 종료시각 자체가 없으니 21시 그대로');
  });
}
