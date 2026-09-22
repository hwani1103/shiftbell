// test/sleep_overlap_test.dart
//
// 2026-09-22 (B-2) - 수면 기록 겹침 규칙 회귀 테스트.
// 1) "지난 24시간 수면" 같은 합계는 겹친 시간을 두 번 세지 않는다(구간 합집합).
// 2) 직접 입력·확정 시 겹침 판정: 확정 기록만 비교, 자기 자신 제외, 맞닿음은 겹침 아님, 진행 중 기록은 지금까지로 본다.
// 3) 하루 낮잠이 3개 이상이어도 합계·평균은 칸(2개)이 아니라 전부를 센다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_day_slots.dart';
import 'package:shiftbell/services/condition/sleep_overlap.dart';

SleepRecord _r(DateTime start, DateTime? end,
        {int? id, SleepStatus status = SleepStatus.confirmed}) =>
    SleepRecord(id: id, start: start, end: end, source: SleepSource.manual, status: status);

DateTime _t(int day, int hour, [int minute = 0]) => DateTime(2026, 9, day, hour, minute);

void main() {
  group('mergedSleepMinutesBetween', () {
    final from = _t(10, 0);
    final until = _t(11, 0);

    test('겹치지 않으면 단순 합과 같다', () {
      final records = [_r(_t(10, 1), _t(10, 5)), _r(_t(10, 13), _t(10, 14))];
      expect(mergedSleepMinutesBetween(records, from, until), 5 * 60);
    });

    test('일부 겹침은 한 번만 센다', () {
      final records = [_r(_t(10, 1), _t(10, 5)), _r(_t(10, 4), _t(10, 7))];
      expect(mergedSleepMinutesBetween(records, from, until), 6 * 60);
    });

    test('완전히 포함된 기록은 더하지 않는다', () {
      final records = [_r(_t(10, 1), _t(10, 8)), _r(_t(10, 3), _t(10, 4))];
      expect(mergedSleepMinutesBetween(records, from, until), 7 * 60);
    });

    test('맞닿은 기록은 이어서 센다', () {
      final records = [_r(_t(10, 1), _t(10, 3)), _r(_t(10, 3), _t(10, 5))];
      expect(mergedSleepMinutesBetween(records, from, until), 4 * 60);
    });

    test('창 경계에 걸친 기록은 창 안 부분만 센다', () {
      final records = [_r(_t(9, 22), _t(10, 6)), _r(_t(10, 23), _t(11, 7))];
      expect(mergedSleepMinutesBetween(records, from, until), 6 * 60 + 60);
    });

    test('끝나지 않은 기록과 빈 창은 0', () {
      expect(mergedSleepMinutesBetween([_r(_t(10, 1), null)], from, until), 0);
      expect(mergedSleepMinutesBetween([_r(_t(10, 1), _t(10, 5))], until, from), 0);
    });
  });

  group('findOverlappingSleep', () {
    final main = _r(_t(10, 23), _t(11, 6), id: 1);

    test('겹치면 그 기록을 돌려준다', () {
      expect(findOverlappingSleep([main], _t(11, 5), _t(11, 8))?.id, 1);
    });

    test('맞닿기만 하면 겹침이 아니다', () {
      expect(findOverlappingSleep([main], _t(11, 6), _t(11, 8)), isNull);
      expect(findOverlappingSleep([main], _t(10, 20), _t(10, 23)), isNull);
    });

    test('수정 중인 자기 자신은 뺀다', () {
      expect(findOverlappingSleep([main], _t(10, 22), _t(11, 7), excludeId: 1), isNull);
    });

    test('확인 대기 중인 자동 후보는 직접 입력을 막지 않는다', () {
      final pending = _r(_t(11, 13), _t(11, 16), id: 2, status: SleepStatus.pendingConfirmation);
      expect(findOverlappingSleep([pending], _t(11, 14), _t(11, 15)), isNull);
    });

    test('진행 중인 확정 기록은 지금까지 이어진 것으로 본다', () {
      final ongoing = _r(_t(11, 13), null, id: 3);
      expect(findOverlappingSleep([ongoing], _t(11, 14), _t(11, 15), now: _t(11, 16))?.id, 3);
      expect(findOverlappingSleep([ongoing], _t(11, 17), _t(11, 18), now: _t(11, 16)), isNull);
    });

    test('여러 개가 겹치면 가장 이른 것', () {
      final a = _r(_t(11, 10), _t(11, 12), id: 4);
      final b = _r(_t(11, 8), _t(11, 11), id: 5);
      expect(findOverlappingSleep([a, b], _t(11, 9), _t(11, 13))?.id, 5);
    });
  });

  test('낮잠이 3개인 날도 합계는 전부를 센다(칸은 2개)', () {
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: const ['휴무'],
      todayIndex: 0,
      startDate: DateTime(2026, 9, 1),
      shiftTypes: const ['휴무'],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: const {});
    final naps = [
      _r(_t(10, 10), _t(10, 10, 40), id: 11),
      _r(_t(10, 13), _t(10, 13, 30), id: 12),
      _r(_t(10, 16), _t(10, 16, 50), id: 13),
    ];
    final slots = buildSleepDaySlots(
      records: naps,
      from: DateTime(2026, 9, 10),
      to: DateTime(2026, 9, 10),
      analyzer: analyzer,
    );
    final day = slots.single;
    expect(day.nap1?.id, 11);
    expect(day.nap2?.id, 12);
    expect(day.allNaps.length, 3);
    expect(day.napMinutes, 40 + 30 + 50);
  });
}
