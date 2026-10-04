import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/models/alarm_history.dart';
import 'package:shiftbell/utils/alarm_wall_time.dart';
import 'package:shiftbell/services/custom_alarm_service.dart';

void main() {
  tzdata.initializeTimeZones();
  for (final zone in ['America/New_York', 'Europe/London']) {
    final location = tz.getLocation(zone);
    final day = zone == 'Europe/London' ? '2026-10-25' : '2026-11-01';
    final offsets =
        zone == 'Europe/London' ? ['+01:00', '+00:00'] : ['-04:00', '-05:00'];
    for (var i = 0; i < 2; i++) {
      test(
          '$zone repeated 01:04 occurrence ${i + 1} survives storage and history',
          () {
        final stored = '${day}T01:04:00${offsets[i]}';
        final expected = DateTime.parse(stored);
        final local = tz.TZDateTime.from(expected, location);
        expect(alarmClockOccurrence(local), i + 1);
        expect(DateTime.parse(alarmInstantForStorage(local)), expected);
        final alarm = Alarm.fromMap({
          'id': 7,
          'time': '01:04',
          'date': stored,
          'type': 'snoozed',
          'alarm_type_id': 1
        });
        expect(alarm.date!.toUtc(), expected);
        expect(Alarm.fromMap(alarm.toMap()).date!.toUtc(), expected);
        final history = AlarmHistory.fromMap({
          'alarm_id': 7,
          'scheduled_date': stored,
          'scheduled_time': '01:04',
          'actual_ring_time': stored,
          'created_at': stored
        });
        expect(history.scheduledDate.toUtc(), expected);
        expect(history.createdAt.toUtc(), expected);
        expect(history.actualRingTime.toUtc(), expected);
      });
    }
  }
  test('five elapsed minutes can move the displayed clock backwards', () {
    final zone = tz.getLocation('America/New_York');
    final start =
        tz.TZDateTime.from(DateTime.parse('2026-11-01T01:58:00-04:00'), zone);
    final end = start.add(const Duration(minutes: 5));
    expect(end.hour, 1);
    expect(end.minute, 3);
    expect(alarmClockOccurrence(start), 1);
    expect(alarmClockOccurrence(end), 2);
    expect(parseAlarmDate(alarmInstantForStorage(end)).difference(start),
        const Duration(minutes: 5));
  });
  test('ordinary times have no occurrence label', () {
    expect(
        alarmClockOccurrence(
            tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 11, 1, 1)),
        0);
    expect(
        alarmClockOccurrence(
            tz.TZDateTime(tz.getLocation('America/New_York'), 2026, 11, 1, 3)),
        0);
  });
  test('one-tap collision uses the actual minute, not the repeated clock label', () {
    final zone = tz.getLocation('America/New_York');
    final first = tz.TZDateTime.from(DateTime.parse('2026-11-01T01:04:00-04:00'), zone);
    final second = first.add(const Duration(hours: 1));
    final now = first.subtract(const Duration(minutes: 5));
    expect(CustomAlarmService.validate(ringAt: second, now: now,
        sameDay: [ExistingAlarmSlot(first, 'snoozed')]), isNull);
    expect(CustomAlarmService.validate(ringAt: second, now: now,
        sameDay: [ExistingAlarmSlot(second.toUtc(), 'snoozed')]), CustomAlarmAssignResult.duplicate);
  });
}
