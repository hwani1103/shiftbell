import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_day_slots.dart';

void main() {
  final rows = <Map<String, Object?>>[];
  ShiftPatternAnalyzer analyzer(bool consecutive) => ShiftPatternAnalyzer(
    schedule: ShiftSchedule(isRegular: true, pattern: consecutive ? ['휴무','야간','야간','휴무','휴무'] : ['휴무','야간','휴무','휴무','휴무'], todayIndex: 0, startDate: DateTime(2026,10,13), shiftTypes: ['휴무','야간']),
    shiftTimes: const {'야간': ShiftTimeRange(shiftName:'야간',startMinutes:1140,endMinutes:420)},
  );
  final cases = <(String,bool,String,String,String,String)>[
    ('single_before',false,'2026-10-13T22:00','2026-10-14T06:00','2026-10-13','main'),
    ('single_after_midnight',false,'2026-10-14T00:30','2026-10-14T08:00','2026-10-13','main'),
    ('single_pre_shift_long',false,'2026-10-14T12:00','2026-10-14T18:00','2026-10-14','nap'),
    ('single_on_shift',false,'2026-10-14T22:00','2026-10-15T01:00','2026-10-14','nap'),
    ('single_after_midnight_on_shift',false,'2026-10-15T00:00','2026-10-15T02:00','2026-10-14','nap'),
    ('single_recovery',false,'2026-10-15T08:00','2026-10-15T13:00','2026-10-14','main'),
    ('single_recovery_short',false,'2026-10-15T08:00','2026-10-15T09:59','2026-10-14','nap'),
    ('single_evening_sleep',false,'2026-10-15T20:30','2026-10-16T05:00','2026-10-15','main'),
    ('double_recovery',true,'2026-10-15T08:00','2026-10-15T13:00','2026-10-14','main'),
    ('double_pivot_1229',true,'2026-10-15T11:29','2026-10-15T13:29','2026-10-14','main'),
    ('double_pivot_1230',true,'2026-10-15T11:30','2026-10-15T13:30','2026-10-15','nap'),
    ('double_pre_shift',true,'2026-10-15T14:00','2026-10-15T17:00','2026-10-15','nap'),
    ('double_long_pre_shift',true,'2026-10-15T12:00','2026-10-15T18:30','2026-10-15','nap'),
    ('double_final_recovery',true,'2026-10-16T08:00','2026-10-16T13:00','2026-10-15','main'),
    ('double_final_night',true,'2026-10-16T23:00','2026-10-17T06:00','2026-10-16','main'),
    ('grace_exact',false,'2026-10-15T06:00','2026-10-15T08:00','2026-10-14','main'),
    ('grace_one_minute_before',false,'2026-10-15T05:59','2026-10-15T08:00','2026-10-14','nap'),
  ];
  for (final c in cases) {
    test(c.$1, () {
      final a=analyzer(c.$2);
      final r=SleepRecord(start:DateTime.parse(c.$3),end:DateTime.parse(c.$4),source:SleepSource.manual,status:SleepStatus.confirmed);
      final day=attributedSleepDay(r,a);
      final slots=buildSleepDaySlots(records:[r],from:day,to:day,analyzer:a).single;
      final actual=slots.mainSleep==r?'main':'nap';
      expect(day,DateTime.parse(c.$5)); expect(actual,c.$6);
      rows.add({'case':c.$1,'consecutive':c.$2,'start':c.$3,'end':c.$4,'day':c.$5,'slot':actual,'note':'single-record classification; longest candidate wins when combined'});
    });
  }
  tearDownAll(() { File('docs/next_version_27이후/수면회복_일정관리_글로벌도입_조사_2026-10-14/귀속_경계_실행결과.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows)); });
}
