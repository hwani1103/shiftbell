/// A calendar date represented by UTC fields, NOT the UTC conversion of an
/// instant. Date-keyed schedules and OT must not gain/lose dates across DST.
DateTime calendarDateFields(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

/// Both endpoint dates are included; time of day/offset is deliberately ignored.
/// A reversed date range is empty. UTC is internal arithmetic only.
Iterable<DateTime> calendarDaysInclusive(DateTime start, DateTime end) sync* {
  final last = calendarDateFields(end);
  for (var day = calendarDateFields(start);
      !day.isAfter(last);
      day = DateTime.utc(day.year, day.month, day.day + 1)) {
    yield day;
  }
}

/// Keep existing local-date output contracts without converting UTC midnight
/// into a different local calendar date.
DateTime localCalendarDate(DateTime fields) =>
    DateTime(fields.year, fields.month, fields.day);
