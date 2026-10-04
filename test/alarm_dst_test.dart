import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shiftbell/utils/alarm_wall_time.dart';
import 'package:shiftbell/models/alarm_template.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/alarm_generation_service.dart';

void main() {
  tzdata.initializeTimeZones();
  final cases =
      (jsonDecode(File('test/fixtures/alarm_dst_cases.json').readAsStringSync())
          as List);
  for (final c in cases) {
    test('${c['zone']} ${c['wall']} generation, offsets and stored date agree',
        () {
      final zone = tz.getLocation(c['zone']);
      DateTime local(int epoch) =>
          tz.TZDateTime.fromMillisecondsSinceEpoch(zone, epoch);
      DateTime resolve(DateTime wall) =>
          resolveAlarmWallTime(wall, localFromEpoch: local);
      final wall = DateTime.parse('${c['wall']}Z');
      final expected = DateTime.parse(c['utc']);
      final actual = resolve(wall);
      expect(actual.toUtc(), expected);
      expect(
          parseAlarmDate(c['wall'], localFromEpoch: local).toUtc(), expected);
      // Native writes normalized local dates, without an offset, to the DB.
      expect(
          parseAlarmDate(alarmSlotTime(actual), localFromEpoch: local).toUtc(),
          expected);
      for (final offset in [-1, 0, 1]) {
        final origin = DateTime.utc(wall.year, wall.month, wall.day - offset);
        final dayKey = origin.toIso8601String().substring(0, 10);
        final schedule = ShiftSchedule(
            isRegular: false,
            shiftTypes: const ['Night'],
            assignedDates: {dayKey: 'Night'});
        final alarms = computeDesiredFixedAlarmsForDate(
            date: wall,
            schedule: schedule,
            allTemplates: [
              AlarmTemplate(
                  shiftType: 'Night',
                  time: c['wall'].substring(11, 16),
                  alarmTypeId: 1,
                  dayOffset: offset)
            ],
            now: local(expected
                .subtract(const Duration(hours: 8))
                .millisecondsSinceEpoch),
            resolveTime: resolve);
        expect(alarms, hasLength(1));
        expect(alarms.single.dateTime.toUtc(), expected);
        expect(alarms.single.time, c['clock']);
        expect(alarms.single.dayOffset, offset);
      }
    });
  }
  test('spring gap colliding with 03:30 produces one alarm', () {
    final zone = tz.getLocation('America/New_York');
    final alarms = computeDesiredFixedAlarmsForDate(
        date: DateTime.utc(2026, 3, 8),
        schedule: ShiftSchedule(
            isRegular: false,
            shiftTypes: const ['Night'],
            assignedDates: const {'2026-03-08': 'Night'}),
        allTemplates: [
          for (final time in ['02:30', '03:30'])
            AlarmTemplate(shiftType: 'Night', time: time, alarmTypeId: 1)
        ],
        now: DateTime.utc(2026, 3, 8),
        resolveTime: (wall) => resolveAlarmWallTime(wall,
            localFromEpoch: (epoch) =>
                tz.TZDateTime.fromMillisecondsSinceEpoch(zone, epoch)));
    expect(alarms, hasLength(1));
    expect(alarms.single.dateTime.toUtc(), DateTime.utc(2026, 3, 8, 7, 30));
  });
  test('first 01:45 does not discard second 01:30; past occurrence stays past',
      () {
    final zone = tz.getLocation('America/New_York');
    List<PendingFixedAlarm> generate(DateTime now) =>
        computeDesiredFixedAlarmsForDate(
            date: DateTime.utc(2026, 11, 1),
            schedule: ShiftSchedule(
                isRegular: false,
                shiftTypes: const ['Night'],
                assignedDates: const {'2026-11-01': 'Night'}),
            allTemplates: [
              AlarmTemplate(shiftType: 'Night', time: '01:30', alarmTypeId: 1)
            ],
            now: now,
            resolveTime: (wall) => resolveAlarmWallTime(wall,
                localFromEpoch: (epoch) =>
                    tz.TZDateTime.fromMillisecondsSinceEpoch(zone, epoch)));
    expect(generate(DateTime.utc(2026, 11, 1, 5, 45)), hasLength(1));
    expect(generate(DateTime.utc(2026, 11, 1, 6, 30)), isEmpty);
  });
}
