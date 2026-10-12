import '../../models/sleep_record.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';

/// Schedule facts and modest, evidence-backed guidance for the English tab.
/// This does not translate Korean prose or infer a diagnosis from missing data.
class EnglishRecoverySummary {
  final DateTime? currentShiftEnd;
  final DateTime? nextShiftStart;
  final DateTime? lastShiftEnd;
  final Duration? betweenShifts;
  final Duration? recordedSleepAfterLastShift;
  final bool hasPendingEstimate;
  final bool recentlyFinishedNightShift;
  final bool approachingNightShift;

  const EnglishRecoverySummary({
    required this.currentShiftEnd,
    required this.nextShiftStart,
    required this.lastShiftEnd,
    required this.betweenShifts,
    required this.recordedSleepAfterLastShift,
    required this.hasPendingEstimate,
    required this.recentlyFinishedNightShift,
    required this.approachingNightShift,
  });
}

EnglishRecoverySummary buildEnglishRecoverySummary({
  required ShiftPatternAnalyzer analyzer,
  required List<SleepRecord> records,
  required DateTime now,
}) {
  final day = DateTime(now.year, now.month, now.day);
  ShiftInstance? current;
  ShiftInstance? last;
  ShiftInstance? next;
  // Use calendar construction: adding 24 hours can skip a local date at DST.
  for (var offset = -14; offset <= 14; offset++) {
    final shift = analyzer.instanceForDate(
      DateTime(day.year, day.month, day.day + offset),
    );
    if (shift.start == null || shift.end == null || !shift.isWorkDay) {
      continue;
    }
    if (!now.isBefore(shift.start!) && now.isBefore(shift.end!)) {
      current = shift;
    }
    if (!shift.end!.isAfter(now) &&
        (last == null || shift.end!.isAfter(last.end!))) {
      last = shift;
    }
    if (shift.start!.isAfter(now) &&
        (next == null || shift.start!.isBefore(next.start!))) {
      next = shift;
    }
  }

  Duration? recordedSleep;
  if (last != null) {
    final intervals = <({DateTime start, DateTime end})>[];
    for (final record in records) {
      if (record.status != SleepStatus.confirmed || record.end == null) {
        continue;
      }
      final start = record.start.isAfter(last.end!) ? record.start : last.end!;
      final end = record.end!.isBefore(now) ? record.end! : now;
      if (end.isAfter(start)) intervals.add((start: start, end: end));
    }
    intervals.sort((a, b) => a.start.compareTo(b.start));
    var minutes = 0;
    DateTime? countedUntil;
    for (final interval in intervals) {
      final start = countedUntil != null && countedUntil.isAfter(interval.start)
          ? countedUntil
          : interval.start;
      if (interval.end.isAfter(start)) {
        minutes += interval.end.difference(start).inMinutes;
      }
      if (countedUntil == null || interval.end.isAfter(countedUntil)) {
        countedUntil = interval.end;
      }
    }
    recordedSleep = Duration(minutes: minutes);
  }

  return EnglishRecoverySummary(
    currentShiftEnd: current?.end,
    nextShiftStart: next?.start,
    lastShiftEnd: current == null ? last?.end : null,
    betweenShifts: current == null &&
            last != null &&
            next != null &&
            next.start!.isAfter(last.end!)
        ? next.start!.difference(last.end!)
        : null,
    recordedSleepAfterLastShift: current == null ? recordedSleep : null,
    hasPendingEstimate: records.any(
      (record) => record.status == SleepStatus.pendingConfirmation,
    ),
    recentlyFinishedNightShift: current == null &&
        last?.category == ShiftTimeCategory.night &&
        now.difference(last!.end!) <= const Duration(hours: 16),
    approachingNightShift: next?.category == ShiftTimeCategory.night &&
        next!.start!.difference(now) <= const Duration(hours: 6),
  );
}
