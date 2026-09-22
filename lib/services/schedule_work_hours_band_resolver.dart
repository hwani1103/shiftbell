// lib/services/schedule_work_hours_band_resolver.dart
//
// ⭐ 2026-09-22 - 일정관리 탭의 "근무시간 반투명 영역" 계산. 순수 함수 -
// 이 날짜(date)에 실제로 보여줄 근무시간 구간(들)을 계산한다.
//
// 자정을 넘기는 근무(예: 야간 19:00~07:00)는 "오늘 배정된 근무"만 봐서는
// 절반만 보인다 - 오늘 19시에 시작한 야간은 오늘 축(19:00~24:00)에 한
// 조각만 그려지고, 그 다음날 새벽(00:00~07:00) 몫은 "다음날 축"에서
// "어제 배정된 근무가 자정을 넘겨 들어왔다"는 걸 따로 확인해야 나온다.
// 그래서 이 함수는 항상 두 날짜(date 자신 + date-1)를 함께 본다:
//  - date 자신의 근무: 자정을 넘기면 [start, 24:00)만, 안 넘기면 [start, end)
//    전체를 오늘 몫으로.
//  - date-1(어제)의 근무: 자정을 넘길 때만 그 [0, end) 부분이 "오늘 새벽"
//    몫으로 넘어온다(어제 몫 [start, 24:00)는 어제 날짜를 봤을 때 이미
//    그려졌으므로 여기서는 안 그림).
// 휴무/미배정(kUnsetShiftSentinel, isRestShiftName)이거나 출퇴근 시각이
// 설정 안 된 근무는 그 날짜분만 조용히 건너뛴다(근거 없으면 표시 안 함).

import 'package:flutter/material.dart';
import '../models/schedule_work_hours_band.dart';
import '../models/shift_schedule.dart';
import '../models/shift_time_range.dart';
import '../theme/app_colors.dart';
import '../utils/shift_name_util.dart';

bool _isRealShift(String name) =>
    name != kUnsetShiftSentinel && name.isNotEmpty && !isRestShiftName(name);

List<ScheduleWorkHoursBand> resolveScheduleWorkHoursBands({
  required DateTime date,
  required ShiftSchedule? schedule,
  required Map<String, ShiftTimeRange>? shiftTimes,
  required Map<String, Color> shiftColors,
}) {
  if (schedule == null || shiftTimes == null || shiftTimes.isEmpty) {
    return const [];
  }
  final bands = <ScheduleWorkHoursBand>[];

  final todayName = schedule.getShiftForDate(date);
  if (_isRealShift(todayName)) {
    final range = shiftTimes[todayName];
    if (range != null) {
      bands.add(ScheduleWorkHoursBand(
        startMinutes: range.startMinutes,
        endMinutes: range.crossesMidnight ? 24 * 60 : range.endMinutes,
        shiftName: todayName,
        color: shiftColors[todayName] ?? kAppMainAccent,
      ));
    }
  }

  final yesterday = date.subtract(const Duration(days: 1));
  final yesterdayName = schedule.getShiftForDate(yesterday);
  if (_isRealShift(yesterdayName)) {
    final range = shiftTimes[yesterdayName];
    if (range != null && range.crossesMidnight && range.endMinutes > 0) {
      bands.add(ScheduleWorkHoursBand(
        startMinutes: 0,
        endMinutes: range.endMinutes,
        shiftName: yesterdayName,
        color: shiftColors[yesterdayName] ?? kAppMainAccent,
      ));
    }
  }

  return bands;
}
