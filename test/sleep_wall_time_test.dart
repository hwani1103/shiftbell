import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shiftbell/utils/sleep_wall_time.dart';

void main() {
  tzdata.initializeTimeZones();
  final cases = [
    ('America/New_York', '2026-03-08T02:30:00', 0, 0),
    ('America/New_York', '2026-11-01T01:30:00', 2, 60),
    ('Europe/Berlin', '2026-03-29T02:30:00', 0, 0),
    ('Europe/Berlin', '2026-10-25T02:30:00', 2, 60),
    ('Europe/London', '2026-03-29T01:30:00', 0, 0),
    ('Europe/London', '2026-10-25T01:30:00', 2, 60),
    ('Australia/Lord_Howe', '2026-10-04T02:15:00', 0, 0),
    ('Australia/Lord_Howe', '2026-04-05T01:45:00', 2, 30),
    ('Asia/Seoul', '2026-03-08T02:30:00', 1, 0),
    ('Asia/Kolkata', '2026-03-08T02:30:00', 1, 0),
    ('Asia/Kathmandu', '2026-03-08T02:30:00', 1, 0),
    ('America/Sao_Paulo', '2026-03-08T02:30:00', 1, 0),
    ('Asia/Dubai', '2026-03-08T02:30:00', 1, 0),
    ('Africa/Johannesburg', '2026-03-08T02:30:00', 1, 0),
    ('Asia/Manila', '2026-03-08T02:30:00', 1, 0),
  ];
  for (final c in cases) {
    test(c.$1 + ' ' + c.$2, () {
      final wall = DateTime.parse(c.$2 + 'Z');
      final location = tz.getLocation(c.$1);
      final values = sleepWallTimeCandidates(wall,
          localFromEpoch: (epoch) =>
              tz.TZDateTime.fromMillisecondsSinceEpoch(location, epoch));
      expect(values.length, c.$3);
      if (values.length == 2)
        expect(values.last.difference(values.first).inMinutes, c.$4);
      for (final value in values) {
        expect(value.year, wall.year);
        expect(value.month, wall.month);
        expect(value.day, wall.day);
        expect(value.hour, wall.hour);
        expect(value.minute, wall.minute);
      }
    });
  }
}
