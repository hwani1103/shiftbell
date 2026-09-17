// test/recovery_briefing_overlap_scenarios_test.dart
//
// ⭐ 2026-09-18 - "오늘의 컨디션" 겹침 시나리오 회귀 테스트. 개별 신호 하나하나가
// 맞는지는 recovery_briefing_engine_test.dart/condition_rule_engine_v2_test.dart가
// 이미 본다 - 여기는 **여러 신호가 같은 날 동시에 뜰 때** 실제로 사람이 읽는
// 문장이 자연스러운지(중복 반복 없음, 안전 상한 숫자가 그대로 새지 않음)를
// 기계적으로 검증한다. 실사용 시나리오를 손으로 돌려보고 문장을 눈으로 읽어본
// 결과 발견한 문제 2가지(180일 캡 노출, RULE_EXTENDED_STREAK_SHORT_BREAK와
// RULE_CONSECUTIVE_WORKDAYS의 동어반복)의 회귀 테스트가 핵심.
//
// 패턴 인덱스 계산 실수를 피하기 위해 항상 `startDate == 오늘(now의 날짜)`로
// 맞춰서 daysDiff=0이 되게 한다 - 그러면 todayIndex가 곧 "오늘의 패턴 위치"라
// 다른 날짜는 상대 오프셋(±1, ±2...)으로만 계산하면 돼서 julianDayNumber를
// 손으로 계산할 필요가 없다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/recovery_briefing_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';

const _kDay4h = '단시간주간'; // 07~11 (4시간) - streakBucketFor가 다루지 않는 길이(8시간 미만)
const _kDay8h = '주간'; // 07~15 (8시간)
const _kNight = '야간'; // 19~07(+1) (12시간)
const _kOff = '휴무';

const _times = {
  _kDay4h: ShiftTimeRange(shiftName: _kDay4h, startMinutes: 7 * 60, endMinutes: 11 * 60),
  _kDay8h: ShiftTimeRange(shiftName: _kDay8h, startMinutes: 7 * 60, endMinutes: 15 * 60),
  _kNight: ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60),
};

/// [today]는 "오늘"의 날짜(자정 0시) - startDate를 여기 맞춰서 daysDiff(오늘)=0이
/// 되게 한다. 즉 `pattern[todayIndex]`가 곧 오늘 배정된 근무.
ShiftPatternAnalyzer analyzerFor(List<String> pattern, DateTime today, int todayIndex) {
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: pattern,
    todayIndex: todayIndex,
    startDate: today,
    shiftTypes: pattern.toSet().toList(),
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: _times);
}

RecoveryBriefing briefingFor(ShiftPatternAnalyzer a, DateTime now, {Map<String, int> ot = const {}}) {
  return buildRecoveryBriefing(
    analyzer: a,
    base: ConditionRuleEngine(a).evaluate(DateTime(now.year, now.month, now.day), otMinutesByDate: ot),
    records: const [],
    now: now,
    otMinutesByDate: ot,
  );
}

/// 같은 topic(단 [BriefingTopic.other] 제외)이 두 번 이상 등장하지 않는지 확인.
void expectNoTopicDuplicates(RecoveryBriefing b) {
  final factTopics = b.facts.map((f) => f.topic).where((t) => t != BriefingTopic.other).toList();
  expect(factTopics.toSet().length, factTopics.length, reason: 'facts에 같은 topic 중복: $factTopics\n실제 문장: ${b.facts.map((f) => f.text).toList()}');
  final actionTopics = b.actions.map((a) => a.topic).where((t) => t != BriefingTopic.other).toList();
  expect(actionTopics.toSet().length, actionTopics.length, reason: 'actions에 같은 topic 중복: $actionTopics\n실제 문장: ${b.actions.map((a) => a.text).toList()}');
}

/// 안전 상한(shift_pattern_analyzer.dart maxLookbackDays=180)이 리터럴 숫자로
/// 새지 않는지 확인 - "180"이 시각(예: 18:00)의 일부로 우연히 등장하는 걸
/// 피하려고 "180일"까지 붙여서 검사한다.
void expectNoCapLeak(RecoveryBriefing b) {
  for (final f in b.facts) {
    expect(f.text.contains('180일'), isFalse, reason: '캡 숫자가 그대로 노출됨: ${f.text}');
  }
  for (final a in b.actions) {
    expect(a.text.contains('180일'), isFalse, reason: '캡 숫자가 그대로 노출됨: ${a.text}');
  }
}

void main() {
  group('겹침 시나리오 - 문구 중복/캡 노출 회귀', () {
    test('야간 연속 + 근무중(퇴근임박) + 주간총량과다 - longWorkStreak가 하나로 합쳐진다', () {
      // 8일 주기: 야간×5, 휴무×3. now=06:45는 아직 "어제 날짜에 배정된" 야간 인스턴스
      // (전날 19시~오늘 07시) 진행 중이라, ctx.date는 어제가 된다 - 그 시점까지의
      // 연속 야간은 4일째. 12시간 버킷(임계 3일)과 근무시간무관 연속근무(임계 7일 -
      // 여긴 4일이라 아직 미달) 둘 다 같은 사실을 가리키지만 여기선 버킷만 fire.
      final pattern = [_kNight, _kNight, _kNight, _kNight, _kNight, _kOff, _kOff, _kOff];
      final today = DateTime(2026, 9, 10);
      final a = analyzerFor(pattern, today, 4);
      final b = briefingFor(a, DateTime(2026, 9, 10, 6, 45)); // 퇴근(07:00) 45분 전

      expect(b.level, ConditionLevel.highLoad);
      expectNoTopicDuplicates(b);
      expectNoCapLeak(b);
      final longStreakFacts = b.facts.where((f) => f.topic == BriefingTopic.longWorkStreak).toList();
      expect(longStreakFacts.length, 1);
      expect(longStreakFacts.single.text, contains('12시간 이상 근무 4일 연속'));
      expect(longStreakFacts.single.text.contains('전체 연속근무'), isFalse);
      expect(b.facts.any((f) => f.topic == BriefingTopic.nightStreak), isTrue);
      expect(b.facts.any((f) => f.topic == BriefingTopic.weeklyLoad), isTrue);
    });

    test('8시간대 근무 5일 연속 뒤 짧은 근무를 섞어 총 8일 연속 - 버킷값과 전체값이 달라 괄호로 합쳐진다', () {
      // 9일 주기: 4시간×3(연속근무엔 포함되지만 8시간 버킷 대상 아님), 8시간×5, 휴무.
      // 오늘 = 5번째(마지막) 8시간 근무. 8시간 버킷(임계 5일)은 8시간 근무만 세어 5일,
      // 근무시간 무관 연속근무는 4시간짜리 3일까지 합쳐 8일 - 총합이 더 크므로 괄호 표기.
      final pattern = [
        _kDay4h, _kDay4h, _kDay4h, // 0~2
        _kDay8h, _kDay8h, _kDay8h, _kDay8h, _kDay8h, // 3~7
        _kOff, // 8
      ];
      final today = DateTime(2026, 9, 10);
      final a = analyzerFor(pattern, today, 7); // 오늘 = 8시간 근무 5번째(index 7)
      final b = briefingFor(a, DateTime(2026, 9, 10, 14, 30)); // 퇴근(15:00) 30분 전

      expectNoTopicDuplicates(b);
      expectNoCapLeak(b);
      final longStreakFacts = b.facts.where((f) => f.topic == BriefingTopic.longWorkStreak).toList();
      expect(longStreakFacts.length, 1);
      expect(longStreakFacts.single.text, contains('8시간 이상 근무 5일 연속'));
      expect(longStreakFacts.single.text, contains('전체 연속근무는 8일째'));
    });

    test('휴무 첫날 - 어제까지 4시간 근무 10일 연속(근거 버킷 대상 아님)을 마친 직후에도 사실이 뜬다', () {
      // 12일 주기: 4시간 근무×10(8시간 미만이라 evidence 버킷 없음) + 휴무×2.
      // RULE_EXTENDED_STREAK_SHORT_BREAK는 절대 안 뜨고, 근무시간 무관 연속근무일수만
      // 뜬다 - ctx가 null인 offDay에서도 last로 폴백해 반영되는지가 핵심(재검토 발견 버그).
      final pattern = [...List.generate(10, (_) => _kDay4h), _kOff, _kOff];
      final today = DateTime(2026, 9, 12); // 첫 휴무일(index 10)
      final a = analyzerFor(pattern, today, 10);
      final b = briefingFor(a, DateTime(2026, 9, 12, 10, 0));

      expect(b.phase, BriefingPhase.offDay);
      expectNoTopicDuplicates(b);
      expectNoCapLeak(b);
      final longStreakFacts = b.facts.where((f) => f.topic == BriefingTopic.longWorkStreak).toList();
      expect(longStreakFacts.length, 1, reason: '휴무 첫날에도 직전 연속근무 정보가 떠야 함(ctx==null 폴백 확인)');
      expect(longStreakFacts.single.text, contains('10일째 연속 근무'));
      expect(b.actions.any((act) => act.id == 'consecutive_workdays_rest'), isTrue);
    });

    test('쉬는 날이 없는(patternHasNoRestDay) 패턴 - 안전 상한 문구로 대체되고 180이 새지 않는다', () {
      final pattern = [_kNight]; // 매일 야간만 반복 - 쉬는 날이 아예 없음
      final today = DateTime(2026, 9, 10);
      final a = analyzerFor(pattern, today, 0);
      expect(a.patternHasNoRestDay, isTrue);
      final b = briefingFor(a, DateTime(2026, 9, 10, 6, 30)); // 퇴근 30분 전

      expect(b.level, ConditionLevel.highLoad);
      expectNoTopicDuplicates(b);
      expectNoCapLeak(b);
      final nightFact = b.facts.singleWhere((f) => f.topic == BriefingTopic.nightStreak);
      expect(nightFact.text, contains('매우 오래'));
      final longStreakFact = b.facts.singleWhere((f) => f.topic == BriefingTopic.longWorkStreak);
      expect(longStreakFact.text, contains('매우 오래'));
    });

    test('퇴근 직후(recovering) + 야간연속 + 연속근무일수과다 + 수면기록없음 - 여러 topic이 겹쳐도 중복 없이 뜬다', () {
      // 9일 주기: 4시간 근무 3일(연속근무엔 포함되지만 버킷 대상 아님) + 야간 5일(버킷 대상)
      // + 휴무. 오늘은 방금 마지막 야간에서 퇴근한 직후(recovering) - 야간연속(5일,
      // nightStreak) + 12시간버킷(5일, longWorkStreak - 총 연속근무 8일이라 괄호 병기)
      // + 수면기록 없음(sleepAmount 미기록 안내)이 동시에 뜬다.
      final pattern = [
        _kDay4h, _kDay4h, _kDay4h, // 0~2
        _kNight, _kNight, _kNight, _kNight, _kNight, // 3~7
        _kOff, // 8
      ];
      final today = DateTime(2026, 9, 10);
      final a = analyzerFor(pattern, today, 7); // 오늘 = 마지막 야간(index 7)
      final b = briefingFor(a, DateTime(2026, 9, 11, 9, 0)); // 07:00 퇴근 후 2시간

      expect(b.phase, BriefingPhase.recovering);
      expectNoTopicDuplicates(b);
      expectNoCapLeak(b);
      expect(b.facts.any((f) => f.topic == BriefingTopic.nightStreak), isTrue);
      final longStreakFacts = b.facts.where((f) => f.topic == BriefingTopic.longWorkStreak).toList();
      expect(longStreakFacts.length, 1);
      expect(longStreakFacts.single.text, contains('전체 연속근무는 8일째'));
      // 수면 기록이 아예 없는 사용자에겐 "기록이 없다"고 나무라지 않고 판단 범위로
      // 안내한다(설계 원칙 - 기록 없음과 컨디션 나쁨을 안 섞는다).
      expect(b.limitations.any((l) => l.contains('수면 기록이 없어')), isTrue);
    });

    test('표준 12시간 패턴의 평범한 하루 - 과부하 신호가 안 뜨는 정상 케이스(회귀 방지)', () {
      final pattern = [_kNight, _kNight, _kOff, _kOff, _kOff, _kOff, _kOff, _kOff];
      final today = DateTime(2026, 9, 10);
      final a = analyzerFor(pattern, today, 0); // 오늘 = 1번째 야간
      final b = briefingFor(a, DateTime(2026, 9, 10, 20, 0)); // 근무 중(초반)

      expect(b.level, ConditionLevel.normal);
      expect(b.facts.any((f) => f.tone == BriefingTone.caution), isFalse);
      expectNoTopicDuplicates(b);
    });

    test('근무시간대가 달라도 총량이 비슷하면 브리핑 레벨도 비슷하다(12시간×3일/7 vs 8시간×5일/7)', () {
      final today = DateTime(2026, 9, 10);
      final p12 = [_kNight, _kNight, _kNight, _kOff, _kOff, _kOff, _kOff]; // 주 36시간
      final p8 = [_kDay8h, _kDay8h, _kDay8h, _kDay8h, _kDay8h, _kOff, _kOff]; // 주 40시간
      final b12 = briefingFor(analyzerFor(p12, today, 0), DateTime(2026, 9, 10, 20, 0));
      final b8 = briefingFor(analyzerFor(p8, today, 0), DateTime(2026, 9, 10, 8, 0));

      expect(b12.level, ConditionLevel.normal);
      expect(b8.level, ConditionLevel.normal);
      expect(b12.facts.any((f) => f.topic == BriefingTopic.weeklyLoad), isFalse);
      expect(b8.facts.any((f) => f.topic == BriefingTopic.weeklyLoad), isFalse);
    });

    test('역방향 교대 전환 + 짧은 회복시간 겹침 - 두 topic이 각자 하나씩만 뜬다', () {
      // 야간→오후 전환은 역방향. 오후 근무(15~23) 뒤 다음날 주간(07시) 출근이면
      // 회복시간이 8시간(<11시간)으로 짧아 RULE_SHORT_RECOVERY도 같이 겹친다.
      const kEvening = '오후';
      final times = {
        ..._times,
        kEvening: const ShiftTimeRange(shiftName: kEvening, startMinutes: 15 * 60, endMinutes: 23 * 60),
      };
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: [_kNight, kEvening, _kDay8h, _kOff],
        todayIndex: 1, // 오늘 = 오후(야간 다음날 - 역방향 전환)
        startDate: DateTime(2026, 9, 10),
        shiftTypes: [_kNight, kEvening, _kDay8h, _kOff],
      );
      final a = ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
      final b = briefingFor(a, DateTime(2026, 9, 10, 22, 30)); // 오후 근무 중, 퇴근 30분 전

      expectNoTopicDuplicates(b);
      expectNoCapLeak(b);
      expect(b.facts.any((f) => f.topic == BriefingTopic.direction), isTrue);
      expect(b.facts.where((f) => f.topic == BriefingTopic.direction).length, 1);
    });
  });
}
