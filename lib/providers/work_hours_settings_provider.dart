// lib/providers/work_hours_settings_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ⭐ "이번 달 총 근로시간"을 어느 기간 기준으로 합산할지 - 달력 월(1~말일) 또는
// 급여 산정일 기준. 전역 설정이라(스케줄과 무관) SharedPreferences에 저장함 -
// 테마 설정과 동일한 패턴.
enum MonthlyPeriodMode { calendar, payday }

// ⭐ 회사마다 "기준일"을 기간의 어느 쪽으로 보는지가 다름 (예: 기준일 20일일 때)
// - periodEnd: 기준일이 기간의 마지막 날 → 전월 21일 ~ 당월 20일
// - periodStart: 기준일이 기간의 시작일 → 전월 20일 ~ 당월 19일
// - bothInclusive: 기준일을 시작/끝 둘 다에 포함 → 전월 20일 ~ 당월 20일
enum PaydayCutoffAnchor { periodEnd, periodStart, bothInclusive }

class WorkHoursSettings {
  final MonthlyPeriodMode periodMode;
  final int paydayCutoffDay;  // 1~31. payday 모드에서만 사용
  final PaydayCutoffAnchor cutoffAnchor;
  // ⭐ 달력에서 근무를 바꿔서(예: 휴무→주간) 원래 패턴보다 늘어난 시간을 "이번 달
  // OT"에 자동으로 합산할지. 기본값 false(기존 동작 유지) - 근무 변경이 잦은
  // 사람은 그걸 OT로 안 치고 싶을 수 있어서 명시적으로 켜야 적용됨.
  final bool shiftChangeCountsAsOt;

  const WorkHoursSettings({
    this.periodMode = MonthlyPeriodMode.calendar,
    this.paydayCutoffDay = 25,
    this.cutoffAnchor = PaydayCutoffAnchor.periodEnd,
    this.shiftChangeCountsAsOt = false,
  });

  WorkHoursSettings copyWith({
    MonthlyPeriodMode? periodMode,
    int? paydayCutoffDay,
    PaydayCutoffAnchor? cutoffAnchor,
    bool? shiftChangeCountsAsOt,
  }) {
    return WorkHoursSettings(
      periodMode: periodMode ?? this.periodMode,
      paydayCutoffDay: paydayCutoffDay ?? this.paydayCutoffDay,
      cutoffAnchor: cutoffAnchor ?? this.cutoffAnchor,
      shiftChangeCountsAsOt: shiftChangeCountsAsOt ?? this.shiftChangeCountsAsOt,
    );
  }

  static int _lastDayOfMonth(DateTime anyDayInMonth) {
    return DateTime(anyDayInMonth.year, anyDayInMonth.month + 1, 0).day;
  }

  // ⭐ anchorMonth(연/월만 사용)를 "당월"로 보고, 이번 달 집계 기간을 계산함.
  // 세 방식 모두 기간이 anchorMonth 안에서 "끝나는" 것으로 라벨링함 (급여명세서에
  // 찍히는 달 = 정산이 마무리되는 달이라는 관행에 맞춤).
  // - calendar 모드: 당월 1일 ~ 당월 말일 (기존 동작 그대로)
  // - periodEnd (기준일=마지막 날): 전월 (기준일+1)일 ~ 당월 기준일
  // - periodStart (기준일=시작일): 전월 기준일 ~ 당월 (기준일-1)일
  // - bothInclusive (기준일을 양쪽 다 포함): 전월 기준일 ~ 당월 기준일
  // - 기준일이 그 달 실제 일수보다 크면(예: 31일인데 그 달이 30일까지) 그 달의
  //   마지막 날로 자동 보정됨 - 사용자가 "말일"을 따로 고를 필요 없음.
  DateTimeRange periodForMonth(DateTime anchorMonth) {
    if (periodMode == MonthlyPeriodMode.calendar) {
      final start = DateTime(anchorMonth.year, anchorMonth.month, 1);
      final end = DateTime(anchorMonth.year, anchorMonth.month + 1, 0);
      return DateTimeRange(start: start, end: end);
    }

    final currentMonth = DateTime(anchorMonth.year, anchorMonth.month);
    final currentLastDay = _lastDayOfMonth(currentMonth);
    final prevMonth = DateTime(anchorMonth.year, anchorMonth.month - 1);
    final prevLastDay = _lastDayOfMonth(prevMonth);

    switch (cutoffAnchor) {
      case PaydayCutoffAnchor.periodEnd:
        final endDay = paydayCutoffDay.clamp(1, currentLastDay);
        final end = DateTime(currentMonth.year, currentMonth.month, endDay);

        final startDayRaw = paydayCutoffDay.clamp(1, prevLastDay) + 1;
        final start = startDayRaw > prevLastDay
            ? DateTime(currentMonth.year, currentMonth.month, 1)  // 기준일이 전월 말일이면 다음날=당월 1일
            : DateTime(prevMonth.year, prevMonth.month, startDayRaw);

        return DateTimeRange(start: start, end: end);

      case PaydayCutoffAnchor.periodStart:
        final startDay = paydayCutoffDay.clamp(1, prevLastDay);
        final start = DateTime(prevMonth.year, prevMonth.month, startDay);

        final endDayRaw = paydayCutoffDay.clamp(1, currentLastDay) - 1;
        final end = endDayRaw < 1
            ? DateTime(prevMonth.year, prevMonth.month, prevLastDay)  // 기준일이 1일이면 전달 말일까지
            : DateTime(currentMonth.year, currentMonth.month, endDayRaw);

        return DateTimeRange(start: start, end: end);

      case PaydayCutoffAnchor.bothInclusive:
        final startDay = paydayCutoffDay.clamp(1, prevLastDay);
        final start = DateTime(prevMonth.year, prevMonth.month, startDay);
        final endDay = paydayCutoffDay.clamp(1, currentLastDay);
        final end = DateTime(currentMonth.year, currentMonth.month, endDay);

        return DateTimeRange(start: start, end: end);
    }
  }

  String periodLabel(DateTime anchorMonth) {
    final range = periodForMonth(anchorMonth);
    final s = range.start;
    final e = range.end;
    final sy = s.year % 100;
    final ey = e.year % 100;
    if (s.year == e.year) {
      return '$sy년 ${s.month}/${s.day} ~ ${e.month}/${e.day} 기준';
    }
    return '$sy년 ${s.month}/${s.day} ~ $ey년 ${e.month}/${e.day} 기준';
  }

  // ⭐ 설정 화면 미리보기용 - 연도/"기준" 접미사 없이 짧게 "7/21 ~ 8/20" 형태만
  String periodRangeShort(DateTime anchorMonth) {
    final range = periodForMonth(anchorMonth);
    final s = range.start;
    final e = range.end;
    return '${s.month}/${s.day} ~ ${e.month}/${e.day}';
  }
}

class WorkHoursSettingsNotifier extends StateNotifier<WorkHoursSettings> {
  WorkHoursSettingsNotifier() : super(const WorkHoursSettings()) {
    _load();
  }

  static const _modeKey = 'work_hours_period_mode';
  static const _cutoffKey = 'work_hours_payday_cutoff_day';
  static const _cutoffAnchorKey = 'work_hours_cutoff_anchor';
  // ⭐ 예전(3방식 도입 이전) bool 설정 키 - 남아있으면 값 승계해서 마이그레이션
  static const _legacyCutoffIsStartKey = 'work_hours_cutoff_is_period_start';
  static const _shiftChangeAsOtKey = 'work_hours_shift_change_as_ot';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_modeKey);
    final cutoff = prefs.getInt(_cutoffKey) ?? 25;
    final mode = modeStr == 'payday' ? MonthlyPeriodMode.payday : MonthlyPeriodMode.calendar;
    final shiftChangeAsOt = prefs.getBool(_shiftChangeAsOtKey) ?? false;

    PaydayCutoffAnchor anchor;
    final anchorStr = prefs.getString(_cutoffAnchorKey);
    if (anchorStr != null) {
      anchor = PaydayCutoffAnchor.values.firstWhere(
        (a) => a.name == anchorStr,
        orElse: () => PaydayCutoffAnchor.periodEnd,
      );
    } else {
      // 마이그레이션: 예전 bool 설정이 있었다면 그 값을 승계
      final legacyIsStart = prefs.getBool(_legacyCutoffIsStartKey);
      anchor = legacyIsStart == true ? PaydayCutoffAnchor.periodStart : PaydayCutoffAnchor.periodEnd;
    }

    state = WorkHoursSettings(
      periodMode: mode,
      paydayCutoffDay: cutoff,
      cutoffAnchor: anchor,
      shiftChangeCountsAsOt: shiftChangeAsOt,
    );
  }

  Future<void> setPeriodMode(MonthlyPeriodMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode == MonthlyPeriodMode.payday ? 'payday' : 'calendar');
    state = state.copyWith(periodMode: mode);
  }

  Future<void> setPaydayCutoffDay(int day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cutoffKey, day);
    state = state.copyWith(paydayCutoffDay: day);
  }

  Future<void> setCutoffAnchor(PaydayCutoffAnchor anchor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cutoffAnchorKey, anchor.name);
    state = state.copyWith(cutoffAnchor: anchor);
  }

  Future<void> setShiftChangeCountsAsOt(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shiftChangeAsOtKey, value);
    state = state.copyWith(shiftChangeCountsAsOt: value);
  }
}

final workHoursSettingsProvider =
    StateNotifierProvider<WorkHoursSettingsNotifier, WorkHoursSettings>(
  (ref) => WorkHoursSettingsNotifier(),
);
