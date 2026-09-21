// test/sleep_by_category_stats_test.dart
//
// ⭐ P2 #6(2026-09-18) - "근무 종류별 평균 수면" 순수 계산 회귀 테스트. 핵심 검증
// 포인트는 buildSleepDaySlots()가 이미 검증된 _attributedDay 귀속(야간 근무 다음날
// 아침 회복수면은 그 야간 근무일=night 카테고리로 집계돼야 함 - 2026-09-18
// 수면 귀속 로직 재검토에서 확인된 규칙, CLAUDE.md 참고)을 이 통계도 그대로
// 따르는지다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/shift_time_category.dart';
import 'package:shiftbell/services/condition/sleep_by_category_stats.dart';

const _kNight = '야간';
const _kOff = '휴무';

SleepRecord _sleep(DateTime start, int minutes) =>
    SleepRecord(start: start, end: start.add(Duration(minutes: minutes)), source: SleepSource.manual, status: SleepStatus.confirmed);

void main() {
  test('야간 근무 다음날 아침 회복수면은 night 카테고리로, 휴무일 밤잠은 off 카테고리로 집계된다', () {
    // 야간(22~06시)/휴무 2일 주기를 15바퀴(30일) 반복. 각 야간 근무 다음날 아침에
    // 5시간 회복수면(→ 그 야간 근무일로 귀속돼야 함), 각 휴무일 밤 10시에 7시간
    // 정상 취침(→ 그 휴무일 자신의 것으로 귀속돼야 함)을 기록한다.
    final start = DateTime(2026, 3, 1); // pattern index0 = 야간
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: [_kNight, _kOff],
      todayIndex: 0,
      startDate: start,
      shiftTypes: [_kNight, _kOff],
    );
    final times = {_kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60)};
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);

    final now = start.add(const Duration(days: 30));
    final records = <SleepRecord>[];
    for (var i = 0; i < 30; i += 2) {
      final offDay = start.add(Duration(days: i + 1)); // 직전 날(i)이 야간 근무
      records.add(_sleep(offDay.add(const Duration(hours: 7)), 300)); // 야간 퇴근 후 아침 회복수면(5h)
      records.add(_sleep(offDay.add(const Duration(hours: 22)), 420)); // 휴무일 밤 정상 취침(7h)
    }

    final averages = buildSleepCategoryAverages(records: records, analyzer: analyzer, now: now);

    final night = averages.firstWhere((a) => a.category == ShiftTimeCategory.night);
    final off = averages.firstWhere((a) => a.category == ShiftTimeCategory.off);
    expect(night.averageMinutes, 300, reason: '야간 다음날 아침 회복수면이 night 카테고리 평균에 반영돼야 함');
    expect(off.averageMinutes, 420, reason: '휴무일 밤 정상 취침이 off 카테고리 평균에 반영돼야 함');
    expect(night.sampleDays, greaterThanOrEqualTo(kMinSampleDaysForCategoryAverage));
    expect(off.sampleDays, greaterThanOrEqualTo(kMinSampleDaysForCategoryAverage));
    expect(averages.any((a) => a.category == ShiftTimeCategory.day), isFalse);
  });

  test('표본이 최소 기준(3일) 미만인 카테고리는 결과에서 빠진다', () {
    final start = DateTime(2026, 3, 1);
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: [_kNight, _kOff],
      todayIndex: 0,
      startDate: start,
      shiftTypes: [_kNight, _kOff],
    );
    final times = {_kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60)};
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
    final now = start.add(const Duration(days: 30));

    // 휴무일 밤잠만 2건 기록(3건 미만) - night 카테고리는 표본이 하나도 없음.
    final records = [
      _sleep(start.add(const Duration(days: 1, hours: 22)), 420),
      _sleep(start.add(const Duration(days: 3, hours: 22)), 420),
    ];
    final averages = buildSleepCategoryAverages(records: records, analyzer: analyzer, now: now);
    expect(averages, isEmpty, reason: '표본 2건은 최소 기준(3일) 미만이라 아무 카테고리도 안 보여야 함');
  });
}
