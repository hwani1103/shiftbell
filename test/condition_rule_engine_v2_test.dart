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

  test('주간 총 근무시간(otMinutesByDate 안 넘기면 기본근무만으로 계산 - 8시간 근무 2일뿐이라 정상)', () {
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
    // otMinutesByDate를 안 넘김 - 기존 테스트/호출부와의 하위호환 확인. OT가 없으면
    // 기본근무만 3개 근무일치(24시간, 아래 참고)라 기준선(28시간)보다 오히려 적어
    // 조용해야 함(2026-09-17 재설계 - 예전엔 "OT 8시간"만으로도 걸렸지만, 이제 기본근무
    // 까지 합친 총량 기준이라 초과근무 없이는 이 정도 스케줄로 안 걸림).
    final withoutOt = ConditionRuleEngine(analyzer).evaluate(today);
    expect(_ruleIds(withoutOt), isEmpty);
    expect(withoutOt.level, ConditionLevel.normal);

    // ⭐ 2026-09-18 재설계 - OT 8시간을 더해도(24h+8h=32h) 기준선(28h)보다 4시간만
    // 많아 최소 임계값(6시간)에 못 미쳐 여전히 조용함.
    final smallOt = {_dateKey(today.subtract(const Duration(days: 1))): 8 * 60};
    final withSmallOt = ConditionRuleEngine(analyzer).evaluate(today, otMinutesByDate: smallOt);
    expect(_ruleIds(withSmallOt), isEmpty);
    expect(withSmallOt.level, ConditionLevel.normal);

    // ⭐ 2026-09-18 재설계 - 이 패턴(주간·휴무·야간·휴무 4일 주기)의 개인 기준선은
    // 12시간(주간8h+야간8h=16h)/4일*7 = 28시간. 이 7일 창은 위상상 실제로 3개 근무일이
    // 걸려(4일 주기가 7일 창과 안 맞아떨어지는 앨리어싱) 기본근무만 24시간 - 여기에
    // 초과근무 12시간을 더하면 총 36시간, 기준선(28시간)보다 8시간 많아 최소 임계값
    // (6시간)은 넘지만 심각 임계값(12시간)에는 못 미쳐 ATTENTION만.
    final heavyOt = {_dateKey(today.subtract(const Duration(days: 1))): 12 * 60};
    final withHeavyOt = ConditionRuleEngine(analyzer).evaluate(today, otMinutesByDate: heavyOt);
    expect(withHeavyOt.level, ConditionLevel.attention);
    expect(_ruleIds(withHeavyOt), ['RULE_WEEKLY_LOAD_INCREASE']);
    expect(withHeavyOt.levelFindings.single.evidenceIds, ['EVIDENCE-012']);
  });

  test('총 근무시간이 같으면 근무시간대가 달라도 비슷하게 평가된다(12시간×15일/월 vs 8시간×22일/월)', () {
    // 12시간 근무자: 3일 근무 + 4일 휴무 반복(7일 주기라 회전 위상과 무관하게 항상
    // 주 36시간 - 6일 주기(3근무+3휴무)를 쓰면 7일 롤링창과 주기가 안 맞아떨어져
    // 위상에 따라 주 36~48시간으로 흔들리는(6일 주기의 7일 창 앨리어싱) 부작용이 있어
    // 일부러 7일 주기로 맞춤).
    final times12h = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60), // 12시간
    };
    final analyzer12h = _analyzerFor(
      today,
      pattern: [_kDay, _kDay, _kDay, _kOff, _kOff, _kOff, _kOff],
      todayIndex: 2, // 3일 연속 근무의 마지막 날
      shiftTimes: times12h,
    );
    final result12h = ConditionRuleEngine(analyzer12h).evaluate(today);

    // 8시간 근무자: 5일 근무 + 2일 휴무 반복(7일 주기, 주 40시간).
    final times8h = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 9 * 60, endMinutes: 17 * 60), // 8시간
    };
    final analyzer8h = _analyzerFor(
      today,
      pattern: [_kDay, _kDay, _kDay, _kDay, _kDay, _kOff, _kOff],
      todayIndex: 4, // 5일 연속 근무의 마지막 날
      shiftTimes: times8h,
    );
    final result8h = ConditionRuleEngine(analyzer8h).evaluate(today);

    // 둘 다 주당 총량이 48시간 미만(36h/40h)이고, 연속일수(3일/5일)도 각 버킷의
    // 임계값과 같거나 낮은데 그 뒤 4일/2일 휴무로 회복시간이 넉넉해 RULE_EXTENDED_
    // STREAK_SHORT_BREAK도 안 걸림. 두 패턴 모두 "표준 근무시간이 다르다는 이유만으로"
    // 캐션이 뜨면 안 된다는 것이 핵심 검증.
    expect(result12h.level, ConditionLevel.normal, reason: '12시간 근무 자체가 단독으로 캐션을 유발하면 안 됨');
    expect(result8h.level, ConditionLevel.normal);
    expect(_ruleIds(result12h), isEmpty);
    expect(_ruleIds(result8h), isEmpty);
  });

  test('충분히 쉰 뒤의 장시간근무 vs 짧은 근무의 장기 연속근무 - 후자만 신호가 뜬다', () {
    // 12시간 근무, 그러나 직전 6일 연속 휴무(패턴: 휴무 6일 + 근무 1일 반복, 7일 주기) -
    // 오늘=근무. 7일 주기로 맞춘 이유: 6일 주기를 쓰면(위 테스트가 이미 지적한 "6일
    // 주기의 7일 창 앨리어싱") 이 패턴의 유일한 근무일이 7일 롤링창에 두 번 걸려
    // 개인 기준선 대비 실제보다 훨씬 많이 일한 것처럼 잘못 계산됨 - 7일 주기면 어떤
    // 위상에서도 항상 정확히 한 번만 걸려 기준선과 실측이 일치한다(2026-09-18 재설계
    // 이후 - RULE_WEEKLY_LOAD_INCREASE가 개인 기준선을 쓰기 시작하면서 새로 드러난
    // 앨리어싱 민감도).
    final timesRested = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60), // 12시간
    };
    final analyzerRested = _analyzerFor(
      today,
      pattern: [_kOff, _kOff, _kOff, _kOff, _kOff, _kOff, _kDay],
      todayIndex: 6, // 오늘 = 근무(직전 6일 휴무)
      shiftTimes: timesRested,
    );
    final resultRested = ConditionRuleEngine(analyzerRested).evaluate(today);
    expect(resultRested.level, ConditionLevel.normal, reason: '충분히 쉰 뒤의 12시간 근무 하루는 캐션을 유발하면 안 됨');
    expect(_ruleIds(resultRested), isEmpty);

    // 4시간 근무, 그러나 오늘로 정확히 7일째 연속근무(그 다음은 휴무 - 무한 연속이
    // 아니라 ATTENTION 임계값만 딱 채우는 케이스를 보려고 8일 근무 대신 7근무+2휴무
    // 9일 주기로 구성).
    final timesShort = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 9 * 60, endMinutes: 13 * 60), // 4시간
    };
    final analyzerShort = _analyzerFor(
      today,
      pattern: [_kDay, _kDay, _kDay, _kDay, _kDay, _kDay, _kDay, _kOff, _kOff],
      todayIndex: 6, // 7일 연속 근무의 마지막(7일째) 날
      shiftTimes: timesShort,
    );
    final resultShort = ConditionRuleEngine(analyzerShort).evaluate(today);
    expect(resultShort.consecutiveWorkDays, 7);
    // ⭐ 2026-09-18 재설계 - 오늘이 7일 연속근무의 마지막 날이면 트레일링 7일 창이
    // 이 9일 주기에서 일할 수 있는 날을 전부(7일) 담는 최댓값 위상이라, 개인
    // 기준선(28시간/9일*7≈21.8시간)보다 실측(28시간)이 6.2시간 많아 RULE_WEEKLY_
    // LOAD_INCREASE도 함께 발동한다(4시간짜리 근무를 몰아서 하는 주가 실제로 이
    // 사람의 평소보다 부담이 큰 주라는 뜻이라 부당한 결과가 아님) - 두 신호가 겹쳐
    // COMPOUND까지 겹치므로 HIGH_LOAD.
    expect(_ruleIds(resultShort), containsAll(['RULE_CONSECUTIVE_WORKDAYS', 'RULE_WEEKLY_LOAD_INCREASE', 'RULE_COMPOUND_HIGH_LOAD']));
    expect(resultShort.level, ConditionLevel.highLoad);

    // 후자가 전자보다 부담이 낮게 평가되면 안 됨(부당한 역전 방지).
    expect(resultShort.level.index, greaterThanOrEqualTo(resultRested.level.index));
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

  test('회귀 확인 - 회복시간 부족+장시간근무 조합(v1 원래 케이스)은 그대로 HIGH_LOAD (2026-09-17 재설계로 신호 구성이 바뀜)', () {
    // 매일 반복되는 14시간 야간(20~10시, 2교대뿐이라 방향 개념 자체가 없음(null),
    // 쉬는 날이 하루도 없는 극단적 패턴) - 24-14=10시간 회복이라 11시간 미만.
    // 2026-09-17 재설계로 이 패턴은 RULE_LONG_SHIFT(폐지됨) 대신 RULE_EXTENDED_
    // STREAK_SHORT_BREAK(12시간대 버킷)·RULE_CONSECUTIVE_WORKDAYS(쉬는 날이 아예
    // 없음)까지 겹쳐 걸린다. 2026-09-18 재설계 - RULE_WEEKLY_LOAD_INCREASE(옛
    // RULE_WEEKLY_TOTAL_LOAD)는 이제 절대 60시간이 아니라 개인 기준선 대비 증가폭을
    // 보는데, 이 패턴은 "매일 14시간 야간"이 스케줄 자체의 정의(=개인 기준선도 주
    // 98시간)라 실제(98시간)와 기준선(98시간)이 같아 증가가 없다고 계산됨 - 이 신호는
    // 의도적으로 조용해야 함(이 사람에게 98시간은 "늘어난 것"이 아니라 "원래 스케줄"
    // 이므로, 이 신호가 잡을 대상이 아님 - 대신 ScheduleLoadProfile이 별도로 "이 근무
    // 패턴 자체가 IOM 60시간 상한을 구조적으로 넘는다"고 조용히 알려줌).
    // "쉬는 날이 전혀 없는 스케줄"이라는 극단적 케이스라 다른 신호는 여전히 겹쳐서
    // 뜨는 것이 이번 재설계의 의도와 일치함(레벨이 HIGH_LOAD로 유지되는 것 자체가
    // 핵심 회귀 검증).
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
    expect(ids, containsAll(['RULE_SHORT_RECOVERY', 'RULE_EXTENDED_STREAK_SHORT_BREAK', 'RULE_COMPOUND_HIGH_LOAD']));
    expect(ids.contains('RULE_LONG_SHIFT'), isFalse); // 이 rule 자체가 폐지됨(2026-09-17)
    expect(ids.contains('RULE_BACKWARD_DIRECTION'), isFalse); // 방향 개념 자체가 성립 안 함
    expect(ids.contains('RULE_WEEKLY_LOAD_INCREASE'), isFalse,
        reason: '98시간이 이 사람의 기준선 자체라 "늘었다"는 신호가 아니어야 함(2026-09-18 핵심 회귀)');
    expect(result.weeklyBaselineMinutes, 98 * 60);
  });

  test('문구 다양성 - 완전히 동일한 스케줄이 반복돼도 누적 수치가 다르면 근거 판정 문구가 달라진다', () {
    // 같은 12시간 근무 3일+휴무 3일 패턴을 두 시점에서 비교: 3일 연속째(오늘)와
    // 아직 회복시간이 넉넉한 1일째(다른 날짜)는 RULE_EXTENDED_STREAK_SHORT_BREAK
    // 문구에 들어가는 "N일 연속" 숫자가 달라야 한다 - 절대 임계값이 아니라 누적
    // 수치를 그대로 문구에 꽂기 때문에 자연히 달라짐(반복되는 정적 문구 문제 완화).
    final times = <String, ShiftTimeRange>{
      _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60), // 12시간
    };
    final analyzer = _analyzerFor(
      today,
      pattern: [_kDay, _kDay, _kDay, _kDay, _kDay, _kDay, _kOff], // 6일 연속 근무 - 3일째/6일째 비교
      todayIndex: 0,
      shiftTimes: times,
    );
    final day3 = today.add(const Duration(days: 2)); // 3일째(임계 충족 시작)
    final day6 = today.add(const Duration(days: 5)); // 6일째(더 누적됨)
    final resultDay3 = ConditionRuleEngine(analyzer).evaluate(day3);
    final resultDay6 = ConditionRuleEngine(analyzer).evaluate(day6);

    final streakMsg3 = resultDay3.levelFindings.firstWhere((f) => f.ruleId == 'RULE_EXTENDED_STREAK_SHORT_BREAK').message;
    final streakMsg6 = resultDay6.levelFindings.firstWhere((f) => f.ruleId == 'RULE_EXTENDED_STREAK_SHORT_BREAK').message;
    expect(streakMsg3, isNot(equals(streakMsg6)), reason: '연속일수가 다르면 문구도 달라야 함(정적 문구 방지)');
    expect(streakMsg3, contains('3일'));
    expect(streakMsg6, contains('6일'));
  });
}
