// test/sleep_history_test.dart
//
// ⭐ 2026-09-01 후속12 - 사용자 요청("낮잠 한번/두번 껴서 총 수면시간이
// 충분한 경우도 다 고려해서 분석해줘")으로 발견한 버그 검증. 원래
// collectRecentWorkNights()는 근무 종료 후 "가장 이른" 수면 1건의 길이만
// 그 밤의 수면시간으로 썼음 - 짧은 낮잠을 먼저 자고 몇 시간 뒤 긴 메인
// 수면을 또 잔 경우, 실제 총 수면은 충분한데도 "짧게 잤다"로 잘못 판정되는
// 버그가 있었음. sleep_history.dart를 고쳐서 매칭되는 모든 수면(낮잠 포함)을
// 합산하도록 했고, 이 테스트가 그 수정을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_history.dart';
import 'package:shiftbell/services/condition/today_forecast_engine.dart';

const _kDay = '주간';
const _kNight = '야간';
const _kOff = '휴무';
const List<String> _pattern8Day = [_kDay, _kDay, _kOff, _kOff, _kNight, _kNight, _kOff, _kOff];
final _shiftTimes = <String, ShiftTimeRange>{
  _kDay: const ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60),
  _kNight: const ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60),
};

ShiftPatternAnalyzer _analyzerFor(DateTime today, {required int todayIndex}) {
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: _pattern8Day,
    todayIndex: todayIndex,
    startDate: today,
    shiftTypes: const [_kDay, _kNight, _kOff],
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _shiftTimes);
}

SleepRecord _record(DateTime start, int minutes) => SleepRecord(
      start: start,
      end: start.add(Duration(minutes: minutes)),
      source: SleepSource.manual,
      status: SleepStatus.confirmed,
    );

void main() {
  final today = DateTime(2026, 9, 6);

  test('1. 메인 수면 1건만 - 기존과 동일하게 그 길이 그대로', () {
    // todayIndex=4(오늘=첫 야간) -> 어제(offset -1, index3)=휴무, 그제(offset
    // -2)=휴무, offset-3(index1)=주간 - 가장 최근 근무일은 offset-3(주간).
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final workDay = today.subtract(const Duration(days: 3));
    final shiftEnd = analyzer.instanceForDate(workDay).end!;
    final records = [_record(shiftEnd.add(const Duration(minutes: 30)), 7 * 60)];
    final nights = collectRecentWorkNights(analyzer: analyzer, records: records, referenceDate: today);
    final night = nights.firstWhere((n) => n.date == DateTime(workDay.year, workDay.month, workDay.day));
    expect(night.sleepMinutes, 7 * 60);
    expect(night.hasSleepData, true);
  });

  test('2. 짧은 낮잠(30분) 먼저 + 몇 시간 뒤 메인 수면(6.5시간) - 합쳐서 7시간이어야 함(버그 수정 검증)', () {
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final workDay = today.subtract(const Duration(days: 3));
    final shiftEnd = analyzer.instanceForDate(workDay).end!;
    final records = [
      _record(shiftEnd.add(const Duration(minutes: 30)), 30), // 낮잠 30분(근무 직후)
      _record(shiftEnd.add(const Duration(hours: 4)), 6 * 60 + 30), // 4시간 뒤 메인 수면 6.5시간
    ];
    final nights = collectRecentWorkNights(analyzer: analyzer, records: records, referenceDate: today);
    final night = nights.firstWhere((n) => n.date == DateTime(workDay.year, workDay.month, workDay.day));
    // ⭐ 수정 전이었다면 "가장 이른" 낮잠(30분)만 잡혀서 sleepMinutes==30이었을 것.
    expect(night.sleepMinutes, 30 + 6 * 60 + 30, reason: '낮잠+메인수면 합계가 총 수면시간이어야 함');
    expect(night.sleep!.durationMinutes, 30, reason: '취침 시각 기준(가장 이른 수면)은 여전히 낮잠');
    expect(night.latestSleep!.durationMinutes, 6 * 60 + 30, reason: '기상 시각 기준(가장 늦게 끝난 수면)은 메인 수면');
  });

  test('3. 낮잠 2번 + 메인 수면 1번 - 전부 합산되는지', () {
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final workDay = today.subtract(const Duration(days: 3));
    final shiftEnd = analyzer.instanceForDate(workDay).end!;
    final records = [
      _record(shiftEnd.add(const Duration(minutes: 30)), 20), // 낮잠1: 20분
      _record(shiftEnd.add(const Duration(hours: 2)), 25), // 낮잠2: 25분
      _record(shiftEnd.add(const Duration(hours: 5)), 6 * 60), // 메인수면: 6시간
    ];
    final nights = collectRecentWorkNights(analyzer: analyzer, records: records, referenceDate: today);
    final night = nights.firstWhere((n) => n.date == DateTime(workDay.year, workDay.month, workDay.day));
    expect(night.sleepMinutes, 20 + 25 + 6 * 60);
  });

  test('4. 낮잠만 있고 메인 수면이 진짜로 없는 경우 - 여전히 부족으로 잡혀야 함(과보정 방지 확인)', () {
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final workDay = today.subtract(const Duration(days: 3));
    final shiftEnd = analyzer.instanceForDate(workDay).end!;
    final records = [_record(shiftEnd.add(const Duration(minutes: 30)), 40)]; // 40분짜리 낮잠 하나뿐
    final nights = collectRecentWorkNights(analyzer: analyzer, records: records, referenceDate: today);
    final night = nights.firstWhere((n) => n.date == DateTime(workDay.year, workDay.month, workDay.day));
    expect(night.sleepMinutes, 40, reason: '진짜로 40분만 잔 경우는 40분 그대로 나와야 함(과도한 보정 방지)');
  });

  test('5. 통합 검증 - 낮잠+메인수면 합계로 축4/급성이벤트가 "짧은 수면"으로 오판하지 않는지', () {
    final yesterday = today.subtract(const Duration(days: 1)); // offset-1(index3)=휴무 - 실제 어제 근무 아님
    // 급성 이벤트는 "어제" 근무를 기준으로 찾으므로, 시나리오를 바꿔 오늘이
    // 아니라 어제가 근무일이 되도록 todayIndex를 조정한다.
    final analyzer2 = _analyzerFor(today, todayIndex: 5); // 오늘=index5(야간 2일차) -> 어제(index4)=야간
    final shiftEndYesterday = analyzer2.instanceForDate(yesterday).end!;
    final records = [
      _record(shiftEndYesterday.add(const Duration(minutes: 30)), 40), // 낮잠 40분
      _record(shiftEndYesterday.add(const Duration(hours: 5)), 6 * 60 + 30), // 메인수면 6.5시간
    ];
    final nights = collectRecentWorkNights(analyzer: analyzer2, records: records, referenceDate: today);
    final patterns = buildPersonalSleepPatterns(nights);
    final baseResult = ConditionRuleEngine(analyzer2).evaluate(today);
    final forecast = buildTodayForecast(
      baseResult: baseResult,
      analyzer: analyzer2,
      nights: nights,
      personalPatterns: patterns,
      otMinutesByDate: const {},
      today: today,
    );
    // ignore: avoid_print
    print('통합검증 메시지: ${forecast.message}');
    // 어제 실제 총 수면은 40+390=430분(7시간10분)으로 충분 - "짧았어요" 급성
    // 문구가 뜨면 안 됨(수정 전에는 40분만 잡혀서 반드시 떴을 상황).
    expect(forecast.message.contains('짧았어요'), false, reason: '낮잠+메인수면 합계가 충분하면 급성 짧은수면 신호가 뜨면 안 됨');
  });

  // ⭐ 2026-09-01 후속16 - "근무 중 수면(위젯에서 근무시간에 '수면' 버튼을
  // 눌러 6시간 자고 '기상'을 누른 경우 등)도 피로도 계산에 반영하되, 주
  // 수면 시각 패턴에는 안 섞이게" 요청 검증.
  test('6. 근무 중 수면(6시간) - 총 수면엔 가산되지만 취침/기상 패턴엔 안 들어가야 함', () {
    final analyzer = _analyzerFor(today, todayIndex: 4); // 오늘=첫 야간
    final workDay = today.subtract(const Duration(days: 3)); // 주간(offset-3, index1)
    final inst = analyzer.instanceForDate(workDay);
    // 근무 시작 1시간 뒤부터 6시간 - 근무시간(12시간) 안에 완전히 들어가는 근무 중 수면.
    final records = [_record(inst.start!.add(const Duration(hours: 1)), 6 * 60)];
    final nights = collectRecentWorkNights(analyzer: analyzer, records: records, referenceDate: today);
    final night = nights.firstWhere((n) => n.date == DateTime(workDay.year, workDay.month, workDay.day));
    expect(night.sleepMinutes, 6 * 60, reason: '근무 중 수면도 그 근무일의 총 수면에 가산돼야 함');
    expect(night.hasSleepData, true);
    expect(night.sleep, null, reason: '취침 시각 패턴용 sleep 필드는 근무 중 수면을 대표하면 안 됨(퇴근 후 수면 전용)');
    expect(night.latestSleep, null);

    // buildPersonalSleepPatterns가 sleep==null인 밤을 스킵하고도 안 죽는지(크래시 방지) 확인.
    final patterns = buildPersonalSleepPatterns(nights, minSamples: 1);
    expect(patterns.containsKey(inst.shiftName), false, reason: '근무 중 수면만 있는 밤은 취침/기상 패턴 평균에서 제외돼야 함');
  });

  test('7. 근무 중 수면(4시간) + 퇴근 후 진짜 주 수면(7시간) - 둘 다 합산되고 패턴은 퇴근 후 수면 기준', () {
    final analyzer = _analyzerFor(today, todayIndex: 4);
    final workDay = today.subtract(const Duration(days: 3));
    final inst = analyzer.instanceForDate(workDay);
    final records = [
      _record(inst.start!.add(const Duration(hours: 1)), 4 * 60), // 근무 중 수면 4시간
      _record(inst.end!.add(const Duration(minutes: 30)), 7 * 60), // 퇴근 후 주 수면 7시간
    ];
    final nights = collectRecentWorkNights(analyzer: analyzer, records: records, referenceDate: today);
    final night = nights.firstWhere((n) => n.date == DateTime(workDay.year, workDay.month, workDay.day));
    expect(night.sleepMinutes, 4 * 60 + 7 * 60, reason: '근무 중 수면 + 퇴근 후 주 수면 합계');
    expect(night.sleep, isNotNull);
    expect(night.sleep!.start, inst.end!.add(const Duration(minutes: 30)), reason: '취침 패턴은 퇴근 후 수면 기준이어야 함(근무 중 수면 제외)');
  });

  // ⭐ 2026-09-01 후속19(사용자 시나리오 그대로, 제가 처음엔 "빈틈"이라고만
  // 보고했다가 사용자 재질문으로 실제로 고침) - "어제 휴무, 오늘 야간"일 때
  // 오늘 출근 전 낮잠이 그날 총 수면에 반영되는지 검증.
  test('8. 어제=휴무(밤잠 8h) / 오늘=야간, 출근 전 낮잠(2h) - 오늘 총 수면에 가산돼야 함', () {
    final analyzer = _analyzerFor(today, todayIndex: 4); // 오늘=첫 야간, 어제(index3)=휴무
    final inst = analyzer.instanceForDate(today); // 오늘 19시 출근
    final yesterday = today.subtract(const Duration(days: 1));

    final lastNightSleep = _record(DateTime(yesterday.year, yesterday.month, yesterday.day, 23), 8 * 60); // 어제 23시~오늘 07시
    final preShiftNap = _record(DateTime(today.year, today.month, today.day, 16), 2 * 60); // 오늘 16~18시(19시 출근 전)

    final nights = collectRecentWorkNights(
      analyzer: analyzer,
      records: [lastNightSleep, preShiftNap],
      referenceDate: today,
    );
    final yesterdayNight = nights.firstWhere((n) => n.date == DateTime(yesterday.year, yesterday.month, yesterday.day));
    final todayNight = nights.firstWhere((n) => n.date == DateTime(today.year, today.month, today.day));

    expect(yesterdayNight.sleepMinutes, 8 * 60, reason: '어제(휴무) 밤잠은 어제 몫으로 정상 반영');
    expect(todayNight.sleepMinutes, 2 * 60, reason: '오늘 출근 전 낮잠이 오늘 몫 총 수면에 가산돼야 함(예전엔 어느 날에도 안 잡히던 빈틈)');
    expect(todayNight.sleep, null, reason: '단, 취침/기상 패턴용 sleep 필드는 여전히 안 채움(이건 근무 중 가산과 같은 취급 - 진짜 주 수면 패턴 대표 아님)');
    expect(inst.start!.hour, 19, reason: '전제 확인: 오늘 출근이 19시');
  });
}
