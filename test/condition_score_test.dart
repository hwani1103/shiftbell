// test/condition_score_test.dart
//
// ⭐ 2026-09-01 후속10 - "오늘의 컨디션 점수"(condition_score.dart) 1차
// 가중치가 사용자가 말한 대략적인 기준(완전한 휴무+양호한 수면=100점 근처,
// 평범한 교대근무일=70점 안팎)에 얼추 맞는지 확인하는 캘리브레이션용 테스트.
// 정밀한 정답은 없음(사용자가 직접 가중치를 조정할 축) - 실행해서 나온
// 숫자를 사람이 보고 "이 정도면 말이 되는지" 판단하는 용도.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/condition_score.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';

const _kDay = '주간';
const _kNight = '야간';
const _kOff = '휴무';
const List<String> _pattern8Day = [_kDay, _kDay, _kOff, _kOff, _kNight, _kNight, _kOff, _kOff];
final _shiftTimes = <String, ShiftTimeRange>{
  _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60),
  _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60),
};

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

ShiftPatternAnalyzer _analyzerFor(DateTime today, {required int todayIndex, Map<int, String> overrides = const {}}) {
  final assignedDates = <String, String>{};
  overrides.forEach((offset, name) => assignedDates[_dateKey(today.add(Duration(days: offset)))] = name);
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: _pattern8Day,
    todayIndex: todayIndex,
    startDate: today,
    shiftTypes: const [_kDay, _kNight, _kOff],
    assignedDates: assignedDates.isEmpty ? null : assignedDates,
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);
}

void _printScore(String title, ConditionScoreResult r) {
  final tier = conditionScoreTierFor(r.score);
  // ignore: avoid_print
  print('\n=== $title ===');
  // ignore: avoid_print
  print('점수: ${r.score} ${tier.emoji} (${tier.label})');
  for (final f in r.factors) {
    // ignore: avoid_print
    print('  -${f.deduction} : ${f.label}');
  }
}

void main() {
  final today = DateTime(2026, 9, 6);

  test('1. 완전한 휴무 + 수면 충분(8시간) - 어제 12시간 근무 직후라 100점은 아니어도 매우 높아야 함', () {
    // ⭐ 2026-09-05 - 이 파일의 공용 _shiftTimes(주간/야간 둘 다 정확히 12시간)
    // 특성상, todayIndex: 2(휴무)의 "어제"(index1=주간)도 12시간 근무라
    // RULE_LONG_SHIFT가 정당하게 걸림(실기기 DB로 재현된 버그 수정 후 재계산 -
    // condition_score.dart factor 2가 예전엔 "오늘이 근무일일 때만" 체크해서
    // 이 케이스를 놓치고 있었음, 지금은 ConditionRuleEngine의 판정을 그대로
    // 읽어서 "어제 12시간 근무하고 오늘 쉬는 날"도 정확히 반영함) - 그래서
    // 예전 기대치(95점 이상)는 그 버그를 전제로 한 값이었고, 지금은 -10점만큼
    // 낮은 90점대가 정확한 계산임.
    final analyzer = _analyzerFor(today, todayIndex: 2); // base pattern index2 = 휴무
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult,
      analyzer: analyzer,
      today: today,
      otMinutesByDate: const {},
      avgRecentSleepMinutes: 8 * 60,
      isRotatingSchedule: true,
    );
    _printScore('1. 휴무 + 수면 8시간', r);
    expect(r.score, greaterThanOrEqualTo(88)); // "매우 좋음" 등급(veryGood, 88점 이상)
  });

  test('2. 평범한 교대근무일(주간 2일차, OT 없음, 수면 데이터 없음) - 사용자 예상 70점 안팎', () {
    final analyzer = _analyzerFor(today, todayIndex: 1); // 주간 2일차
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult,
      analyzer: analyzer,
      today: today,
      otMinutesByDate: const {},
      avgRecentSleepMinutes: null, // 데이터 없음 - 감점 안 됨
      isRotatingSchedule: true,
    );
    _printScore('2. 평범한 주간 근무일', r);
  });

  test('3. 평범한 야간근무일(첫 야간, OT 없음)', () {
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult, analyzer: analyzer, today: today,
      otMinutesByDate: const {}, avgRecentSleepMinutes: null, isRotatingSchedule: true,
    );
    _printScore('3. 평범한 야간 근무일', r);
  });

  test('4. 야간 3연속(대근) + 수면기록 없음', () {
    final analyzer = _analyzerFor(today, todayIndex: 6, overrides: {0: _kNight});
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult, analyzer: analyzer, today: today,
      otMinutesByDate: const {}, avgRecentSleepMinutes: null, isRotatingSchedule: true,
    );
    _printScore('4. 야간 3연속', r);
  });

  test('5. 장시간근무 연속(4연속 12h, 회복 부족) - 최악 시나리오 중 하나', () {
    final analyzer = _analyzerFor(today, todayIndex: 0, overrides: {
      -3: _kNight, -2: _kNight, -1: _kNight, 0: _kNight,
    });
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult, analyzer: analyzer, today: today,
      otMinutesByDate: const {}, avgRecentSleepMinutes: 5 * 60, isRotatingSchedule: true,
    );
    _printScore('5. 장시간 연속 + 수면부족(5h)', r);
    // ⭐ 후속12 - "최악이 38점 선" 재요청으로 상한 재조정(45→47) - 바닥이
    // 정확히 38점에서 잡히는지 확인(이 시나리오도 문제축 합계가 상한을 넘음).
    expect(r.score, inInclusiveRange(38, 48));
  });

  test('6. 최악 조합(장시간연속 + 수면부족 + OT + 역방향)', () {
    final analyzer = _analyzerFor(today, todayIndex: 0, overrides: {
      -6: _kOff, -5: _kNight, -4: _kNight, -3: _kNight, -2: _kNight, -1: _kNight, 0: _kNight,
    });
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult, analyzer: analyzer, today: today,
      otMinutesByDate: {_dateKey(today.subtract(const Duration(days: 1))): 8 * 60},
      avgRecentSleepMinutes: 4 * 60,
      isRotatingSchedule: true,
    );
    _printScore('6. 최악 조합', r);
    // ⭐ 후속12 - 이 시나리오는 요인이 더 많이 겹치지만(회복+연속+야간+연속근무+
    // OT+수면), 상한 때문에 시나리오5와 똑같이 38점 바닥에서 멈춤 - "최악은
    // 38점 선"이라는 요청이 의도한 그대로의 동작(단, 이미 상한에 걸린 두 극단
    // 케이스끼리는 서로 구분이 안 됨 - 캡의 트레이드오프).
    expect(r.score, inInclusiveRange(38, 48));
  });

  test('7. 저강도(휴가 위주, 주 1회 근무) - 근무일 자체', () {
    const patternLight = [_kNight, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];
    final schedule = ShiftSchedule(
      isRegular: true, pattern: patternLight, todayIndex: 0, startDate: today,
      shiftTypes: const [_kNight, _kOff],
    );
    final analyzer = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);
    final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
    final r = computeConditionScore(
      baseResult: baseResult, analyzer: analyzer, today: today,
      otMinutesByDate: const {}, avgRecentSleepMinutes: 7 * 60, isRotatingSchedule: true,
    );
    _printScore('7. 저강도 패턴 근무일', r);
  });
}
