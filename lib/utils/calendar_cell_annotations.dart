import '../models/shift_schedule.dart';
import '../services/work_hours_calculator.dart';

/// Reuse the monthly OT definition; cache per immutable schedule/provider map.
class CalendarDayOvertime {
  CalendarDayOvertime(this.schedule, this.manual, this.countShiftChanges);
  final ShiftSchedule schedule;
  final Map<String, int> manual;
  final bool countShiftChanges;
  final _days = <String, int>{};

  int minutesFor(DateTime day) => _days.putIfAbsent(dateKey(day), () {
        final extra = countShiftChanges
            ? impliedOvertimeForDate(schedule, day)?.minutes ?? 0
            : 0;
        return (manual[dateKey(day)] ?? 0) + extra;
      });
}

/// Wednesday first, then nearest weekdays. Never move a sample to a weekend.
/// Construct calendar dates instead of adding 24h across daylight-saving time.
DateTime? calendarLunarLabelDate(DateTime day,
    {required bool Function(DateTime) hasHoliday,
    required bool Function(DateTime) hasOvertime}) {
  final sunday = day.day - day.weekday % 7;
  for (final offset in const [3, 2, 4, 1, 5]) {
    final candidate = DateTime(day.year, day.month, sunday + offset);
    if (!hasHoliday(candidate) && !hasOvertime(candidate)) return candidate;
  }
  return null;
}

List<String> calendarOvertimeLabels(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  final parts = [
    if (hours > 0) '${hours}h',
    if (remainder > 0) '${remainder}m'
  ];
  final spaced = parts.join(' '), tight = parts.join();
  return ['+ $spaced', '+$spaced', '+$tight', tight];
}
