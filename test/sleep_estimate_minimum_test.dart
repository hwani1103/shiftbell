import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/sleep_record.dart';

void main() {
  final start = DateTime(2026, 10, 7, 23);
  SleepRecord record(Duration duration,
          {SleepSource source = SleepSource.autoDetected,
          SleepStatus status = SleepStatus.pendingConfirmation,
          bool ongoing = false}) =>
      SleepRecord(
          start: start,
          end: ongoing ? null : start.add(duration),
          source: source,
          status: status);

  test(
      'automatic estimates crossing midnight require five hours, both ongoing and ended',
      () {
    for (final duration in [
      const Duration(hours: 2),
      const Duration(hours: 3),
      const Duration(hours: 4, minutes: 59, seconds: 59),
      const Duration(hours: 5),
      const Duration(hours: 9)
    ]) {
      for (final ongoing in [false, true]) {
        expect(
            shouldOfferSleepEstimate(
                record(duration, ongoing: ongoing), start.add(duration)),
            duration >= const Duration(hours: 5));
      }
    }
  });
  test(
      'manual naps still appear and confirmed automatic history stays outside pending cards',
      () {
    for (final source in [SleepSource.manual, SleepSource.widgetManual]) {
      expect(
          shouldOfferSleepEstimate(
              record(const Duration(hours: 1), source: source), start),
          true);
    }
    final confirmed =
        record(const Duration(hours: 2), status: SleepStatus.confirmed);
    expect(
        shouldOfferSleepEstimate(
            confirmed, start.add(const Duration(hours: 9))),
        false);
    expect(confirmed.durationMinutes, 120);
  });
}
