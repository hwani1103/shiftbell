// test/recovery_briefing_engine_test.dart
//
// ⭐ 2026-09-15 - "오늘의 컨디션"(recovery_briefing_engine.dart) 회귀 테스트.
// 컨디션 점수·날짜 시드 문구를 대체한 엔진이 교대근무자의 실제 흐름(근무 중·퇴근 후·출근 전·휴무)에서
// 확인된 사실 / 시각이 박힌 추천 행동 / 판단 범위를 기대대로 나누는지, 그리고 근거 규칙을 지키는지 본다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/evidence_database.dart';
import 'package:shiftbell/services/condition/recovery_briefing_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/database_service.dart';

const _kDay = '주간';
const _kEvening = '오후';
const _kNight = '야간';
const _kOff = '휴무';

/// 주주휴휴야야휴휴 8일 순환(주간 07~19, 야간 19~07)
const List<String> _pattern8 = [_kDay, _kDay, _kOff, _kOff, _kNight, _kNight, _kOff, _kOff];
const _dayRange = ShiftTimeRange(shiftName: _kDay, startMinutes: 7 * 60, endMinutes: 19 * 60);
const _nightRange = ShiftTimeRange(shiftName: _kNight, startMinutes: 19 * 60, endMinutes: 7 * 60);

final _today = DateTime(2026, 9, 6);
final _all = <RecoveryBriefing>[];

ShiftPatternAnalyzer _analyzer(List<String> pattern, int todayIndex, Map<String, ShiftTimeRange> times) {
  final schedule = ShiftSchedule(
    isRegular: true,
    pattern: pattern,
    todayIndex: todayIndex,
    startDate: _today,
    shiftTypes: pattern.toSet().toList(),
  );
  return ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
}

SleepRecord _sleep(DateTime start, int minutes) => SleepRecord(
      start: start,
      end: start.add(Duration(minutes: minutes)),
      source: SleepSource.manual,
      status: SleepStatus.confirmed,
    );

RecoveryBriefing _brief(
  ShiftPatternAnalyzer analyzer,
  DateTime now,
  List<SleepRecord> records, {
  Map<String, int> ot = const {},
  int pending = 0,
}) {
  final b = buildRecoveryBriefing(
    analyzer: analyzer,
    base: ConditionRuleEngine(analyzer).evaluate(DateTime(now.year, now.month, now.day), otMinutesByDate: ot),
    records: records,
    now: now,
    otMinutesByDate: ot,
    pendingCount: pending,
  );
  _all.add(b);
  return b;
}

List<String> _ids(RecoveryBriefing b) => b.actions.map((a) => a.id).toList();

void main() {
  final times = {_kDay: _dayRange, _kNight: _nightRange};

  test('야간 뒤 회복 중 · 수면이 아직 부족 - 늦어도 몇 시에 잠들지와 카페인 시각을 준다', () {
    final a = _analyzer(_pattern8, 5, times); // 9/6 야간(2일차), 9/5 야간
    final b = _brief(a, DateTime(2026, 9, 6, 10), [_sleep(DateTime(2026, 9, 6, 7, 30), 150)]);

    expect(b.phase, BriefingPhase.recovering);
    expect(b.situation, contains('야간 근무 마친 지 3시간'));
    expect(b.facts.map((f) => f.text), contains(startsWith('퇴근(오늘 07:00) 후 수면 2시간 30분')));
    expect(b.facts.map((f) => f.text), contains(startsWith('근무 사이 회복시간 12시간')));
    expect(_ids(b).first, 'sleep_plan');
    expect(b.actions.first.text, contains('4시간 30분 더 자려면'));
    expect(b.actions.first.text, contains('오늘 13:30'), reason: '다음 출근 19:00 - 준비 1시간 - 남은 4.5시간');
    expect(b.actions.first.evidenceIds, containsAll(['EVIDENCE-006', 'EVIDENCE-011']));
    expect(_ids(b), contains('caffeine'));
    // 기록한 날이 1일(야간 퇴근 뒤 수면은 야간 근무일로 집계)뿐이라 평균만 판단 범위로 빠진다 - 상태는 깎지 않음
    expect(b.limitations, ['최근 7일 중 기록이 1일뿐이라 평균 수면은 계산하지 않았어요.']);
  });

  test('야간 근무 중 퇴근 1시간 반 전 - 퇴근길 안전이 첫 행동, 행동은 최대 3개', () {
    final a = _analyzer(_pattern8, 4, times); // 9/6 야간 1일차
    final b = _brief(a, DateTime(2026, 9, 7, 5, 30), const []);

    expect(b.phase, BriefingPhase.onShift);
    expect(b.situation, contains('퇴근'));
    expect(_ids(b), ['commute', 'sleep_after_shift', 'caffeine']);
    expect(b.actions.first.evidenceIds, ['EVIDENCE-009']);
    expect(b.limitations.join(), contains('수면 기록이 없어'), reason: '기록이 없으면 상태를 깎지 않고 판단 범위로만 알린다');
  });

  test('오후 23시 퇴근 → 다음날 주간 07시: 회복 8시간을 경고하고 "지금 바로 자도 최대"를 안내', () {
    final a = _analyzer(const [_kEvening, _kDay, _kOff], 0, {
      _kEvening: const ShiftTimeRange(shiftName: _kEvening, startMinutes: 15 * 60, endMinutes: 23 * 60),
      _kDay: _dayRange,
    });
    final b = _brief(a, DateTime(2026, 9, 6, 23, 30), [_sleep(DateTime(2026, 9, 4, 23), 420)]);

    expect(b.phase, BriefingPhase.recovering);
    final gap = b.facts.firstWhere((f) => f.text.startsWith('근무 사이 회복시간'));
    expect(gap.text, contains('8시간'));
    expect(gap.tone, BriefingTone.caution);
    expect(gap.evidenceIds, containsAll(['EVIDENCE-002', 'EVIDENCE-003']));
    expect(_ids(b).first, 'sleep_now');
    expect(b.actions.first.text, contains('최대 6시간 30분'));
  });

  test('출퇴근 시각이 없는 근무가 끼면 다음 근무·회복시간을 단정하지 않고 판단 범위에 적는다', () {
    final a = _analyzer(const [_kDay, _kEvening, _kOff], 0, {_kDay: _dayRange}); // 오후 시각 미입력
    final b = _brief(a, DateTime(2026, 9, 6, 20), const []);

    expect(b.situation, contains('오후(시각 미입력)'));
    expect(b.facts.where((f) => f.text.contains('회복시간')), isEmpty);
    expect(b.limitations.join(), contains("'오후'"));
  });

  test('야간 뒤 휴무 밤 - 수면 회복 우선 행동, 야간 퇴근 뒤 수면은 야간 근무일(어제)로 집계', () {
    final a = _analyzer(_pattern8, 6, times); // 9/6 휴무, 9/5·9/4 야간
    final b = _brief(a, DateTime(2026, 9, 6, 23, 30), [_sleep(DateTime(2026, 9, 6, 8), 420)]);

    expect(b.phase, BriefingPhase.offDay);
    expect(_ids(b), contains('off_after_night'));
    expect(b.facts.map((f) => f.text), contains(startsWith('어제(9/5) 수면 7시간')));
    expect(b.facts.map((f) => f.text), contains('어제까지 야간 2일 연속 근무'));
  });

  test('퇴근 후 이미 7시간 이상 잤으면 수면 행동은 빼고, 야간 출근 전 짧은 낮잠만 권한다', () {
    final a = _analyzer(_pattern8, 5, times);
    final b = _brief(a, DateTime(2026, 9, 6, 15, 30), [_sleep(DateTime(2026, 9, 6, 7, 30), 450)]);

    expect(b.phase, BriefingPhase.recovering);
    expect(b.facts.first.tone, BriefingTone.good);
    expect(_ids(b), isNot(contains('sleep_plan')));
    expect(_ids(b), isNot(contains('sleep_now')));
    expect(_ids(b), contains('nap_before_night'));
  });

  test('확인 전 자동 기록은 반영하지 않았다고 판단 범위에 적는다', () {
    final a = _analyzer(_pattern8, 5, times);
    final b = _brief(a, DateTime(2026, 9, 6, 10), [_sleep(DateTime(2026, 9, 6, 7, 30), 150)], pending: 2);
    expect(b.limitations.join(), contains('자동 수면 기록 2건'));
  });

  test('최근 7일 평균 수면은 기록한 날이 3일 이상일 때만 보여준다', () {
    final a = _analyzer(_pattern8, 6, times);
    final threeDays = [
      _sleep(DateTime(2026, 9, 1, 23), 360),
      _sleep(DateTime(2026, 9, 2, 23), 360),
      _sleep(DateTime(2026, 9, 3, 23), 360),
    ];
    final withAvg = _brief(a, DateTime(2026, 9, 6, 23, 30), threeDays);
    expect(withAvg.facts.map((f) => f.text), contains(startsWith('최근 7일 평균 수면 6시간 (기록한 3일 기준)')));
    expect(_ids(withAvg), contains('catch_up'));

    final twoDays = _brief(a, DateTime(2026, 9, 6, 23, 30), threeDays.take(2).toList());
    expect(twoDays.facts.where((f) => f.text.startsWith('최근 7일 평균')), isEmpty);
    expect(twoDays.limitations.join(), contains('2일뿐'));
  });

  test('최근 7일 실근무시간이 평소보다 많이 늘면 사실과 행동에 근거를 단다(2026-09-18 개인기준선 재설계)', () {
    // ⭐ 2026-09-17 재설계 - "초과근무만"에서 "기본근무+초과근무 합계"로 확장.
    // _pattern8(주간·야간 12시간씩, 8일 주기)에서 이 시점 기준 최근 7일 기본근무만
    // 이미 48시간(12시간×4일: 야간2일+주간2일)이라 초과근무 9시간(5+4)을 더하면 총 57시간.
    // ⭐ 2026-09-18 재설계 - 이 패턴의 개인 기준선은 12시간×4일/8일*7 = 42시간. 57시간은
    // 기준선보다 15시간 많아 심각 임계값(기준선의 25%=10.5시간, 최소 12시간 중 큰 쪽인
    // 12시간)도 넘어 EVIDENCE-014까지 함께 인용됨(예전 절대 60시간 기준으로는 57시간이
    // "심각"에 못 미쳤지만, 이제는 기준선 대비 증가폭만 본다).
    final a = _analyzer(_pattern8, 5, times);
    final b = _brief(a, DateTime(2026, 9, 6, 10), [_sleep(DateTime(2026, 9, 6, 7, 30), 150)], ot: const {'2026-09-05': 300, '2026-09-03': 240});
    expect(
      b.facts.where((f) => f.text.startsWith('최근 7일 실근무시간 57시간')).single.evidenceIds,
      ['EVIDENCE-012', 'EVIDENCE-014'],
    );
  });

  test('근거 규칙 - 모든 근거 ID는 실제 근거 DB에 있고, 기록 안내를 뺀 모든 행동은 근거를 가진다', () {
    final known = kEvidenceDatabase.map((e) => e.id).toSet();
    expect(_all, isNotEmpty);
    for (final b in _all) {
      for (final id in b.evidenceIds) {
        expect(known, contains(id));
      }
      for (final action in b.actions) {
        if (action.id == 'record_sleep') continue;
        expect(action.evidenceIds, isNotEmpty, reason: '행동 ${action.id}에 근거가 없음');
      }
      expect(b.actions.length, lessThanOrEqualTo(kBriefingMaxActions));
    }
  });

  test('Q-07 - 수면 기록 한 행의 날짜가 깨져도 나머지 기록은 그대로 읽는다', () {
    final rows = <Map<String, Object?>>[
      {'id': 1, 'start_time': '2026-09-06T01:00:00', 'end_time': '2026-09-06T07:00:00', 'source': 'MANUAL', 'status': 'CONFIRMED', 'confidence': null},
      {'id': 2, 'start_time': 'broken', 'end_time': null, 'source': 'MANUAL', 'status': 'CONFIRMED', 'confidence': null},
    ];
    final records = decodeSleepRecordRows(rows);
    expect(records.map((r) => r.id), [1]);
  });
}
