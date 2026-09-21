// test/night_shift_sleep_attribution_test.dart
//
// ⭐ 2026-09-21(사용자 신고 시나리오 그대로) - 야간 근무 주변의 수면 귀속과
// "오늘의 컨디션" 수면량 문구 회귀 테스트.
//
//  1) 연속 야간(야간1·야간2)일 때 야간2의 "출근 전 수면"(예: 14~17시)이 야간1의
//     낮잠으로 빨려 들어가던 버그 - sleep_day_slots.dart의 _attributedDay가
//     "어제 퇴근 ~ 오늘 출근"의 한가운데를 경계로 쓰도록 바뀐 것의 회귀.
//  2) "출근 전 수면 2시간 — 권장 7시간보다 짧아요"처럼 야간 근무자에게 실행
//     불가능한 비교를 하던 문구를 "지난 24시간 총 수면"으로 바꾼 것의 회귀
//     (recovery_briefing_engine.dart 3-1).
//  3) 근무시간(출퇴근 시각)을 하나도 입력하지 않은 상태에서도 수면 기록만으로
//     말할 수 있는 사실은 계속 나와야 한다(수면·회복 탭의 자동 감지는 그 상태에서도
//     계속 돌아가므로).

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/recovery_briefing_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_day_slots.dart';

const _kNight = '야간';
const _kDay = '주간';
const _kOff = '휴무';
const _nightRange = ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60);
const _dayRange = ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60);

final _anchor = DateTime(2026, 9, 17); // "오늘"

ShiftPatternAnalyzer _analyzer(List<String> pattern, int todayIndex, {bool withTimes = true}) {
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: pattern,
    todayIndex: todayIndex,
    startDate: _anchor,
    shiftTypes: pattern.toSet().toList(),
  );
  return ShiftPatternAnalyzer(
    schedule: schedule,
    shiftTimes: withTimes ? const {_kNight: _nightRange, _kDay: _dayRange} : const {},
  );
}

SleepRecord _sleep(DateTime start, int minutes) => SleepRecord(
      start: start,
      end: start.add(Duration(minutes: minutes)),
      source: SleepSource.manual,
      status: SleepStatus.confirmed,
    );

RecoveryBriefing _brief(ShiftPatternAnalyzer a, DateTime now, List<SleepRecord> records) =>
    buildRecoveryBriefing(
      analyzer: a,
      base: ConditionRuleEngine(a).evaluate(DateTime(now.year, now.month, now.day)),
      records: records,
      now: now,
    );

String _sleepFact(RecoveryBriefing b) =>
    b.facts.firstWhere((f) => f.topic == BriefingTopic.sleepAmount).text;

void main() {
  final today = _anchor; // 9/17
  final yesterday = today.subtract(const Duration(days: 1)); // 9/16

  // 야간1 = 9/16, 야간2 = 9/17 (둘 다 19~07시)
  ShiftPatternAnalyzer consecutiveNights() =>
      _analyzer(const [_kNight, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);

  group('연속 야간 - 아침 회복수면과 출근 전 수면의 분리(사용자 신고 항목 5)', () {
    // 야간1 퇴근(9/17 07시) 뒤 아침에 자고, 그날 오후에 야간2 출근 전 낮잠을 또 잔 경우.
    final recovery = _sleep(DateTime(2026, 9, 17, 8), 5 * 60); // 9/17 08~13시
    final preShiftNap = _sleep(DateTime(2026, 9, 17, 14), 3 * 60); // 9/17 14~17시

    test('아침 회복수면은 야간1(어제) 주 수면, 오후 출근 전 수면은 야간2(오늘) 낮잠으로 갈린다', () {
      final a = consecutiveNights();
      final slots = buildSleepDaySlots(
        records: [recovery, preShiftNap],
        from: yesterday,
        to: today,
        analyzer: a,
      );
      final ySlot = slots.firstWhere((s) => s.date == yesterday);
      final tSlot = slots.firstWhere((s) => s.date == today);

      expect(ySlot.mainSleep?.start, recovery.start, reason: '야간1의 주 수면은 다음날 아침 회복수면');
      expect(ySlot.nap1, null, reason: '오후 출근 전 수면이 야간1의 낮잠으로 딸려오면 안 됨(신고된 버그)');
      expect(tSlot.nap1?.start, preShiftNap.start, reason: '야간2 출근 전 수면은 야간2 당일 낮잠 칸');
      expect(tSlot.mainSleep, null, reason: '야간2의 주 수면 자리는 내일 아침 회복수면용으로 비워둠');
    });

    test('오늘이 휴무면 경계는 예전처럼 21시 - 아침 회복수면은 어제, 그날 밤 취침은 오늘', () {
      final a = _analyzer(const [_kNight, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff], 1);
      final ownNight = _sleep(DateTime(2026, 9, 17, 23), 7 * 60);
      final slots = buildSleepDaySlots(records: [recovery, ownNight], from: yesterday, to: today, analyzer: a);
      expect(slots.firstWhere((s) => s.date == yesterday).mainSleep?.start, recovery.start);
      expect(slots.firstWhere((s) => s.date == today).mainSleep?.start, ownNight.start);
    });
  });

  group('수면량 문구 - "출근 전 7시간"이 아니라 "지난 24시간"(사용자 신고 항목 2)', () {
    test('야간 첫날(어제 휴무) - 전날 밤잠 8시간 + 출근 전 낮잠 2시간이면 부족 경고가 없어야 한다', () {
      final a = _analyzer(const [_kOff, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);
      final records = [
        _sleep(DateTime(2026, 9, 16, 23), 8 * 60), // 9/16 23시~9/17 07시
        _sleep(DateTime(2026, 9, 17, 14), 2 * 60), // 출근 전 낮잠 2시간
      ];
      final b = _brief(a, DateTime(2026, 9, 17, 19, 30), records); // 야간 근무 중
      final fact = _sleepFact(b);

      expect(fact, contains('지난 24시간 수면 10시간'));
      expect(fact, contains('출근 전 2시간 포함'));
      expect(fact, isNot(contains('권장')), reason: '10시간이면 부족 경고가 붙으면 안 됨');
      expect(b.facts.any((f) => f.text.contains('출근 전 수면 2시간')), false,
          reason: '"출근 전 수면 2시간 — 권장 7시간보다 짧아요"는 없어져야 함');
    });

    test('연속 야간 둘째 날 - 아침 회복수면 5시간 + 출근 전 2시간이면 합쳐서 7시간으로 본다', () {
      final a = consecutiveNights();
      final records = [
        _sleep(DateTime(2026, 9, 17, 8), 5 * 60),
        _sleep(DateTime(2026, 9, 17, 14), 2 * 60),
      ];
      final fact = _sleepFact(_brief(a, DateTime(2026, 9, 17, 19, 30), records));
      expect(fact, contains('지난 24시간 수면 7시간'));
      expect(fact, isNot(contains('권장')));
    });

    test('실제로 부족하면(2시간만 잠) 여전히 권장 7시간보다 적다고 알린다', () {
      final a = _analyzer(const [_kOff, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);
      final records = [_sleep(DateTime(2026, 9, 17, 14), 2 * 60)];
      final b = _brief(a, DateTime(2026, 9, 17, 19, 30), records);
      final fact = _sleepFact(b);
      expect(fact, contains('지난 24시간 수면 2시간'));
      expect(fact, contains('권장 7시간보다 적어요'));
      expect(fact, isNot(contains('포함')), reason: '24시간 총량과 같은 값이면 괄호를 붙이지 않는다');
    });

    test('기록이 비어 있으면 사실에서 끝내지 않고 기록 안내 행동까지 준다(항목 1)', () {
      final a = _analyzer(const [_kOff, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1);
      // 최근 2주 안에 다른 기록은 있지만 지난 24시간에는 없는 상태
      final records = [_sleep(DateTime(2026, 9, 12, 23), 7 * 60)];
      final b = _brief(a, DateTime(2026, 9, 17, 17, 30), records);
      expect(b.facts.any((f) => f.text == '지난 24시간 수면 기록이 없어요'), true);
      expect(b.actions.any((x) => x.id == 'record_sleep'), true,
          reason: '"기록이 없어요"에서 문장이 끊기지 않고 다음 행동을 줘야 함');
    });
  });

  test('근무시간을 하나도 입력하지 않아도 수면 사실은 계속 나온다(항목 3)', () {
    final a = _analyzer(const [_kNight, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff], 1, withTimes: false);
    final records = [_sleep(DateTime(2026, 9, 16, 23), 6 * 60)]; // 어제 밤잠
    final b = _brief(a, DateTime(2026, 9, 17, 12), records);
    expect(b.phase, BriefingPhase.unknown);
    expect(b.facts.any((f) => f.topic == BriefingTopic.sleepAmount && f.text.contains('어제(9/16) 수면 6시간')), true);
    expect(b.limitations.any((l) => l.contains('출퇴근 시각이 없어')), true);
  });
}
