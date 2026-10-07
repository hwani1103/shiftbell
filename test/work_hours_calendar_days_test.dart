import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/work_hours_settings_provider.dart';
import 'package:shiftbell/services/work_hours_calculator.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();
  const zones = [
    'America/New_York',
    'America/Los_Angeles',
    'America/Phoenix',
    'Pacific/Honolulu',
    'Europe/London',
    'Europe/Berlin',
    'Africa/Johannesburg',
    'Asia/Manila',
    'Asia/Dubai',
    'America/Sao_Paulo',
    'America/Rio_Branco',
    'Asia/Kolkata',
    'Asia/Seoul',
    'Australia/Lord_Howe'
  ];

  for (final row in [
    ('Europe/Berlin', 3, 28),
    ('Europe/Berlin', 10, 24),
    ('Europe/London', 3, 28),
    ('Europe/London', 10, 24),
    ('America/New_York', 3, 7),
    ('America/New_York', 10, 31),
    ('Australia/Lord_Howe', 4, 4),
    ('Australia/Lord_Howe', 10, 3)
  ]) {
    test('DST ${row.$1} ${row.$2}: every date exactly once, including last day',
        () {
      final zone = tz.getLocation(row.$1);
      final start = tz.TZDateTime(zone, 2026, row.$2, row.$3, 23, 59);
      final end = tz.TZDateTime(zone, 2026, row.$2, row.$3 + 2, 0, 1);
      final assigned = <String, String>{};
      final ot = <String, int>{};
      for (var i = 0; i < 3; i++) {
        final key = dateKey(DateTime.utc(2026, row.$2, row.$3 + i));
        assigned[key] = 'Day';
        ot[key] = (i + 1) * 10;
      }
      final schedule = ShiftSchedule(
          isRegular: false,
          shiftTypes: const ['Day'],
          assignedDates: assigned,
          shiftDurations: const {'Day': 480});
      final summary = computeWeekSummary(
          schedule: schedule, weekStart: start, weekEnd: end, otByDate: ot);
      expect(summary.shiftDayCounts, {'Day': 3});
      expect(summary.shiftMinutes, 1440);
      expect(summary.otMinutes, 60);
      expect(summary.totalMinutes, 1500);
      final midnightSummary = computeWeekSummary(
          schedule: schedule,
          weekStart: tz.TZDateTime(zone, 2026, row.$2, row.$3),
          weekEnd: tz.TZDateTime(zone, 2026, row.$2, row.$3 + 2),
          otByDate: ot);
      expect(midnightSummary.shiftDayCounts, {'Day': 3});
      expect(midnightSummary.totalMinutes, 1500);
      expect(
          computeTotalWorkMinutes(
              schedule: schedule, start: start, end: end, otByDate: ot),
          1500);
      final entries = computeOtDisplayEntries(
          schedule: schedule,
          start: start,
          end: end,
          manualOtByDate: ot,
          countShiftChangeAsOt: true);
      expect(entries.map((e) => dateKey(e.date)), ot.keys);
      expect(entries.map((e) => e.manualMinutes), [10, 20, 30]);
      expect(computeOtDisplayTotal(entries), 60);
    });
  }

  for (final zoneName in zones) {
    test(
        '$zoneName all months 2024/2026/2027/2028 agree with independent date ledger',
        () {
      final zone = tz.getLocation(zoneName);
      for (final year in [2024, 2026, 2027, 2028]) {
        for (var month = 1; month <= 12; month++) {
          final count = DateTime.utc(year, month + 1, 0).day;
          final assignments = <String, String>{};
          final ot = <String, int>{};
          var expected = 0;
          for (var day = 1; day <= count; day++) {
            final key = dateKey(DateTime.utc(year, month, day));
            final shift = day % 3 == 0 ? 'Off' : 'Day';
            if (day % 7 != 0) {
              assignments[key] = shift;
              expected += shift == 'Day' ? 480 : 0;
            }
            if (day % 2 == 0) {
              ot[key] = day;
              expected += day;
            }
          }
          final schedule = ShiftSchedule(
              isRegular: false,
              shiftTypes: const ['Day', 'Off'],
              assignedDates: assignments,
              shiftDurations: const {'Day': 480, 'Off': 0});
          final start = tz.TZDateTime(zone, year, month, 1, 12);
          final end = tz.TZDateTime(zone, year, month, count, 6);
          expect(
              computeTotalWorkMinutes(
                  schedule: schedule, start: start, end: end, otByDate: ot),
              expected,
              reason: '$year-$month');
          final summary = computeWeekSummary(
              schedule: schedule, weekStart: start, weekEnd: end, otByDate: ot);
          expect(summary.totalMinutes, expected, reason: '$year-$month');
          expect(summary.shiftDayCounts.values.fold(0, (a, b) => a + b),
              assignments.length);
          final entries = computeOtDisplayEntries(
              schedule: schedule,
              start: start,
              end: end,
              manualOtByDate: ot,
              countShiftChangeAsOt: true);
          expect(entries.map((e) => dateKey(e.date)), ot.keys);
          expect(computeOtDisplayTotal(entries),
              ot.values.fold(0, (a, b) => a + b));

          final weeks = weeksCoveringMonth(start);
          final covered = <String>[];
          for (final week in weeks) {
            expect(week.start.weekday, DateTime.monday);
            expect(week.end.weekday, DateTime.sunday);
            final a =
                DateTime.utc(week.start.year, week.start.month, week.start.day);
            final b = DateTime.utc(week.end.year, week.end.month, week.end.day);
            expect(b.difference(a).inDays, 6);
            for (var i = 0; i < 7; i++) {
              covered.add(dateKey(a.add(Duration(days: i))));
            }
          }
          final first = DateTime.utc(year, month, 1);
          final last = DateTime.utc(year, month, count);
          final oracleStart = first.subtract(Duration(days: first.weekday - 1));
          final oracleEnd = last.add(Duration(days: 7 - last.weekday));
          final oracle = [
            for (var i = 0; i <= oracleEnd.difference(oracleStart).inDays; i++)
              dateKey(oracleStart.add(Duration(days: i)))
          ];
          expect(covered, oracle);
          expect(covered.toSet().length, covered.length);
        }
      }
    });
  }

  test(
      'shift-change OT is optional display detail, never double-counted in work total',
      () {
    final schedule = ShiftSchedule(
        isRegular: true,
        shiftTypes: const ['Day', 'Night', 'Off', 'Short'],
        pattern: const ['Off', 'Day', 'Night', 'Day'],
        todayIndex: 0,
        startDate: DateTime(2026, 3, 28),
        assignedDates: const {
          '2026-03-28': 'Night',
          '2026-03-29': 'Short',
          '2026-03-30': 'Night',
          '2026-03-31': 'Off'
        },
        shiftDurations: const {
          'Day': 480,
          'Night': 720,
          'Off': 0,
          'Short': 240
        });
    final a = DateTime(2026, 3, 28), b = DateTime(2026, 3, 31);
    const manual = {'2026-03-28': 30, '2026-03-29': 60, '2026-03-31': 15};
    final off = computeOtDisplayEntries(
        schedule: schedule,
        start: a,
        end: b,
        manualOtByDate: manual,
        countShiftChangeAsOt: false);
    final on = computeOtDisplayEntries(
        schedule: schedule,
        start: a,
        end: b,
        manualOtByDate: manual,
        countShiftChangeAsOt: true);
    expect(computeOtDisplayTotal(off), 105);
    expect(computeOtDisplayTotal(on), 825);
    expect(on.first.impliedMinutes, 720);
    expect(on.first.fromShift, 'Off');
    expect(on.first.toShift, 'Night');
    expect(on.skip(1).every((e) => !e.hasImplied), isTrue);
    expect(
        computeTotalWorkMinutes(
            schedule: schedule, start: a, end: b, otByDate: manual),
        1785);
    expect(
        computeWeekSummary(
                schedule: schedule, weekStart: a, weekEnd: b, otByDate: manual)
            .totalMinutes,
        1785);
  });

  test(
      'same date, reversed dates, unset shift, leap day, year and payday boundaries',
      () {
    final schedule = ShiftSchedule(isRegular: false, shiftTypes: const [
      'Day'
    ], assignedDates: const {
      '2028-02-29': 'Day',
      '2027-12-31': 'Day',
      '2028-01-01': 'Day'
    }, shiftDurations: const {
      'Day': 480
    });
    final cases = [
      (DateTime(2028, 2, 29, 23), DateTime(2028, 2, 29, 1), 510),
      (DateTime(2028, 3, 1), DateTime(2028, 2, 29), 0),
      (DateTime(2027, 12, 31), DateTime(2028, 1, 1), 990)
    ];
    const ot = {'2028-02-29': 30, '2028-01-01': 30};
    for (final c in cases) {
      expect(
          computeTotalWorkMinutes(
              schedule: schedule, start: c.$1, end: c.$2, otByDate: ot),
          c.$3);
      expect(
          computeWeekSummary(
                  schedule: schedule,
                  weekStart: c.$1,
                  weekEnd: c.$2,
                  otByDate: ot)
              .totalMinutes,
          c.$3);
    }
    for (final anchor in PaydayCutoffAnchor.values) {
      for (final cutoff in [1, 20, 28, 29, 30, 31]) {
        final settings = WorkHoursSettings(
            periodMode: MonthlyPeriodMode.payday,
            paydayCutoffDay: cutoff,
            cutoffAnchor: anchor);
        for (final month in [
          DateTime(2028, 2),
          DateTime(2028, 3),
          DateTime(2028, 1)
        ]) {
          final range = settings.periodForMonth(month);
          final keys = ot.keys.where((k) =>
              k.compareTo(dateKey(range.start)) >= 0 &&
              k.compareTo(dateKey(range.end)) <= 0);
          final expectedOt = keys.fold(0, (n, k) => n + ot[k]!);
          final entries = computeOtDisplayEntries(
              schedule: schedule,
              start: range.start,
              end: range.end,
              manualOtByDate: ot,
              countShiftChangeAsOt: false);
          expect(computeOtDisplayTotal(entries), expectedOt);
        }
      }
    }
  });
}
