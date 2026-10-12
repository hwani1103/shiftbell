/// Resolve a device-local wall clock consistently with Android's alarm parser:
/// gaps move forward by the offset change; overlaps use the later occurrence.
/// [wall] carries calendar fields, not an instant. No DB format is changed.
DateTime resolveAlarmWallTime(DateTime wall,
    {DateTime Function(int)? localFromEpoch}) {
  final local = localFromEpoch ??
      (int millis) => DateTime.fromMillisecondsSinceEpoch(millis);
  final fields = DateTime.utc(wall.year, wall.month, wall.day, wall.hour,
      wall.minute, wall.second, wall.millisecond, wall.microsecond);
  final epoch = fields.millisecondsSinceEpoch;
  // Sample both sides of modern DST transitions, including 30-minute changes.
  final offsets = {-2, 0, 2}
      .map((days) =>
          local(epoch + days * Duration.millisecondsPerDay).timeZoneOffset)
      .toSet();
  final exact = <DateTime>[];
  final forward = <DateTime>[];
  for (final offset in offsets) {
    final candidate = local(epoch - offset.inMilliseconds);
    final candidateFields = DateTime.utc(
        candidate.year,
        candidate.month,
        candidate.day,
        candidate.hour,
        candidate.minute,
        candidate.second,
        candidate.millisecond);
    final delta = candidateFields.millisecondsSinceEpoch - epoch;
    if (delta == 0) exact.add(candidate);
    if (delta > 0) forward.add(candidate);
  }
  if (exact.isNotEmpty) {
    exact.sort((a, b) => a.compareTo(b));
    return exact.last.add(Duration(microseconds: wall.microsecond));
  }
  forward.sort((a, b) => a.compareTo(b));
  return forward.first.add(Duration(microseconds: wall.microsecond));
}

DateTime parseAlarmDate(String value,
    {DateTime Function(int)? localFromEpoch}) {
  final parsed = DateTime.parse(value);
  if (parsed.isUtc)
    return localFromEpoch?.call(parsed.millisecondsSinceEpoch) ??
        parsed.toLocal();
  // Parse fields in UTC first: a local DateTime constructor may already have
  // normalized a nonexistent 02:30 before our shared gap policy sees it.
  return resolveAlarmWallTime(DateTime.parse('${value}Z'),
      localFromEpoch: localFromEpoch);
}

DateTime? tryParseAlarmDate(String? value) {
  if (value == null) return null;
  try {
    return parseAlarmDate(value);
  } on FormatException {
    return null;
  }
}

/// Preserve the instant when a snooze row is written back by Flutter.
String alarmInstantForStorage(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  final minutes = local.timeZoneOffset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final hours = (minutes.abs() ~/ 60).toString().padLeft(2, '0');
  final rest = (minutes.abs() % 60).toString().padLeft(2, '0');
  final fields = DateTime.utc(local.year, local.month, local.day, local.hour,
          local.minute, local.second, local.millisecond, local.microsecond)
      .toIso8601String();
  return '${fields.substring(0, fields.length - 1)}$sign$hours:$rest';
}

/// 0 = ordinary clock time, 1/2 = first/second occurrence of a repeated time.
int alarmClockOccurrence(DateTime value) {
  final before = value.subtract(const Duration(days: 2)).timeZoneOffset;
  final after = value.add(const Duration(days: 2)).timeZoneOffset;
  if (before <= after) return 0;
  final delta = before - after;
  final other =
      value.timeZoneOffset == before ? value.add(delta) : value.subtract(delta);
  if (other.year != value.year ||
      other.month != value.month ||
      other.day != value.day ||
      other.hour != value.hour ||
      other.minute != value.minute) return 0;
  return value.isBefore(other) ? 1 : 2;
}
