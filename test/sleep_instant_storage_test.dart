import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/sleep_record.dart';

void main() {
  SleepRecord record(String start, String end) => SleepRecord.fromMap({
        'start_time': start,
        'end_time': end,
        'source': 'MANUAL',
        'status': 'CONFIRMED',
      });
  final cases = [
    (
      'New York spring',
      '2026-03-08T00:00:00-05:00',
      '2026-03-08T08:00:00-04:00',
      420
    ),
    (
      'New York autumn',
      '2026-11-01T00:00:00-04:00',
      '2026-11-01T08:00:00-05:00',
      540
    ),
    (
      'Berlin spring',
      '2026-03-29T00:00:00+01:00',
      '2026-03-29T08:00:00+02:00',
      420
    ),
    (
      'Berlin autumn',
      '2026-10-25T00:00:00+02:00',
      '2026-10-25T08:00:00+01:00',
      540
    ),
    (
      'Repeated hour',
      '2026-11-01T01:30:00-04:00',
      '2026-11-01T01:30:00-05:00',
      60
    ),
    (
      'Lord Howe half-hour',
      '2026-04-05T00:00:00+11:00',
      '2026-04-05T08:00:00+10:30',
      510
    ),
    ('India', '2026-10-14T00:00:00+05:30', '2026-10-14T08:00:00+05:30', 480),
    ('Nepal', '2026-10-14T00:00:00+05:45', '2026-10-14T08:00:00+05:45', 480),
    ('Korea', '2026-10-14T00:00:00+09:00', '2026-10-14T08:00:00+09:00', 480),
    (
      'Travel preserves elapsed time',
      '2026-10-14T00:00:00+09:00',
      '2026-10-14T00:00:00+01:00',
      480
    ),
  ];
  for (final c in cases) {
    test(c.$1, () {
      final r = record(c.$2, c.$3);
      expect(r.durationMinutes, c.$4);
      final saved = SleepRecord.fromMap(r.toMap());
      expect(saved.start.isAtSameMomentAs(r.start), isTrue);
      expect(saved.end!.isAtSameMomentAs(r.end!), isTrue);
      expect(saved.durationMinutes, c.$4);
      expect(
          r.toMap()['start_time'], matches(RegExp(r'[+-][0-9]{2}:[0-9]{2}$')));
    });
  }
  test('legacy local rows keep local wall clock fields', () {
    final r = record('2026-09-27T22:00:00', '2026-09-28T06:00:00');
    expect(r.start, DateTime(2026, 9, 27, 22));
    expect(r.end, DateTime(2026, 9, 28, 6));
  });
}
