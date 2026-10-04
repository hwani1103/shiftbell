import 'english_recovery_summary.dart';

/// User-facing English copy for the sleep screen's data-dependent states.
class EnglishSleepCopy {
  const EnglishSleepCopy._();

  static String duration(Duration value) {
    final minutes = value.inMinutes;
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest min';
    if (rest == 0) return '$hours hr';
    return '$hours hr $rest min';
  }

  static String weekTotal(Duration value, int count) {
    if (count == 0) return 'No confirmed sleep recorded in the past 7 days.';
    final noun = count == 1 ? 'record' : 'records';
    return '${duration(value)} of confirmed sleep across $count $noun.';
  }

  static String sinceLastShift(Duration value) => value == Duration.zero
      ? 'No confirmed sleep recorded since your last shift.'
      : 'Confirmed sleep since your last shift: ${duration(value)}';

  static List<String> guidance(EnglishRecoverySummary? summary, DateTime now) {
    if (summary == null) {
      return [
        'Add work hours in Settings to connect your shifts with your sleep records.'
      ];
    }
    final lines = <String>[];
    if (summary.currentShiftEnd == null &&
        summary.nextShiftStart == null &&
        summary.lastShiftEnd == null) {
      lines.add('Add work hours in Settings to see your shift times here.');
    }
    if (summary.hasPendingEstimate) {
      lines.add(
          'Review the sleep estimates below. They are not included in your totals until you confirm them.');
    }
    if (summary.recentlyFinishedNightShift) {
      lines.add(
          'After a night shift, allow time to sleep and recover when you can.');
    }
    if (summary.approachingNightShift) {
      lines.add('If you can, rest or take a nap before your night shift.');
    } else if (summary.currentShiftEnd == null &&
        summary.nextShiftStart != null &&
        summary.nextShiftStart!.difference(now) <= const Duration(hours: 24)) {
      lines.add(
          'If you can, leave enough time to sleep before your next shift.');
    }
    return lines;
  }
}
