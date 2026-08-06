// lib/services/work_hours_calculator.dart
//
// ⭐ "총 근로(예정) 시간" / "주별 근무시간" 계산 전용 순수 로직 모음. 위젯과
// 무관하게 스케줄(ShiftSchedule) + OT(Map<'YYYY-MM-DD', 분>)만 있으면 계산
// 가능하도록 분리함 - 달력탭 팝업 2곳(월 누적 OT, 주별 근무시간)에서 재사용.

import 'package:flutter/material.dart';
import '../models/shift_schedule.dart';

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ⭐ 기간(start~end, 둘 다 포함) 동안의 "근무시간 합계"(분) = 각 날짜에 배정된
// 근무의 기본 근로시간 합 + 그 기간의 OT 합계(분). 근무일 변경(달력에서 꾹 눌러
// 변경한 assignedDates)도 schedule.getShiftForDate()가 이미 반영하므로 자동으로
// 따라감 - 별도 캐시나 저장 없이 항상 그 자리에서 다시 계산함.
int computeTotalWorkMinutes({
  required ShiftSchedule schedule,
  required DateTime start,
  required DateTime end,
  required Map<String, int> otByDate,
}) {
  int total = 0;
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  for (var d = startDay; !d.isAfter(endDay); d = d.add(const Duration(days: 1))) {
    final shift = schedule.getShiftForDate(d);
    if (shift != '미설정') {
      total += schedule.getDurationMinutes(shift);
    }
    total += otByDate[dateKey(d)] ?? 0;
  }
  return total;
}

// ⭐ 한 주(월~일)의 근무 요약
class WeekWorkSummary {
  final DateTime start;  // 월요일
  final DateTime end;    // 일요일
  final Map<String, int> shiftDayCounts;  // 근무명 -> 그 주에 며칠(0인 건 제외)
  final int shiftMinutes;  // 근무시간 합(OT 제외)
  final int otMinutes;

  WeekWorkSummary({
    required this.start,
    required this.end,
    required this.shiftDayCounts,
    required this.shiftMinutes,
    required this.otMinutes,
  });

  int get totalMinutes => shiftMinutes + otMinutes;
}

// ⭐ month(연/월만 사용)가 속한 달을 완전히 덮는 월~일 주 단위 범위 목록.
// 그 달 1일이 속한 주의 월요일부터, 말일이 속한 주의 일요일까지 - 앞뒤로 다른
// 달의 날짜가 며칠 포함되는 건 의도된 동작 (달력에 보이는 6번째 줄과 동일한 개념).
List<DateTimeRange> weeksCoveringMonth(DateTime month) {
  final firstDay = DateTime(month.year, month.month, 1);
  final lastDay = DateTime(month.year, month.month + 1, 0);

  // DateTime.weekday: 월=1 ... 일=7
  final firstMonday = firstDay.subtract(Duration(days: firstDay.weekday - 1));
  final lastSunday = lastDay.add(Duration(days: 7 - lastDay.weekday));

  final weeks = <DateTimeRange>[];
  var weekStart = firstMonday;
  while (!weekStart.isAfter(lastSunday)) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    weeks.add(DateTimeRange(start: weekStart, end: weekEnd));
    weekStart = weekStart.add(const Duration(days: 7));
  }
  return weeks;
}

// ⭐ 특정 주(월~일) 하나의 근무 요약 계산
WeekWorkSummary computeWeekSummary({
  required ShiftSchedule schedule,
  required DateTime weekStart,
  required DateTime weekEnd,
  required Map<String, int> otByDate,
}) {
  final counts = <String, int>{};
  int shiftMinutes = 0;
  int otMinutes = 0;

  for (var d = weekStart; !d.isAfter(weekEnd); d = d.add(const Duration(days: 1))) {
    final shift = schedule.getShiftForDate(d);
    if (shift != '미설정') {
      counts[shift] = (counts[shift] ?? 0) + 1;
      shiftMinutes += schedule.getDurationMinutes(shift);
    }
    otMinutes += otByDate[dateKey(d)] ?? 0;
  }

  return WeekWorkSummary(
    start: weekStart,
    end: weekEnd,
    shiftDayCounts: counts,
    shiftMinutes: shiftMinutes,
    otMinutes: otMinutes,
  );
}
