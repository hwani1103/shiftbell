// test/condition_baseline_load_test.dart
//
// ⭐ 2026-09-18 - 개인 기준선(ShiftPatternAnalyzer.baselineWeeklyMinutesAsOf) +
// RULE_WEEKLY_LOAD_INCREASE(개인 기준선 대비 증가폭) 재설계 회귀 테스트.
//
// 계기: RULE_WEEKLY_TOTAL_LOAD(구 이름)가 최근 7일 실근무시간을 EU 48시간/IOM
// 60시간 절대값과 비교했는데, 12시간 표준 근무자는 구조적으로 주 48~60시간이
// 정상이라 "보통인 날"이 하루도 없었음(실측: 3조2교대 8주 시뮬레이션 NORMAL 0%,
// 2교대 주주주야야야휴휴휴 8주 시뮬레이션 NORMAL 0%). 개인 기준선(이 스케줄
// 자체의 구조적 평균) 대비 "얼마나 늘었는지"로 바꿔서, 표준 근무시간 자체가
// 아니라 "평소보다 실제로 늘었는지"만 신호로 삼는다.
//
// ⚠️ 아래 5개 패턴은 실제 한국 교대 근무 형태를 대표한다(사용자 검증에 쓰인 것과
// 동일). "며칠 몰아 일하고 몰아 쉬는" 블록형 패턴(P3)은 트레일링 7일 창의 위상에
// 따라 같은 스케줄 안에서도 "유난히 밀도가 높은 주"가 실제로 존재할 수 있다는
// 것이 수학적으로 불가피하다(장기 평균은 기준선과 같아도, 3일 근무+3일 근무를
// 연달아 배치하면 그 이음매에 걸리는 7일 창은 6일 연속 12시간 근무를 통째로
// 담아 장기 평균보다 훨씬 높아짐) - 이건 버그가 아니라 "이 사이클 안에서도 유난히
// 빡빡한 주"를 정확히 잡아내는 의도된 동작이다(아래 그룹 2 참고).

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';

const _kDay = '주간';
const _kEvening = '오후';
const _kNight = '야간';
const _kOff = '휴무';

const _times12h = {
  _kDay: ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60),
  _kNight: ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60),
};
const _times8h = {
  _kDay: ShiftTimeRange(shiftName: _kDay, startMinutes: 6 * 60, endMinutes: 14 * 60),
  _kEvening: ShiftTimeRange(shiftName: _kEvening, startMinutes: 14 * 60, endMinutes: 22 * 60),
  _kNight: ShiftTimeRange(shiftName: _kNight, startMinutes: 22 * 60, endMinutes: 6 * 60),
};

// 5개 대표 패턴
const _p1ThreeGroupTwoShift = [_kDay, _kDay, _kNight, _kNight, _kOff, _kOff]; // 3조2교대, 6일주기, 12h
const _p2FourGroupTwoShift = [_kDay, _kDay, _kNight, _kNight, _kOff, _kOff, _kOff, _kOff]; // 4조2교대, 8일주기, 12h
const _p3TwoShift = [_kDay, _kDay, _kDay, _kNight, _kNight, _kNight, _kOff, _kOff, _kOff]; // 2교대, 9일주기, 12h(3+3 블록)
const _p4FourGroupThreeShift = [_kDay, _kDay, _kEvening, _kEvening, _kNight, _kNight, _kOff, _kOff]; // 4조3교대, 8일주기, 8h
final _p5ThreeGroupThreeShift = [
  ...List.filled(5, _kDay), _kOff, _kOff,
  ...List.filled(5, _kEvening), _kOff, _kOff,
  ...List.filled(5, _kNight), _kOff, _kOff,
]; // 3조3교대(5근무2휴×3조), 21일주기, 8h

ShiftPatternAnalyzer _regularAnalyzer(List<String> pattern, Map<String, ShiftTimeRange> times, {DateTime? startDate, int todayIndex = 0}) {
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: pattern,
    todayIndex: todayIndex,
    startDate: startDate ?? DateTime(2026, 1, 1),
    shiftTypes: pattern.toSet().toList(),
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
}

String _isoDay(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String().split('T')[0];

/// 불규칙 스케줄(assignedDates만으로 실제 배정된 날을 만듦 - isRegular:false는
/// pattern을 아예 안 봄, shift_schedule.dart의 getShiftForDate 참고).
ShiftPatternAnalyzer _irregularAnalyzer(Map<DateTime, String> assignedByDate, Map<String, ShiftTimeRange> times) {
  final assigned = {for (final e in assignedByDate.entries) _isoDay(e.key): e.value};
  final schedule = ShiftSchedule(
    isRegular: false,
    shiftTypes: assignedByDate.values.toSet().toList(),
    assignedDates: assigned,
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
}

void main() {
  group('개인 기준선 계산(baselineWeeklyMinutesAsOf)', () {
    test('규칙적 - 짧은 주기(3조2교대 6일, 12h×4일/6일*7=56시간)', () {
      final a = _regularAnalyzer(_p1ThreeGroupTwoShift, _times12h);
      expect(a.baselineWeeklyMinutesAsOf(DateTime(2026, 1, 1)), 56 * 60);
    });

    test('규칙적 - 긴 주기(3조3교대 21일, 8h×15일/21일*7=40시간)', () {
      final a = _regularAnalyzer(_p5ThreeGroupThreeShift, _times8h);
      expect(a.baselineWeeklyMinutesAsOf(DateTime(2026, 1, 1)), 40 * 60);
    });

    test('불규칙 - 배정된 날이 21일 미만이면 판단 근거 부족으로 null', () {
      final today = DateTime(2026, 6, 15);
      final assigned = <DateTime, String>{
        for (var i = 1; i <= 10; i++) today.subtract(Duration(days: i)): _kDay, // 10일뿐(21일 미만)
      };
      final a = _irregularAnalyzer(assigned, _times8h);
      expect(a.baselineWeeklyMinutesAsOf(today), isNull);
    });

    test('불규칙 - 배정된 날이 21일 이상이면 실측 평균×7', () {
      final today = DateTime(2026, 6, 15);
      final assigned = <DateTime, String>{
        for (var i = 1; i <= 21; i++) today.subtract(Duration(days: i)): _kDay, // 21일, 전부 8시간 근무
      };
      final a = _irregularAnalyzer(assigned, _times8h);
      // 21일 모두 8시간 근무 → 평균 480분/일 × 7 = 3360분(56시간).
      expect(a.baselineWeeklyMinutesAsOf(today), 56 * 60);
    });
  });

  group('회귀 - 정상 패턴은 개인 기준선 대비 조용해야 함(P0 핵심 검증)', () {
    void expectNeverFires(String label, List<String> pattern, Map<String, ShiftTimeRange> times, int cycles) {
      final start = DateTime(2026, 1, 1);
      final a = _regularAnalyzer(pattern, times, startDate: start);
      final engine = ConditionRuleEngine(a);
      for (var i = 0; i < pattern.length * cycles; i++) {
        final d = start.add(Duration(days: i));
        final r = engine.evaluate(d);
        expect(
          r.levelFindings.any((f) => f.ruleId == 'RULE_WEEKLY_LOAD_INCREASE'),
          isFalse,
          reason: '$label - ${i + 1}일차(패턴 내 ${i % pattern.length}번째)에 개인 기준선 신호가 부당하게 발동함',
        );
      }
    }

    test('3조2교대(6일,12h) - 3주기 내내 조용함', () {
      expectNeverFires('3조2교대', _p1ThreeGroupTwoShift, _times12h, 3);
    });
    test('4조2교대(8일,12h) - 3주기 내내 조용함', () {
      expectNeverFires('4조2교대', _p2FourGroupTwoShift, _times12h, 3);
    });
    test('4조3교대(8일,8h) - 3주기 내내 조용함', () {
      expectNeverFires('4조3교대', _p4FourGroupThreeShift, _times8h, 3);
    });
    test('3조3교대(21일,8h) - 2주기 내내 조용함', () {
      expectNeverFires('3조3교대', _p5ThreeGroupThreeShift, _times8h, 2);
    });

    test('2교대(9일,12h, 3+3 블록) - 대부분 조용하지만 이음매(같은 유형 3일 근무가 막 끝난 주)는 실제로 밀도가 높아 발동한다', () {
      // ⭐ 이 패턴은 3일 주간+3일 야간을 연달아 배치해서, 그 이음매에 걸리는 7일
      // 트레일링 창은 최대 6일 연속 12시간 근무(72시간)를 통째로 담는다(기준선은
      // 56시간 - 장기 평균은 같아도 이 사이클 안에서 유난히 빡빡한 주가 실재함).
      // 9일 주기 중 정확히 2일(패턴 내 5·6번째 날)에서만 발동하고 나머지 7일은
      // 조용해야 한다 - "며칠 몰아 일하면 실제로 힘든 주로 잡힌다"는 걸 보여주는
      // 의도된 동작이라 P0의 "구조적으로 조용해야 함" 원칙 위반이 아니다(구조적
      // 표준 근무시간 자체가 아니라 그 안에서의 국소적 밀집을 잡는 것).
      final start = DateTime(2026, 1, 1);
      final a = _regularAnalyzer(_p3TwoShift, _times12h, startDate: start);
      final engine = ConditionRuleEngine(a);
      final firedOffsets = <int>{};
      for (var i = 0; i < _p3TwoShift.length * 3; i++) {
        final d = start.add(Duration(days: i));
        final r = engine.evaluate(d);
        if (r.levelFindings.any((f) => f.ruleId == 'RULE_WEEKLY_LOAD_INCREASE')) {
          firedOffsets.add(i % _p3TwoShift.length);
        }
      }
      expect(firedOffsets, {5, 6});
    });
  });

  group('양성 대조군 - 실제로 늘어나면 신호가 살아있어야 함', () {
    test('평소 조용한 4조2교대 패턴도 근무변경(휴무→근무)이 생기면 발동한다', () {
      final start = DateTime(2026, 1, 1);
      final a = _regularAnalyzer(_p2FourGroupTwoShift, _times12h, startDate: start);
      // 패턴상 휴무인 날 하나를 달력에서 12시간 근무로 바꿈(assignedDates 예외 -
      // baselineWeeklyMinutesAsOf는 패턴 자체만 보므로 기준선(42시간)은 그대로,
      // 실제 주간 총량만 늘어난다).
      final target = start.add(const Duration(days: 4)); // 패턴 index4 = 휴무
      a.schedule.assignedDates = {_isoDay(target): _kDay};
      final result = ConditionRuleEngine(a).evaluate(start.add(const Duration(days: 6)));
      expect(result.levelFindings.any((f) => f.ruleId == 'RULE_WEEKLY_LOAD_INCREASE'), isTrue);
    });

    test('평소 조용한 3조2교대 패턴도 초과근무가 충분히 쌓이면 발동한다', () {
      final start = DateTime(2026, 1, 1);
      final a = _regularAnalyzer(_p1ThreeGroupTwoShift, _times12h, startDate: start);
      // 패턴 index2(야간)를 오늘로 잡으면 이 위상의 트레일링 7일 실제 근무일이 5일
      // (야간·주간·주간·야간·야간)이라 기본근무만 60시간(기준선 56시간보다 이미 4시간
      // 많음) - 여기에 초과근무 10시간을 더하면 기준선보다 14시간 많아져(임계값
      // 8.4시간) 확실히 발동한다.
      final today = start.add(const Duration(days: 2));
      String dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final ot = {dateKey(today): 10 * 60};
      final result = ConditionRuleEngine(a).evaluate(today, otMinutesByDate: ot);
      expect(result.levelFindings.any((f) => f.ruleId == 'RULE_WEEKLY_LOAD_INCREASE'), isTrue);
    });
  });

  group('총량 동등성 - 하루 근무시간이 달라도 각자 기준선 대비로는 비슷하게 평가된다', () {
    test('12시간×3일/7일 근무자와 8시간×5일/7일 근무자 둘 다 자기 기준선 그대로라 조용함', () {
      // 둘 다 7일 주기라 실제(actual)와 기준선(baseline)이 위상과 무관하게 항상
      // 정확히 일치한다(period==window길이) - "표준 근무시간이 다르다"는 이유만으로
      // 다르게 평가되지 않는다는 걸 baseline 필드로 직접 확인한다.
      final p12 = [_kDay, _kDay, _kDay, _kOff, _kOff, _kOff, _kOff]; // 주 36시간
      final p8 = [_kDay, _kDay, _kDay, _kDay, _kDay, _kOff, _kOff]; // 주 40시간(8시간짜리로 재사용)
      final times8hDayOnly = {_kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 9 * 60, endMinutes: 17 * 60)};
      final today = DateTime(2026, 1, 10);

      final a12 = _regularAnalyzer(p12, _times12h, startDate: today, todayIndex: 2);
      final a8 = _regularAnalyzer(p8, times8hDayOnly, startDate: today, todayIndex: 4);

      expect(a12.baselineWeeklyMinutesAsOf(today), 36 * 60);
      expect(a8.baselineWeeklyMinutesAsOf(today), 40 * 60);

      final r12 = ConditionRuleEngine(a12).evaluate(today);
      final r8 = ConditionRuleEngine(a8).evaluate(today);
      expect(r12.levelFindings.any((f) => f.ruleId == 'RULE_WEEKLY_LOAD_INCREASE'), isFalse);
      expect(r8.levelFindings.any((f) => f.ruleId == 'RULE_WEEKLY_LOAD_INCREASE'), isFalse);
    });
  });
}
