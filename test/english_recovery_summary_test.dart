import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/english_recovery_summary.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';

void main() {
  final analyzer = ShiftPatternAnalyzer(
    schedule: ShiftSchedule(
      isRegular: true,
      pattern: ['Night', '휴무'],
      todayIndex: 0,
      shiftTypes: ['Night', '휴무'],
      startDate: DateTime(2026, 9, 24),
    ),
    shiftTimes: const {
      'Night': ShiftTimeRange(
        shiftName: 'Night',
        startMinutes: 19 * 60,
        endMinutes: 7 * 60,
      ),
    },
  );

  test('night-shift guidance uses confirmed overlap, not pending estimates',
      () {
    final now = DateTime(2026, 9, 25, 14);
    final summary = buildEnglishRecoverySummary(
      analyzer: analyzer,
      now: now,
      records: [
        SleepRecord(
          start: DateTime(2026, 9, 25, 8),
          end: DateTime(2026, 9, 25, 12),
          source: SleepSource.manual,
          status: SleepStatus.confirmed,
        ),
        SleepRecord(
          start: DateTime(2026, 9, 25, 12),
          end: DateTime(2026, 9, 25, 13),
          source: SleepSource.autoDetected,
          status: SleepStatus.pendingConfirmation,
        ),
      ],
    );
    expect(summary.lastShiftEnd, DateTime(2026, 9, 25, 7));
    expect(summary.nextShiftStart, DateTime(2026, 9, 26, 19));
    expect(summary.betweenShifts, const Duration(hours: 36));
    expect(summary.recordedSleepAfterLastShift, const Duration(hours: 4));
    expect(summary.hasPendingEstimate, isTrue);
    expect(summary.recentlyFinishedNightShift, isTrue);
    expect(summary.approachingNightShift, isFalse);
  });

  test('upcoming night shift is identified without inventing sleep data', () {
    final summary = buildEnglishRecoverySummary(
      analyzer: analyzer,
      now: DateTime(2026, 9, 26, 15),
      records: const [],
    );
    expect(summary.approachingNightShift, isTrue);
    expect(summary.recordedSleepAfterLastShift, Duration.zero);
  });

  test('an ongoing shift is shown instead of asking for work hours', () {
    final summary = buildEnglishRecoverySummary(
      analyzer: analyzer,
      now: DateTime(2026, 9, 25, 2),
      records: const [],
    );
    expect(summary.currentShiftEnd, DateTime(2026, 9, 25, 7));
    expect(summary.nextShiftStart, DateTime(2026, 9, 26, 19));
    expect(summary.lastShiftEnd, isNull);
    expect(summary.betweenShifts, isNull);
    expect(summary.recordedSleepAfterLastShift, isNull);
  });

  test('overlapping confirmed records count shared sleep only once', () {
    final summary = buildEnglishRecoverySummary(
      analyzer: analyzer,
      now: DateTime(2026, 9, 25, 14),
      records: [
        SleepRecord(
          start: DateTime(2026, 9, 25, 8),
          end: DateTime(2026, 9, 25, 11),
          source: SleepSource.manual,
          status: SleepStatus.confirmed,
        ),
        SleepRecord(
          start: DateTime(2026, 9, 25, 10),
          end: DateTime(2026, 9, 25, 12),
          source: SleepSource.autoDetected,
          status: SleepStatus.confirmed,
        ),
      ],
    );
    expect(summary.recordedSleepAfterLastShift, const Duration(hours: 4));
  });
}
