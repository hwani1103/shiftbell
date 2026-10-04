import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/condition/english_recovery_summary.dart';
import 'package:shiftbell/services/condition/english_sleep_copy.dart';

EnglishRecoverySummary summary({
  DateTime? currentEnd,
  DateTime? nextStart,
  DateTime? lastEnd,
  bool pending = false,
  bool afterNight = false,
  bool beforeNight = false,
}) =>
    EnglishRecoverySummary(
      currentShiftEnd: currentEnd,
      nextShiftStart: nextStart,
      lastShiftEnd: lastEnd,
      betweenShifts: null,
      recordedSleepAfterLastShift: null,
      hasPendingEstimate: pending,
      recentlyFinishedNightShift: afterNight,
      approachingNightShift: beforeNight,
    );

void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('durations and record counts read naturally at zero, one and many', () {
    expect(EnglishSleepCopy.duration(Duration.zero), '0 min');
    expect(EnglishSleepCopy.duration(const Duration(minutes: 35)), '35 min');
    expect(EnglishSleepCopy.duration(const Duration(hours: 1)), '1 hr');
    expect(EnglishSleepCopy.duration(const Duration(hours: 2, minutes: 5)),
        '2 hr 5 min');
    expect(EnglishSleepCopy.weekTotal(Duration.zero, 0),
        'No confirmed sleep recorded in the past 7 days.');
    expect(EnglishSleepCopy.weekTotal(const Duration(hours: 6), 1),
        '6 hr of confirmed sleep across 1 record.');
    expect(EnglishSleepCopy.weekTotal(const Duration(hours: 8), 2),
        '8 hr of confirmed sleep across 2 records.');
    expect(EnglishSleepCopy.sinceLastShift(Duration.zero),
        'No confirmed sleep recorded since your last shift.');
    expect(EnglishSleepCopy.sinceLastShift(const Duration(hours: 4)),
        'Confirmed sleep since your last shift: 4 hr');
  });

  test('missing work hours and pending estimates have honest explanations', () {
    expect(EnglishSleepCopy.guidance(null, now), [
      'Add work hours in Settings to connect your shifts with your sleep records.'
    ]);
    expect(EnglishSleepCopy.guidance(summary(pending: true), now), [
      'Add work hours in Settings to see your shift times here.',
      'Review the sleep estimates below. They are not included in your totals until you confirm them.',
    ]);
  });

  test('night-shift messages and next-shift message do not contradict', () {
    expect(
        EnglishSleepCopy.guidance(
            summary(
              lastEnd: now.subtract(const Duration(hours: 4)),
              nextStart: now.add(const Duration(hours: 5)),
              afterNight: true,
              beforeNight: true,
            ),
            now),
        [
          'After a night shift, allow time to sleep and recover when you can.',
          'If you can, rest or take a nap before your night shift.',
        ]);
  });

  test('generic advice appears only before a near shift, not days early', () {
    expect(
        EnglishSleepCopy.guidance(
            summary(nextStart: now.add(const Duration(hours: 12))), now),
        ['If you can, leave enough time to sleep before your next shift.']);
    expect(
        EnglishSleepCopy.guidance(
            summary(nextStart: now.add(const Duration(days: 4))), now),
        isEmpty);
    expect(
        EnglishSleepCopy.guidance(
            summary(
              currentEnd: now.add(const Duration(hours: 4)),
              nextStart: now.add(const Duration(hours: 20)),
            ),
            now),
        isEmpty);
  });
}
