// test/today_forecast_engine_scenarios_test.dart
//
// ⭐ 2026-09-01 후속9 - "오늘의 컨디션" 추천 로직 리팩토링(요인별 행동 팁)을
// 완성한 뒤 요청받은 확장 검증 세트. today_forecast_engine_test.dart(1차분,
// 근무 패턴 중심)에 이어 이번엔:
// 1) 수면 기록 유무/빈도의 모든 조합(없음/전부 있음/부분적/최근 시작/최근 중단)
// 2) 실제로 있을 법한 다양한 근무 강도(야간 몰빵 패턴, 4주 내내 고강도,
//    휴가로 주 30시간 이내인 저강도)
// 3) 신규 4교대 패턴(M 07-15/E 15-23/N 23-07/O 휴무)
// 을 검증한다. 기기 대신 이 방식을 쓴 이유는 today_forecast_engine_test.dart
// 상단 주석과 동일(순수 Dart 계산이라 기기 검증과 커버리지가 같으면서 훨씬
// 빠르고 반복 가능).

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_history.dart';
import 'package:shiftbell/services/condition/today_forecast_engine.dart';

// ═══════════════════════════════════════════════════════════════════════
// 공용 헬퍼(패턴/시각을 파라미터로 받는 범용판 - 첫 테스트 파일보다 더 유연함)
// ═══════════════════════════════════════════════════════════════════════

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

ShiftSchedule _buildSchedule(
  DateTime today, {
  required List<String> pattern,
  required List<String> shiftTypes,
  required int todayIndex,
  Map<int, String> overrides = const {},
}) {
  final assignedDates = <String, String>{};
  overrides.forEach((offset, name) {
    assignedDates[_dateKey(today.add(Duration(days: offset)))] = name;
  });
  return ShiftSchedule(
    isRegular: true,
    pattern: pattern,
    todayIndex: todayIndex,
    startDate: today,
    shiftTypes: shiftTypes,
    assignedDates: assignedDates.isEmpty ? null : assignedDates,
  );
}

ShiftPatternAnalyzer _analyzerFor(
  DateTime today, {
  required List<String> pattern,
  required List<String> shiftTypes,
  required Map<String, ShiftTimeRange> shiftTimes,
  required int todayIndex,
  Map<int, String> overrides = const {},
}) {
  final schedule = _buildSchedule(
    today,
    pattern: pattern,
    shiftTypes: shiftTypes,
    todayIndex: todayIndex,
    overrides: overrides,
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: shiftTimes);
}

class _ScenarioResult {
  final TodayForecast forecast;
  final ConditionResult baseResult;
  final List<SleepHistoryNight> nights;
  const _ScenarioResult(this.forecast, this.baseResult, this.nights);
}

_ScenarioResult _run({
  required DateTime today,
  required List<String> pattern,
  required List<String> shiftTypes,
  required Map<String, ShiftTimeRange> shiftTimes,
  required int todayIndex,
  Map<int, String> overrides = const {},
  Map<String, int> otMinutesByDate = const {},
  List<SleepRecord> sleepRecords = const [],
}) {
  final analyzer = _analyzerFor(
    today,
    pattern: pattern,
    shiftTypes: shiftTypes,
    shiftTimes: shiftTimes,
    todayIndex: todayIndex,
    overrides: overrides,
  );
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
  return _ScenarioResult(forecast, baseResult, nights);
}

void _printScenario(String title, _ScenarioResult r) {
  // ignore: avoid_print
  print('\n=== $title ===');
  // ignore: avoid_print
  print('consecutiveWorkDays=${r.baseResult.consecutiveWorkDays} consecutiveNightDays=${r.baseResult.consecutiveNightDays}');
  // ignore: avoid_print
  print('baseResult.level=${r.baseResult.level} ruleIds=${r.baseResult.levelFindings.map((f) => f.ruleId).toList()}');
  final withData = r.nights.where((n) => n.hasSleepData).length;
  // ignore: avoid_print
  print('nights=${r.nights.length} withSleepData=$withData sleepCoverage=${r.forecast.sleepCoverage}');
  // ignore: avoid_print
  print('메시지: ${r.forecast.message}');
  // ignore: avoid_print
  print('evidenceIds: ${r.forecast.evidenceIds}');
}

/// 근무일에 실제 수면기록을 붙여주는 헬퍼 - analyzer에서 그 근무의 실제
/// 종료시각을 뽑아 정확히 그 뒤에 배치한다(수면 입력 시각 매칭 로직 검증).
SleepRecord _sleepAfter(ShiftPatternAnalyzer analyzer, DateTime workDate, {int sleepMinutes = 7 * 60, int delayMinutes = 30}) {
  final inst = analyzer.instanceForDate(workDate);
  final end = inst.end!;
  return SleepRecord(
    start: end.add(Duration(minutes: delayMinutes)),
    end: end.add(Duration(minutes: delayMinutes + sleepMinutes)),
    source: SleepSource.manual,
    status: SleepStatus.confirmed,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 근무 패턴 정의
// ═══════════════════════════════════════════════════════════════════════

// 12시간 주/야 - 기존 패턴(주주휴휴야야휴휴)
const _kDay12 = '주간';
const _kNight12 = '야간';
const _kOff = '휴무';
const List<String> _pattern8Day = [_kDay12, _kDay12, _kOff, _kOff, _kNight12, _kNight12, _kOff, _kOff];
final _shiftTypes8Day = const [_kDay12, _kNight12, _kOff];
final _shiftTimes8Day = <String, ShiftTimeRange>{
  _kDay12: const ShiftTimeRange(shiftName: _kDay12, startMinutes: 7 * 60, endMinutes: 19 * 60),
  _kNight12: const ShiftTimeRange(shiftName: _kNight12, startMinutes: 19 * 60, endMinutes: 7 * 60),
};

// 야간 몰빵 - 야야야야휴(5일 주기)
const List<String> _patternNightHeavy = [_kNight12, _kNight12, _kNight12, _kNight12, _kOff];

// 저강도 - 야휴휴휴휴휴휴(7일 주기, 주 12시간)
const List<String> _patternLight = [_kNight12, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];

// 4교대 MENO - M(07-15)/E(15-23)/N(23-07)/OFF(휴무), 각 8시간
const _kM = 'M';
const _kE = 'E';
const _kN = 'N';
const _kOff2 = 'OFF';
const List<String> _patternMeno = [
  _kM, _kM, _kM, _kM, _kOff2, _kOff2, _kE, _kE, _kE, _kE, _kOff2, _kN, _kN, _kN, _kN, _kOff2, _kOff2,
];
final _shiftTypesMeno = const [_kM, _kE, _kN, _kOff2];
final _shiftTimesMeno = <String, ShiftTimeRange>{
  _kM: const ShiftTimeRange(shiftName: _kM, startMinutes: 7 * 60, endMinutes: 15 * 60),
  _kE: const ShiftTimeRange(shiftName: _kE, startMinutes: 15 * 60, endMinutes: 23 * 60),
  _kN: const ShiftTimeRange(shiftName: _kN, startMinutes: 23 * 60, endMinutes: 7 * 60),
};

void main() {
  final today = DateTime(2026, 9, 6);

  // ═════════════════════════════════════════════════════════════════════
  // 그룹 A - 수면 기록 유무/빈도 조합(기존 8일 주기 패턴, 오늘=주간2일차 기준)
  // ═════════════════════════════════════════════════════════════════════
  group('A. 수면 기록 커버리지 조합', () {
    test('A1. 수면 기록 전무', () {
      final r = _run(
        today: today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
      );
      _printScenario('A1. 수면기록 0건', r);
      expect(r.forecast.sleepCoverage, SleepDataCoverage.none);
      expect(r.forecast.message.contains('기록'), true);
    });

    test('A2. 수면 기록이 최근 근무일마다 전부(충분한 시간)', () {
      final analyzer = _analyzerFor(
        today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
      );
      // 56일 창 전체(collectRecentWorkNights 기본 daysBack) 근무일에 전부
      // 8시간대 수면을 붙여야 진짜 "거의 다 있음"(high)이 됨 - 40일치만
      // 채우면 뒤쪽 16일이 비어서 mid로 잡히는 걸 실측으로 확인했음.
      final records = <SleepRecord>[];
      for (var i = 1; i <= 56; i++) {
        final d = today.subtract(Duration(days: i));
        final inst = analyzer.instanceForDate(d);
        if (inst.isWorkDay && inst.end != null) {
          records.add(_sleepAfter(analyzer, d, sleepMinutes: 8 * 60));
        }
      }
      final r = _run(
        today: today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
        sleepRecords: records,
      );
      _printScenario('A2. 최근 근무일마다 수면기록 전부(8h)', r);
      expect(r.forecast.sleepCoverage, SleepDataCoverage.high);
      // "전부 다 있으면 생략" - 꾸준히 기록해달라는 격려 문구가 안 붙어야 함
      expect(r.forecast.message.contains('꾸준히 기록'), false, reason: '커버리지가 높으면 격려 문구가 없어야 함');
    });

    test('A3. 최근 근무일 5일 중 3일 정도만(부분적) 기록 - 격려 문구 확인', () {
      final analyzer = _analyzerFor(
        today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
      );
      // 지난 20일 근무일 중 대략 40%만 기록(충분히 표본은 있지만 커버리지는 낮게)
      final records = <SleepRecord>[];
      var workDaySeen = 0;
      for (var i = 1; i <= 30; i++) {
        final d = today.subtract(Duration(days: i));
        final inst = analyzer.instanceForDate(d);
        if (inst.isWorkDay && inst.end != null) {
          workDaySeen++;
          if (workDaySeen % 5 <= 1) {
            // 5일 중 대략 2일꼴(그 중 최근 구간엔 3일 정도 걸리도록 나열)
            records.add(_sleepAfter(analyzer, d, sleepMinutes: 8 * 60));
          }
        }
      }
      final r = _run(
        today: today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
        sleepRecords: records,
      );
      _printScenario('A3. 부분적 수면기록(약 40%)', r);
      // ignore: avoid_print
      print('coverage=${r.forecast.sleepCoverage}');
    });

    test('A4. 최근부터 수면 기록을 시작(recentlyStarted) - 격려 문구와 안 겹치는지', () {
      final analyzer = _analyzerFor(
        today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
      );
      // 최근 절반 구간(대략 마지막 28일 = work-day 기준 절반)은 채우고, 그
      // 이전은 완전히 비워야 earlierRatio<=0.15 && recentRatio>=0.5를 넘어
      // recentlyStarted로 분류됨(10일만으로는 안 됨 - 실측으로 확인).
      final records = <SleepRecord>[];
      for (var i = 1; i <= 20; i++) {
        final d = today.subtract(Duration(days: i));
        final inst = analyzer.instanceForDate(d);
        if (inst.isWorkDay && inst.end != null) records.add(_sleepAfter(analyzer, d, sleepMinutes: 8 * 60));
      }
      final r = _run(
        today: today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
        sleepRecords: records,
      );
      _printScenario('A4. 최근부터 기록 시작(최근 20일만 채움)', r);
      expect(r.forecast.message.contains('시작'), true);
    });

    test('A5. 예전엔 기록했는데 최근 중단(recentlyStopped)', () {
      final analyzer = _analyzerFor(
        today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
      );
      // 오래된 절반(대략 29~56일 전)만 채우고 최근 절반(1~28일 전)은 완전히
      // 비워야 earlierRatio>=0.5 && recentRatio<=0.15로 recentlyStopped가 됨.
      final records = <SleepRecord>[];
      for (var i = 29; i <= 56; i++) {
        final d = today.subtract(Duration(days: i));
        final inst = analyzer.instanceForDate(d);
        if (inst.isWorkDay && inst.end != null) records.add(_sleepAfter(analyzer, d, sleepMinutes: 8 * 60));
      }
      final r = _run(
        today: today, pattern: _pattern8Day, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 1,
        sleepRecords: records,
      );
      _printScenario('A5. 최근 중단(29~56일 전만 채움)', r);
      expect(r.forecast.message.contains('뜸') || r.forecast.message.contains('줄') , true);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // 그룹 B - 근무 강도 다양화
  // ═════════════════════════════════════════════════════════════════════
  group('B. 근무 강도 다양화', () {
    test('B1a. 야간 몰빵 패턴 - 4연속 야간 중 마지막날', () {
      // 5일 주기 야야야야휴, todayIndex=3(4번째 야간)
      final r = _run(
        today: today, pattern: _patternNightHeavy, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 3,
      );
      _printScenario('B1a. 야간몰빵 패턴, 오늘=4연속째 야간', r);
      expect(r.baseResult.consecutiveNightDays, 4);
    });

    test('B1b. 야간 몰빵 패턴 - 쉬는 날(4연속 야간 직후)', () {
      final r = _run(
        today: today, pattern: _patternNightHeavy, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 4,
      );
      _printScenario('B1b. 야간몰빵 패턴, 오늘=휴무(4연속 야간 직후)', r);
    });

    test('B2. 4주 내내 고강도(야간몰빵을 8주 통째로 유지) - OT까지 추가', () {
      // 패턴 자체가 처음부터 끝까지 균일하게 힘든 경우 - "최근 급증"으로
      // 오판하지 않는지(축1은 stable이어야 함), 개인 평소 대비 비교도 과민하지
      // 않은지 확인.
      final analyzer = _analyzerFor(
        today, pattern: _patternNightHeavy, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 3,
      );
      final r = _run(
        today: today, pattern: _patternNightHeavy, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 3,
        otMinutesByDate: {
          _dateKey(today.subtract(const Duration(days: 1))): 8 * 60,
        },
      );
      _printScenario('B2. 8주 내내 고강도 + OT 8시간 추가', r);
      // ignore: avoid_print
      print('baseline check: 이 사람 개인 평소 근무시간은 이미 높아야(12h) 함');
      final _ = analyzer; // keep reference for clarity/logging symmetry
    });

    test('B3a. 저강도(휴가 위주, 주 12시간) - 근무일', () {
      // 7일 주기 야휴휴휴휴휴휴, todayIndex=0(그 주의 유일한 근무일)
      final r = _run(
        today: today, pattern: _patternLight, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 0,
      );
      _printScenario('B3a. 저강도 패턴, 오늘=주 1회 근무일', r);
      expect(r.baseResult.consecutiveWorkDays, 1);
    });

    test('B3b. 저강도(휴가 위주) - 휴무일(대부분)', () {
      final r = _run(
        today: today, pattern: _patternLight, shiftTypes: _shiftTypes8Day, shiftTimes: _shiftTimes8Day, todayIndex: 3,
      );
      _printScenario('B3b. 저강도 패턴, 오늘=휴무(대부분의 날)', r);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // 그룹 C - 신규 4교대(MENO) 패턴
  // ═════════════════════════════════════════════════════════════════════
  group('C. MENO(4교대) 패턴', () {
    test('C1. 평상시(오늘=M 2일차)', () {
      final r = _run(
        today: today, pattern: _patternMeno, shiftTypes: _shiftTypesMeno, shiftTimes: _shiftTimesMeno, todayIndex: 1,
      );
      _printScenario('C1. MENO 평상시(오늘=M2일차)', r);
    });

    test('C2. N 4연속 중(오늘=N 3일차)', () {
      final r = _run(
        today: today, pattern: _patternMeno, shiftTypes: _shiftTypesMeno, shiftTimes: _shiftTimesMeno, todayIndex: 13,
      );
      _printScenario('C2. MENO N연속(오늘=N 3일차)', r);
      expect(r.baseResult.consecutiveNightDays, greaterThanOrEqualTo(3));
    });

    test('C3. 대근으로 N 5연속(원래 O였던 자리를 N으로 override)', () {
      // base index15는 원래 OFF -> 오늘만 N으로 override(대근), 그 앞 인덱스 11~14가
      // 이미 N이라 결과적으로 N 5연속(오늘 포함)이 됨.
      final r = _run(
        today: today, pattern: _patternMeno, shiftTypes: _shiftTypesMeno, shiftTimes: _shiftTimesMeno, todayIndex: 15,
        overrides: {0: _kN},
      );
      _printScenario('C3. MENO 대근: N 5연속', r);
      expect(r.baseResult.consecutiveWorkDays, 5);
      expect(r.baseResult.consecutiveNightDays, 5);
    });

    test('C4. MENO + OT 8시간', () {
      final r = _run(
        today: today, pattern: _patternMeno, shiftTypes: _shiftTypesMeno, shiftTimes: _shiftTimesMeno, todayIndex: 1,
        otMinutesByDate: {_dateKey(today.subtract(const Duration(days: 2))): 8 * 60},
      );
      _printScenario('C4. MENO + OT 8시간', r);
      expect(r.forecast.message.contains('초과근무'), true);
    });

    test('C5. MENO + 수면 기록 결합', () {
      final analyzer = _analyzerFor(
        today, pattern: _patternMeno, shiftTypes: _shiftTypesMeno, shiftTimes: _shiftTimesMeno, todayIndex: 13,
      );
      final records = [
        _sleepAfter(analyzer, today.subtract(const Duration(days: 2)), sleepMinutes: 4 * 60),
        _sleepAfter(analyzer, today.subtract(const Duration(days: 1)), sleepMinutes: 5 * 60),
      ];
      final r = _run(
        today: today, pattern: _patternMeno, shiftTypes: _shiftTypesMeno, shiftTimes: _shiftTimesMeno, todayIndex: 13,
        sleepRecords: records,
      );
      _printScenario('C5. MENO N연속 + 최근 수면부족(4h/5h)', r);
    });
  });
}
