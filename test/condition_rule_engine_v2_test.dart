// test/condition_rule_engine_v2_test.dart
//
// ⭐ 2026-09-04 - ConditionRuleEngine v2(사용자 요청 - "이미 확보한 evidence를
// 빠짐없이 판정에 활용") 검증용. 기존 today_forecast_engine_test.dart/
// condition_score_test.dart는 전부 2교대(주간/야간)뿐인 스케줄만 써서
// analyzeDirection()이 항상 null을 반환했고(day/evening/night 3종류가 다 있어야
// 방향 개념이 성립 - shift_pattern_analyzer.dart 참고) otMinutesByDate도 항상
// evaluate()에 안 넘겼기 때문에, RULE_BACKWARD_DIRECTION/RULE_WEEKLY_OVERTIME은
// 그 테스트들로는 전혀 검증되지 않았음(전체 스위트가 통과한 건 "기존 동작을 안
// 깼다"는 증거일 뿐, "새 규칙이 동작한다"는 증거는 아니었음) - 이 파일이 그 공백을 메움.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';

const _kDay = '주간';
const _kEvening = '오후';
const _kNight = '야간';
const _kOff = '휴무';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

ShiftPatternAnalyzer _analyzerFor(
  DateTime today, {
  required List<String> pattern,
  required int todayIndex,
  required Map<String, ShiftTimeRange> shiftTimes,
}) {
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: pattern,
    todayIndex: todayIndex,
    startDate: today,
    shiftTypes: [...pattern.toSet()],
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: shiftTimes);
}

List<String> _ruleIds(ConditionResult r) =>
    r.levelFindings.where((f) => f.ruleId != null).map((f) => f.ruleId!).toList();

void main() {
  final today = DateTime(2026, 9, 6);

  test('역방향 단독(다른 부담 없음) - ATTENTION, RULE_BACKWARD_DIRECTION만', () {
    // 야간→오후→주간→휴무 순환 = day/evening/night 역순(역방향). 오늘=휴무라
    // 회복시간/장시간근무는 전혀 안 걸림 - 방향 신호 하나만 순수하게 검증.
    final times = <String, ShiftTimeRange>{
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
      _kEvening: const ShiftTimeRange(shiftName: _kEvening, startMinutes: 14 * 60, endMinutes: 22 * 60),
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 15 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kNight, _kEvening, _kDay, _kOff],
      todayIndex: 3, // 휴무
      shiftTimes: times,
    );
    final result = ConditionRuleEngine(analyzer).evaluate(today);

    expect(result.level, ConditionLevel.attention);
    expect(_ruleIds(result), ['RULE_BACKWARD_DIRECTION']);
    expect(
      result.levelFindings.single.evidenceIds,
      ['EVIDENCE-001'],
    );
  });

  test('정방향은 레벨에 영향 없음(컨텍스트로만 표시)', () {
    final times = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 15 * 60),
      _kEvening: const ShiftTimeRange(shiftName: _kEvening, startMinutes: 14 * 60, endMinutes: 22 * 60),
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kDay, _kEvening, _kNight, _kOff],
      todayIndex: 3,
      shiftTimes: times,
    );
    final result = ConditionRuleEngine(analyzer).evaluate(today);

    expect(result.level, ConditionLevel.normal);
    expect(_ruleIds(result), isEmpty);
    // 정방향 정보는 여전히 설명용 context로만 나옴.
    expect(
      result.contextFindings.any((f) => f.ruleId == 'RULE_SHIFT_DIRECTION'),
      isTrue,
    );
  });

  test('주간 초과근무 단독(otMinutesByDate 안 넘기면 항상 꺼짐 - 기본값 확인)', () {
    final times = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 15 * 60),
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kDay, _kOff, _kNight, _kOff],
      todayIndex: 1, // 휴무
      shiftTimes: times,
    );
    // otMinutesByDate를 안 넘김 - 기존 테스트/호출부와의 하위호환 확인.
    final withoutOt = ConditionRuleEngine(analyzer).evaluate(today);
    expect(_ruleIds(withoutOt), isEmpty);
    expect(withoutOt.level, ConditionLevel.normal);

    // 최근 7일 누적 8시간 이상 - RULE_WEEKLY_OVERTIME 단독 발동.
    final otMinutes = {_dateKey(today.subtract(const Duration(days: 1))): 8 * 60};
    final withOt = ConditionRuleEngine(analyzer).evaluate(today, otMinutesByDate: otMinutes);
    expect(withOt.level, ConditionLevel.attention);
    expect(_ruleIds(withOt), ['RULE_WEEKLY_OVERTIME']);
    expect(withOt.levelFindings.single.evidenceIds, ['EVIDENCE-012']);
  });

  test('역방향 + 회복시간 부족 겹침 - HIGH_LOAD로 승격 + RULE_COMPOUND_HIGH_LOAD', () {
    // 야간→오후→주간 3일 순환(휴무 없음, 역방향) - 주간(07~15) 종료 후 겨우
    // 7시간 뒤에 야간(22시)이 시작돼 회복시간이 11시간 미만.
    final times = <String, ShiftTimeRange>{
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
      _kEvening: const ShiftTimeRange(shiftName: _kEvening, startMinutes: 14 * 60, endMinutes: 22 * 60),
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 15 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kNight, _kEvening, _kDay],
      todayIndex: 0, // 오늘 = 야간
      shiftTimes: times,
    );
    final result = ConditionRuleEngine(analyzer).evaluate(today);

    expect(result.level, ConditionLevel.highLoad);
    final ids = _ruleIds(result);
    expect(ids, containsAll(['RULE_SHORT_RECOVERY', 'RULE_BACKWARD_DIRECTION', 'RULE_COMPOUND_HIGH_LOAD']));
    // 장시간근무(8시간, 12시간 미만)는 안 걸려야 함 - 오직 회복시간+방향 2개 조합.
    expect(ids.contains('RULE_LONG_SHIFT'), isFalse);
    final compound = result.levelFindings.firstWhere((f) => f.ruleId == 'RULE_COMPOUND_HIGH_LOAD');
    expect(compound.evidenceIds, containsAll(['EVIDENCE-002', 'EVIDENCE-003', 'EVIDENCE-001']));
  });

  test('연속 야간근무 3일째 - ATTENTION, RULE_CONSECUTIVE_NIGHT_SHIFTS만(다른 부담 없음)', () {
    // 야간 8시간(12시간 미만이라 RULE_LONG_SHIFT 안 걸림, 매일 반복이라 회복시간도
    // 16시간으로 충분) - 휴무 4일 뒤 야간 3연속, 오늘=그 3번째 야간.
    final times = <String, ShiftTimeRange>{
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kOff, _kOff, _kOff, _kOff, _kNight, _kNight, _kNight, _kOff],
      todayIndex: 6, // 3번째 야간
      shiftTimes: times,
    );
    final result = ConditionRuleEngine(analyzer).evaluate(today);

    expect(result.consecutiveNightDays, 3);
    expect(result.level, ConditionLevel.attention);
    expect(_ruleIds(result), ['RULE_CONSECUTIVE_NIGHT_SHIFTS']);
    expect(result.levelFindings.single.evidenceIds, ['EVIDENCE-013']);
  });

  test('연속 야간근무 4일째 - 단독으로 HIGH_LOAD(가속화 구간)', () {
    final times = <String, ShiftTimeRange>{
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kOff, _kOff, _kOff, _kOff, _kNight, _kNight, _kNight, _kNight],
      todayIndex: 7, // 4번째 야간
      shiftTimes: times,
    );
    final result = ConditionRuleEngine(analyzer).evaluate(today);

    expect(result.consecutiveNightDays, 4);
    expect(result.level, ConditionLevel.highLoad);
    expect(_ruleIds(result), ['RULE_CONSECUTIVE_NIGHT_SHIFTS']);
  });

  test('회귀 확인 - 회복시간 부족+장시간근무 조합(v1 원래 케이스)은 그대로 HIGH_LOAD', () {
    // 매일 반복되는 14시간 야간(20~10시, 2교대뿐이라 방향 개념 자체가 없음(null)) -
    // 24-14=10시간 회복이라 11시간 미만.
    final times = <String, ShiftTimeRange>{
      _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 20 * 60, endMinutes: 10 * 60),
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kNight],
      todayIndex: 0,
      shiftTimes: times,
    );
    final result = ConditionRuleEngine(analyzer).evaluate(today);

    expect(result.level, ConditionLevel.highLoad);
    final ids = _ruleIds(result);
    expect(ids, containsAll(['RULE_SHORT_RECOVERY', 'RULE_LONG_SHIFT', 'RULE_COMPOUND_HIGH_LOAD']));
    expect(ids.contains('RULE_BACKWARD_DIRECTION'), isFalse); // 방향 개념 자체가 성립 안 함
    expect(ids.contains('RULE_WEEKLY_OVERTIME'), isFalse); // OT 데이터 자체를 안 넘김
  });
}
