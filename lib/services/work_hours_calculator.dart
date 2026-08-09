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

// ⭐⭐ "근무변경으로 인한 OT" 관련 계산 ⭐⭐
//
// 달력에서 근무를 바꾸면(예: 휴무→주간) assignedDates에 예외로 저장되고,
// getShiftForDate()가 이걸 우선 반영해서 "월별/주별 총 근무시간"엔 이미 새
// 근무(주간 12시간)의 전체 시간이 정상적으로 들어감 - 이 계산은 이 기능과
// 무관하게 항상 그대로 유지됨(중복 합산 없음).
//
// 여기서 추가하는 건 별개로, "이번 달 OT" 표시(카드/팝업의 합계·목록)에만
// 쓰이는 계산임: 원래 패턴대로였다면 몇 시간이었을지(patternShift 기준)와
// 실제 배정된 시간(actualShift 기준)의 차이(늘어난 만큼만, 음수는 0으로
// clamp)를 "근무변경으로 늘어난 시간"으로 보고, 설정에서 켜져 있으면 그 날의
// 수동 OT(date_overtime)에 더해서 "이번 달 OT"에 얹어 보여줌.

// ⭐ 특정 날짜의 "근무변경으로 늘어난 시간" 정보. 패턴과 실제가 같거나(변경
// 없음), 실제가 패턴보다 짧거나 같으면(늘어난 게 없으면) null.
class ImpliedOvertime {
  final int minutes;
  final String fromShift;  // 원래 패턴상 근무
  final String toShift;    // 실제로 바뀐 근무

  const ImpliedOvertime({required this.minutes, required this.fromShift, required this.toShift});
}

ImpliedOvertime? impliedOvertimeForDate(ShiftSchedule schedule, DateTime date) {
  // ⭐ 불규칙 스케줄은 "원래 패턴"이라는 기준 자체가 없어서 이 개념이 성립하지 않음
  if (!schedule.isRegular) return null;

  final patternShift = schedule.getPatternShiftForDate(date);
  if (patternShift.isEmpty) return null;

  final actualShift = schedule.getShiftForDate(date);
  if (actualShift == patternShift) return null;  // 변경 없음

  final patternMinutes = schedule.getDurationMinutes(patternShift);
  final actualMinutes = schedule.getDurationMinutes(actualShift);
  final delta = actualMinutes - patternMinutes;
  if (delta <= 0) return null;  // 오히려 줄었거나 그대로면 OT로 안 침

  return ImpliedOvertime(minutes: delta, fromShift: patternShift, toShift: actualShift);
}

// ⭐ "이번 달 OT" 목록/카드에 표시할 날짜별 항목 - 수동 OT + (설정 켜져 있으면)
// 근무변경으로 늘어난 시간을 합친 값. 팝업 안의 OT 토글(수동 입력 UI) 자체는
// 이 값과 무관하게 항상 순수 수동 OT만 보여줌 - 이 클래스는 오직 "이번 달 OT"
// 요약 화면 전용.
class OtDisplayEntry {
  final DateTime date;
  final int manualMinutes;
  final int impliedMinutes;
  final String? fromShift;  // impliedMinutes > 0일 때만 값 있음
  final String? toShift;

  const OtDisplayEntry({
    required this.date,
    required this.manualMinutes,
    required this.impliedMinutes,
    this.fromShift,
    this.toShift,
  });

  int get totalMinutes => manualMinutes + impliedMinutes;
  bool get hasImplied => impliedMinutes > 0;
}

// ⭐ 기간(start~end) 동안의 "이번 달 OT" 목록. 수동 OT가 없어도 근무변경으로
// 늘어난 시간이 있으면(설정 켜진 경우) 항목에 포함됨 - 그래서 date_overtime
// 테이블 기반 getRangeEntries()와 달리 기간 내 모든 날짜를 순회함.
List<OtDisplayEntry> computeOtDisplayEntries({
  required ShiftSchedule schedule,
  required DateTime start,
  required DateTime end,
  required Map<String, int> manualOtByDate,
  required bool countShiftChangeAsOt,
}) {
  final result = <OtDisplayEntry>[];
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);

  for (var d = startDay; !d.isAfter(endDay); d = d.add(const Duration(days: 1))) {
    final manual = manualOtByDate[dateKey(d)] ?? 0;
    final implied = countShiftChangeAsOt ? impliedOvertimeForDate(schedule, d) : null;
    final impliedMinutes = implied?.minutes ?? 0;
    if (manual <= 0 && impliedMinutes <= 0) continue;

    result.add(OtDisplayEntry(
      date: d,
      manualMinutes: manual,
      impliedMinutes: impliedMinutes,
      fromShift: implied?.fromShift,
      toShift: implied?.toShift,
    ));
  }
  return result;
}

int computeOtDisplayTotal(List<OtDisplayEntry> entries) {
  var total = 0;
  for (final e in entries) {
    total += e.totalMinutes;
  }
  return total;
}
