// test/sleep_opportunity_test.dart
//
// ⭐ 2026-09-06(사용자 논의) - "그 외(주간/오후/휴무)"는 무조건 21시부터 창이
// 열리다 보니, 21시를 넘겨 끝나는 주간/오후 근무(예: 12시간 주간 10~22시)에서
// 아직 근무 중에 창이 열려버리는 구멍이 있었다. "21시와 실제 종료시각 중 더
// 늦은 쪽"으로 고친 걸 검증(SleepScheduleResolver.kt도 동일하게 고쳤으나
// Kotlin은 별도 계측 없이는 유닛테스트하기 어려워 Dart 쪽만 검증).

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_opportunity.dart';

const _kDay = '주간';
const _kOff = '휴무';

void main() {
  final today = DateTime(2026, 9, 6);
  // now = 06시 - 아직 오늘 창이 시작 전(미래)이라 반환된 window.start를 그대로
  // "오늘의 창 시작 시각"으로 관찰할 수 있음.
  final now = DateTime(today.year, today.month, today.day, 6);

  ShiftPatternAnalyzer buildAnalyzer(ShiftTimeRange dayRange) {
    final schedule = ShiftSchedule(
      isRegular: true,
      pattern: [_kDay, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff],
      todayIndex: 0,
      startDate: today,
      shiftTypes: const [_kDay, _kOff],
    );
    return ShiftPatternAnalyzer(
      schedule: schedule,
      shiftTimes: {_kDay: dayRange},
    );
  }

  test('1. 주간 07~19시(21시 이전 퇴근) - 창은 그대로 21시부터(회귀 확인)', () {
    final analyzer = buildAnalyzer(
      const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60),
    );
    final window = sleepOpportunityWindowFor(now, analyzer: analyzer);
    expect(window, isNotNull);
    expect(window!.start, DateTime(today.year, today.month, today.day, 21),
        reason: '평소처럼 21시 이전에 끝나는 주간은 21시 고정이 그대로 맞음');
  });

  test('2. 주간 10~22시(21시를 넘겨 끝나는 12시간 근무) - 창이 실제 퇴근(22시)까지 밀려야 함', () {
    final analyzer = buildAnalyzer(
      const ShiftTimeRange(shiftName: _kDay, startMinutes: 10 * 60, endMinutes: 22 * 60),
    );
    final window = sleepOpportunityWindowFor(now, analyzer: analyzer);
    expect(window, isNotNull);
    expect(window!.start, DateTime(today.year, today.month, today.day, 22),
        reason: '21시 고정이면 아직 근무 중(22시 퇴근)인데 창이 열려버림 - 실제 퇴근시각까지 밀려야 함');
  });

  test('3. 휴무일 - 비교할 종료시각이 없으니 그대로 21시', () {
    final offDay = today.add(const Duration(days: 1));
    final nowOnOffDay = DateTime(offDay.year, offDay.month, offDay.day, 6);
    final analyzer = buildAnalyzer(
      const ShiftTimeRange(shiftName: _kDay, startMinutes: 10 * 60, endMinutes: 22 * 60),
    );
    final window = sleepOpportunityWindowFor(nowOnOffDay, analyzer: analyzer);
    expect(window, isNotNull);
    expect(window!.start, DateTime(offDay.year, offDay.month, offDay.day, 21),
        reason: '휴무일은 근무 종료시각 자체가 없으니 21시 그대로');
  });

  // ⭐ 2026-09-21(사용자 결정) - 야간 출근 전 낮잠창 신설. 연속 야간에서 출근 전에
  // 자는 잠이 ⑴ 회복창 9시간 캡 ⑵ 창당 1건 규칙 ⑶ 2시간 최소 길이에 3중으로 막혀
  // 한 번도 자동 기록되지 않던 문제(사용자 신고)를 별도 창으로 푼 것의 회귀 테스트.
  group('야간 출근 전 낮잠창', () {
    const kNight = '야간';
    const nightRange = ShiftTimeRange(shiftName: kNight, startMinutes: 19 * 60, endMinutes: 7 * 60);

    ShiftPatternAnalyzer nightAnalyzer(List<String> pattern, int todayIndex) {
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: todayIndex,
        startDate: today,
        shiftTypes: pattern.toSet().toList(),
      );
      return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: const {kNight: nightRange});
    }

    // 야간1 = 어제, 야간2 = 오늘. 야간1 회복창 = 오늘 06:00~15:00(9시간 캡).
    ShiftPatternAnalyzer consecutive() =>
        nightAnalyzer(const [kNight, kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);

    test('연속 야간 - 낮잠창은 회복창이 끝난 뒤(15시)부터 출근(19시)까지', () {
      final w = preShiftNapWindowFor(consecutive(), today);
      expect(w, isNotNull);
      expect(w!.start, DateTime(today.year, today.month, today.day, 15),
          reason: '회복창(06~15시)과 겹치면 "창당 1건" 규칙이 어느 쪽을 막을지 불안정해짐');
      expect(w.end, DateTime(today.year, today.month, today.day, 19));
      expect(w.kind, SleepWindowKind.preShiftNap);
    });

    test('야간 첫날(어제 휴무) - 회복창이 없으니 출근 6시간 전(13시)부터', () {
      final a = nightAnalyzer(const [_kOff, kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);
      final w = preShiftNapWindowFor(a, today);
      expect(w!.start, DateTime(today.year, today.month, today.day, 13));
      expect(w.end, DateTime(today.year, today.month, today.day, 19));
    });

    test('연속 야간 16시 - 실제로 낮잠창이 활성 창으로 선택된다(예전엔 내일 06시를 반환)', () {
      final now16 = DateTime(today.year, today.month, today.day, 16);
      final w = sleepOpportunityWindowFor(now16, analyzer: consecutive());
      expect(w, isNotNull);
      expect(w!.kind, SleepWindowKind.preShiftNap);
      expect(w.contains(now16), true);
    });

    test('연속 야간 10시 - 아침 회복창(메인 잠)이 그대로 우선', () {
      final now10 = DateTime(today.year, today.month, today.day, 10);
      final w = sleepOpportunityWindowFor(now10, analyzer: consecutive());
      expect(w!.kind, SleepWindowKind.mainSleep);
      expect(w.start, DateTime(today.year, today.month, today.day, 6));
      expect(w.end, DateTime(today.year, today.month, today.day, 15));
    });

    test('야간 근무일 22시(근무 중) - 플랫창이 열리면 안 된다', () {
      final a = nightAnalyzer(const [_kOff, kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);
      final now22 = DateTime(today.year, today.month, today.day, 22);
      final w = sleepOpportunityWindowFor(now22, analyzer: a);
      // 반환되더라도 "지금 근무 중인 시각"을 품는 활성 창이면 안 됨(근무 중 수면을 잡게 됨).
      expect(w == null || !w.contains(now22), true,
          reason: '야간 근무일의 21시는 이미 근무 중 - 플랫창 가드가 없으면 여기서 창이 열림');
    });

    test('내일이 야간이어도, 오늘 밤 자고 있는 플랫창(활성)을 가로채면 안 된다', () {
      // 오늘 휴무 / 내일 야간 - 지금 23시에 자기 시작함. 내일 낮잠창(13시)이
      // upcoming 후보로 먼저 반환되면 오늘 밤 수면이 통째로 추적에서 빠진다.
      final a = nightAnalyzer(const [_kOff, kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 0);
      final now23 = DateTime(today.year, today.month, today.day, 23);
      final w = sleepOpportunityWindowFor(now23, analyzer: a);
      expect(w, isNotNull);
      expect(w!.contains(now23), true, reason: '지금 활성인 플랫창이 선택돼야 함');
      expect(w.kind, SleepWindowKind.mainSleep);
    });
  });
}
