// test/today_forecast_engine_test.dart
//
// ⭐ 2026-09-01 - "오늘의 컨디션 예측"(today_forecast_engine.dart) 시나리오
// 검증용. 순수 함수(buildTodayForecast)를 실제 DB/Provider 없이 합성 데이터로
// 호출해서 문구를 눈으로 확인한다(컨디션매니저_설계.md 13-8장이 "0개"라고
// 남겨둔 단위 테스트 숙제의 1차분). `flutter test test/today_forecast_engine_test.dart`
// 로 실행하면 각 시나리오의 결과 문장이 콘솔에 출력된다 - assert는 최소한만
// 걸고(크래시 없이 돌아가는지, 특정 플래그가 기대대로 켜지는지) 나머지는 사람이
// 읽고 판단하는 용도.
//
// 근무 패턴: 주간 07:00~19:00 / 야간 19:00~07:00(자정 넘김), 각 12시간.
// 기본 패턴 "주주휴휴야야휴휴"(8일 주기)에, 대근으로 특정 날짜만
// assignedDates로 덮어써서 "주주주휴야야휴휴"/"주주휴휴야야야휴휴" 같은 변형과
// 6일 이상 연속근무 케이스까지 재현한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_history.dart';
import 'package:shiftbell/services/condition/today_forecast_engine.dart';

const _kDayShift = '주간';
const _kNightShift = '야간';
const _kOff = '휴무';

// 8일 주기: 주주휴휴야야휴휴
const List<String> _basePattern = [
  _kDayShift, _kDayShift, _kOff, _kOff, _kNightShift, _kNightShift, _kOff, _kOff,
];

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [todayIndex]는 오늘이 _basePattern의 몇 번째 자리인지(0~7). [overrides]는
/// 오늘 기준 offset(0=오늘, -1=어제, +1=내일 ...) -> 근무명으로, 대근 등
/// 예외를 assignedDates로 덮어씀(실제 앱의 대근 매커니즘과 동일한 방식).
ShiftSchedule _buildSchedule(
  DateTime today, {
  required int todayIndex,
  Map<int, String> overrides = const {},
}) {
  final assignedDates = <String, String>{};
  overrides.forEach((offset, name) {
    assignedDates[_dateKey(today.add(Duration(days: offset)))] = name;
  });
  return ShiftSchedule(
    isRegular: true,
    pattern: _basePattern,
    todayIndex: todayIndex,
    startDate: today,
    shiftTypes: const [_kDayShift, _kNightShift, _kOff],
    assignedDates: assignedDates.isEmpty ? null : assignedDates,
  );
}

final _shiftTimes = <String, ShiftTimeRange>{
  _kDayShift: const ShiftTimeRange(shiftName: _kDayShift, startMinutes: 7 * 60, endMinutes: 19 * 60),
  _kNightShift: const ShiftTimeRange(shiftName: _kNightShift, startMinutes: 19 * 60, endMinutes: 7 * 60),
};

ShiftPatternAnalyzer _analyzerFor(DateTime today, {required int todayIndex, Map<int, String> overrides = const {}}) {
  final schedule = _buildSchedule(today, todayIndex: todayIndex, overrides: overrides);
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);
}

class _ScenarioResult {
  final TodayForecast forecast;
  final ConditionResult baseResult;
  const _ScenarioResult(this.forecast, this.baseResult);
}

_ScenarioResult _run({
  required DateTime today,
  required int todayIndex,
  Map<int, String> overrides = const {},
  Map<String, int> otMinutesByDate = const {},
  List<SleepRecord> sleepRecords = const [],
}) {
  final analyzer = _analyzerFor(today, todayIndex: todayIndex, overrides: overrides);
  final baseResult = ConditionRuleEngine(analyzer).evaluate(today);
  final nights = collectRecentWorkNights(analyzer: analyzer, records: sleepRecords, referenceDate: today);
  final patterns = buildPersonalSleepPatterns(nights);
  final forecast = buildTodayForecast(
    baseResult: baseResult,
    analyzer: analyzer,
    nights: nights,
    personalPatterns: patterns,
    otMinutesByDate: otMinutesByDate,
    today: today,
  );
  return _ScenarioResult(forecast, baseResult);
}

void _printScenario(String title, _ScenarioResult r) {
  // ignore: avoid_print
  print('\n=== $title ===');
  // ignore: avoid_print
  print('consecutiveWorkDays(baseResult) = ${r.baseResult.consecutiveWorkDays}');
  // ignore: avoid_print
  print('consecutiveNightDays(baseResult) = ${r.baseResult.consecutiveNightDays}');
  // ignore: avoid_print
  print('메시지: ${r.forecast.message}');
  // ignore: avoid_print
  print('evidenceIds: ${r.forecast.evidenceIds}');
}

void main() {
  // 재현성을 위해 고정 날짜 사용(요일 자체는 로직에 영향 없음).
  final today = DateTime(2026, 9, 6);

  test('시나리오1 - 평상시(오늘=두번째 주간), 이상 신호 없어야 함', () {
    final r = _run(today: today, todayIndex: 1);
    _printScenario('1. 평상시(주주휴휴야야휴휴, 오늘=주간 2일차)', r);
  });

  test('시나리오2 - 평상시(오늘=첫 야간)', () {
    final r = _run(today: today, todayIndex: 4);
    _printScenario('2. 평상시(오늘=야간 1일차)', r);
  });

  test('시나리오3 - 대근으로 야간 3연속(주주휴휴야야야휴휴, 오늘=extra 야간)', () {
    // base index6은 원래 휴무 -> 오늘만 야간으로 대근 override, 앞의 인덱스4,5는
    // 이미 야간이라 결과적으로 야간 3연속(어제/그제/오늘)이 됨.
    final r = _run(today: today, todayIndex: 6, overrides: {0: _kNightShift});
    _printScenario('3. 대근: 야간 3연속(주주휴휴야야[야]휴휴)', r);
    expect(r.forecast.message.contains('야간'), true, reason: '야간 빈도 신호가 문구에 반영돼야 함');
  });

  test('시나리오4 - 대근으로 주간 3연속(주주주휴야야휴휴, 오늘=extra 주간)', () {
    // base index2는 원래 휴무 -> 오늘만 주간으로 대근 override.
    final r = _run(today: today, todayIndex: 2, overrides: {0: _kDayShift});
    _printScenario('4. 대근: 주간 3연속(주[주]주휴야야휴휴, 오늘=3번째 주간)', r);
  });

  test('시나리오5 - 6일 연속근무(5일 창 너머까지 정확히 잡히는지 확인)', () {
    // offset -6 = 휴무(스트릭 끊는 지점), -5..0 = 6일 연속 근무.
    final r = _run(
      today: today,
      todayIndex: 0, // base pattern은 override로 전부 덮어써서 의미 없음
      overrides: {
        -6: _kOff,
        -5: _kNightShift,
        -4: _kDayShift,
        -3: _kNightShift,
        -2: _kDayShift,
        -1: _kNightShift,
        0: _kDayShift,
      },
    );
    _printScenario('5a. 6일 연속근무(오프셋-7일째=휴무로 스트릭 캡)', r);
    expect(r.baseResult.consecutiveWorkDays, 6, reason: '5일 창을 넘어선 6일 연속근무도 정확히 잡혀야 함');
    expect(r.forecast.message.contains('연속'), true, reason: '연속근무 신호가 문구에 반영돼야 함');
  });

  test('시나리오5b - 7일 연속근무(경계 하나 더 늘려서 재확인)', () {
    final r = _run(
      today: today,
      todayIndex: 0,
      overrides: {
        -7: _kOff,
        -6: _kNightShift,
        -5: _kDayShift,
        -4: _kNightShift,
        -3: _kDayShift,
        -2: _kNightShift,
        -1: _kDayShift,
        0: _kNightShift,
      },
    );
    _printScenario('5b. 7일 연속근무(오프셋-8일째=휴무로 스트릭 캡)', r);
    expect(r.baseResult.consecutiveWorkDays, 7);
  });

  test('시나리오6a - OT 3시간(사소한 수준, 문구 안 바뀌어야 함)', () {
    final base = _run(today: today, todayIndex: 1);
    final withOt = _run(
      today: today,
      todayIndex: 1,
      otMinutesByDate: {_dateKey(today.subtract(const Duration(days: 2))): 3 * 60},
    );
    _printScenario('6a-기준(OT 없음)', base);
    _printScenario('6a-OT 3시간', withOt);
  });

  test('시나리오6b - OT 8시간(유의미한 수준, 문구 바뀌어야 함)', () {
    final r = _run(
      today: today,
      todayIndex: 1,
      otMinutesByDate: {_dateKey(today.subtract(const Duration(days: 2))): 8 * 60},
    );
    _printScenario('6b. OT 8시간(휴무일에 몰아서)', r);
    expect(r.forecast.message.contains('초과근무'), true, reason: 'OT 8시간이면 초과근무 신호가 떠야 함');
  });

  test('시나리오7 - 다중 요인(연속근무+야간빈도+OT) 겹쳤을 때 정제된 출력인지 확인', () {
    final r = _run(
      today: today,
      todayIndex: 0,
      overrides: {
        -6: _kOff,
        -5: _kNightShift,
        -4: _kNightShift,
        -3: _kNightShift,
        -2: _kNightShift,
        -1: _kNightShift,
        0: _kNightShift, // 6일 연속 야간 - workStreak + nightFrequency 동시 트리거
      },
      otMinutesByDate: {_dateKey(today.subtract(const Duration(days: 1))): 8 * 60}, // + OT
    );
    _printScenario('7. 다중 요인 겹침(6일 연속 야간 + OT 8시간)', r);
    final sentenceCount = '.'.allMatches(r.forecast.message).length; // 대략적인 문장 수
    // ignore: avoid_print
    print('대략적인 문장 개수: $sentenceCount');
  });

  test('시나리오8 - 수면 기록 전무(재프레이밍 문구 확인)', () {
    final r = _run(today: today, todayIndex: 1);
    _printScenario('8. 수면 기록 없음', r);
    expect(r.forecast.message.contains('기록'), true);
  });

  test('시나리오9 - 최근 수면 부족(2건 이상, 평균 7시간 미만)', () {
    // todayIndex=4(오늘=첫 야간)면 offset -1(index3)=휴무, offset -2(index2)=휴무,
    // offset -3(index1)=주간, offset -4(index0)=주간이라 실제 근무일의 퇴근
    // 시각을 analyzer에서 직접 뽑아 정확히 그 뒤에 수면을 붙인다(하드코딩 시각
    // 추정 대신 - 패턴이 바뀌어도 항상 맞게).
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final workDay1 = analyzer.instanceForDate(today.subtract(const Duration(days: 4))); // 주간
    final workDay2 = analyzer.instanceForDate(today.subtract(const Duration(days: 3))); // 주간
    final records = [
      SleepRecord(
        start: workDay1.end!.add(const Duration(minutes: 30)),
        end: workDay1.end!.add(const Duration(minutes: 30 + 4 * 60)), // 4시간만 수면
        source: SleepSource.manual,
        status: SleepStatus.confirmed,
      ),
      SleepRecord(
        start: workDay2.end!.add(const Duration(minutes: 30)),
        end: workDay2.end!.add(const Duration(minutes: 30 + 5 * 60)), // 5시간만 수면
        source: SleepSource.manual,
        status: SleepStatus.confirmed,
      ),
    ];
    final r = _run(today: today, todayIndex: 4, sleepRecords: records);
    _printScenario('9. 최근 수면 부족(4h/5h, 최근 근무일 이틀 뒤)', r);
    // ⭐ 2026-09-01 후속20(사용자 지적: "69점인데 근무 얘기가 아예 없어서
    // 왜 이 점수인지 감이 안 온다") - 수면만 문제고 근무 패턴(연속근무일수 등)은
    // 문제없을 때, "근무는 괜찮았다"는 균형 잡힌 문구가 같이 나와야 함.
    // 이 시나리오는 today=첫 야간, 어제/그제=휴무라 연속근무일수가 짧으므로
    // "회복할 시간은 챙겼다"류 문구(stable_work_short_streak)가 붙어야 정상.
    expect(
      r.forecast.message.contains('회복할 시간') ||
          r.forecast.message.contains('여유가 있었을') ||
          r.forecast.message.contains('부담이 크게 쌓이진'),
      true,
      reason: '수면만 문제고 근무 패턴 자체는 괜찮았다는 균형 문구가 있어야 함',
    );
  });
}
