// lib/services/condition/recovery_briefing_engine.dart
//
// ⭐ 2026-09-15 - "오늘의 컨디션" 카드 엔진. today_forecast_engine.dart(날짜 시드 문구 조합)와
// condition_score.dart(0~100 점수)를 대체한다(출시 적합성 재검토 후속, 사용자 결정):
//  - 점수는 근거보다 임의 가중치 영향이 컸고, 수면 기록이 없다는 이유로 감점해서 "상태가 나쁨"과 "데이터 없음"이 섞였음
//  - 문구는 풍부했지만 사용자가 실제로 무엇을 몇 시에 하면 되는지로 이어지지 않는 경우가 많았음
// 그래서 "지금 이 시각" 기준으로 세 가지를 분리해서 만든다.
//  1. 확인된 사실 - 근무표·실제 수면 기록에서 계산되는 것만(퇴근 후 수면, 근무 사이 회복시간, 연속 야간 등)
//  2. 추천 행동 - 시각이 박힌 구체 행동 최대 3개(몇 시까지 잠자리에 들기, 카페인 끊을 시각, 퇴근길 빛·운전 등)
//  3. 판단 범위 - 수면 기록 없음·출퇴근 시각 미입력·확인 전 자동 기록처럼 판단을 제한한 이유(상태를 나쁘게 보지 않음)
//
// 원칙(CLAUDE.md 설계 기록 › 컨디션 매니저 유지):
//  - 건강 관련 기준·조언에는 evidence_database.dart 근거 ID를 단다. 근거 없는 판정·진단·점수·%·질병 위험 금지.
//    순수 사실(연속 근무일수 등)과 기록 안내(record_sleep)만 근거 없이 쓴다.
//  - 3단계 판정(ConditionLevel)은 ConditionRuleEngine 결과 그대로 쓰고, 수면 기록은 판정에 섞지 않는다.
//  - 기준값(7시간·11시간·12시간·카페인 6시간·초과근무 8시간)은 ConditionRuleEngine 상수를 그대로 쓴다.
//  - 순수 함수 - [now]를 주입받는다(테스트: test/recovery_briefing_engine_test.dart).
//  - 60분 "출근 준비·귀가 여유"와 3시간·16시간 같은 구간 경계는 연구값이 아니라 화면 구성용 관례값이다.

import 'dart:math' as math;

import '../../models/sleep_record.dart';
import '../../utils/sleep_format_util.dart' show kWeekdayLabelsKo;
import 'condition_rule_engine.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';
import 'sleep_by_category_stats.dart';
import 'sleep_day_slots.dart';
import 'sleep_opportunity.dart' show graceAdjustedShiftEnd;
import 'sleep_overlap.dart';

enum BriefingTone { neutral, good, caution }

/// ⭐ 2026-09-18 - 여러 신호가 결국 "같은 근본 사실"을 가리킬 때(예: 근무시간대별
/// 연속근무 버킷과 근무시간 무관 연속근무일수가 둘 다 "쉬지 않고 일했다"는 같은
/// 얘기를 각자 다른 말로 반복하던 문제) 렌더링 직전에 중복을 걸러내기 위한 태그.
/// [other]는 애초에 한 브리핑에 하나만 나오도록 코드가 이미 보장하는 사실(수면
/// 기록 안내 등)이라 dedup 대상에서 제외한다.
enum BriefingTopic {
  sleepAmount,
  sleepAverage,
  personalSleepBaseline,
  recoveryGap,
  nightStreak,
  longWorkStreak,
  weeklyLoad,
  direction,
  other,
}

class BriefingFact {
  final String text;
  final BriefingTone tone;
  final List<String> evidenceIds;
  final BriefingTopic topic;
  const BriefingFact(this.text,
      {this.tone = BriefingTone.neutral,
      this.evidenceIds = const [],
      this.topic = BriefingTopic.other});
}

class BriefingAction {
  /// 중복 제거·테스트용 식별자(화면에는 안 보임)
  final String id;
  final String text;
  final List<String> evidenceIds;
  final BriefingTopic topic;
  const BriefingAction(this.id, this.text,
      {this.evidenceIds = const [], this.topic = BriefingTopic.other});
}

/// ⭐ 2026-09-18 - 같은 topic(단 [BriefingTopic.other] 제외)이 여러 개면 먼저 생성된
/// 것 하나만 남긴다. 항목 생성 순서 자체가 "더 구체적이고 근거가 강한 신호를 먼저
/// 만든다"는 규칙을 따르므로(예: longWorkStreak는 근무시간대별 버킷 결과를 먼저
/// 넣음) first-wins로 충분하다 - 지금 당장 실제로 겹치는 topic이 없더라도, 새 신호를
/// 추가할 때 같은 topic을 잘못 두 번 만드는 실수를 렌더링 단계에서 한 번 더 막아준다.
List<T> _dedupByTopic<T>(List<T> items, BriefingTopic Function(T) topicOf) {
  final seen = <BriefingTopic>{};
  final result = <T>[];
  for (final item in items) {
    final t = topicOf(item);
    if (t != BriefingTopic.other && !seen.add(t)) continue;
    result.add(item);
  }
  return result;
}

/// 지금 이 시각이 근무 흐름에서 어디쯤인지.
enum BriefingPhase {
  onShift, // 근무 중
  beforeShift, // 출근 3시간 이내
  recovering, // 퇴근 후 16시간 이내
  laterToday, // 오늘 근무가 3시간 넘게 남음
  offDay, // 오늘 휴무(퇴근 직후 회복 구간이 아님)
  unknown, // 근무 일정 없음·오늘 근무 시각 미입력
}

class RecoveryBriefing {
  final ConditionLevel level;
  final BriefingPhase phase;
  final String situation;
  final List<BriefingFact> facts;
  final List<BriefingAction> actions;
  final List<String> limitations;

  const RecoveryBriefing({
    required this.level,
    required this.phase,
    required this.situation,
    required this.facts,
    required this.actions,
    required this.limitations,
  });

  /// 화면 "근거 보기"에 쓸 근거 ID(중복 제거·정렬).
  List<String> get evidenceIds {
    final ids = <String>{
      for (final f in facts) ...f.evidenceIds,
      for (final a in actions) ...a.evidenceIds,
    };
    return ids.toList()..sort();
  }
}

const int kBriefingMaxActions = 3;
const int kBriefingMaxFacts = 6;

const Duration _kPrepBuffer =
    Duration(minutes: ConditionRuleEngine.sleepBufferMinutes);
const Duration _kBeforeShiftWindow = Duration(hours: 3);
const Duration _kRecoveringWindow = Duration(hours: 16);
const Duration _kCommuteWindow = Duration(hours: 3);
const Duration _kNoSleepNudgeAfter = Duration(hours: 4);

/// ⭐ 2026-09-21 - "지난 24시간 총 수면"의 창. EVIDENCE-011(성인 7~9시간)은 원래
/// 24시간당 기준이라, 수면량 비교는 항상 이 창으로 한다(아래 3-1 참고).
const Duration _kSleepDayWindow = Duration(hours: 24);
const Duration _kNapMinLead = Duration(hours: 1);
const Duration _kNapMaxLead = Duration(hours: 6);
const Duration _kCaffeineCutoff =
    Duration(hours: ConditionRuleEngine.caffeineCutoffHoursBeforeSleep);
const int _kSearchDays = 14;
const int _kLongWorkStreakDays = 5;
const int _kMinRecordedDaysForAverage = 3;
// 개인 평균과 1시간 미만 차이는 기록 오차·일상 변동일 수 있어 경고하지 않는다.
const int _kMeaningfulPersonalSleepDeficitMinutes = 60;

const List<String> _eDirection = ['EVIDENCE-001'];
const List<String> _eRecovery = ['EVIDENCE-002', 'EVIDENCE-003'];
const String _eAfterNight = 'EVIDENCE-006';
const List<String> _eNap = ['EVIDENCE-007'];
const List<String> _eCaffeine = ['EVIDENCE-008'];
const List<String> _eCommute = ['EVIDENCE-009'];
const List<String> _eMeal = ['EVIDENCE-010'];
const String _eSleepAmount = 'EVIDENCE-011';
const List<String> _eOvertime = ['EVIDENCE-012'];
const List<String> _eOvertimeSevere = ['EVIDENCE-012', 'EVIDENCE-014'];
const List<String> _eNightStreak = ['EVIDENCE-013'];
const List<String> _eConsecutiveWorkdays = ['EVIDENCE-005'];

const BriefingAction _commuteAction = BriefingAction(
  'commute',
  '퇴근길엔 선글라스 등으로 강한 햇빛을 줄이면 이후 잠들기 쉬워요. 많이 졸리면 운전하지 말고 대중교통이나 동승을 이용하세요.',
  evidenceIds: _eCommute,
);
const BriefingAction _napAction = BriefingAction(
  'nap_before_night',
  '출근 전에 짧게 눈을 붙이면 야간 졸림을 줄이는 데 도움이 될 수 있어요. 깬 직후엔 잠깐 멍할 수 있으니 바로 운전하지는 마세요.',
  evidenceIds: _eNap,
);
const BriefingAction _mealAction = BriefingAction(
  'night_meal',
  '자정~06시에는 식사량을 줄이고 가벼운 음식 위주로 드세요.',
  evidenceIds: _eMeal,
);
const BriefingAction _recordSleepAction = BriefingAction(
  'record_sleep',
  '아래 "최근 수면 기록"에 수면 시간을 남겨주세요. 기록이 쌓이면 실제로 잔 시간을 바탕으로 더 정확하게 알려드릴게요.',
);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "7시간 20분" / "7시간" / "40분" (음수는 0분)
String fmtBriefingDuration(int minutes) {
  final m = math.max(0, minutes);
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '$r분';
  if (r == 0) return '$h시간';
  return '$h시간 $r분';
}

/// "오늘 07:00" / "내일 19:00" / "어제 23:00" / "모레 07:00" / "9/20(일) 07:00"
String briefingWhenLabel(DateTime t, DateTime now) {
  final diff = (_day(t).difference(_day(now)).inHours / 24).round();
  final hm = _hm(t);
  switch (diff) {
    case 0:
      return '오늘 $hm';
    case 1:
      return '내일 $hm';
    case -1:
      return '어제 $hm';
    case 2:
      return '모레 $hm';
  }
  return '${t.month}/${t.day}(${kWeekdayLabelsKo[t.weekday - 1]}) $hm';
}

/// 출퇴근 시각을 아는 근무일의 인스턴스만(휴무·미설정·시각 미입력은 null).
ShiftInstance? _timed(ShiftPatternAnalyzer analyzer, DateTime day) {
  final inst = analyzer.instanceForDate(day);
  return (inst.isWorkDay && inst.start != null && inst.end != null)
      ? inst
      : null;
}

bool _isRotating(ShiftTimeCategory c) =>
    c == ShiftTimeCategory.day ||
    c == ShiftTimeCategory.evening ||
    c == ShiftTimeCategory.night;

/// 주간→야간·오후→주간·야간→오후 = 역방향(ShiftPatternAnalyzer.analyzeDirection과 같은 순서 정의)
bool _isBackwardStep(ShiftTimeCategory from, ShiftTimeCategory to) {
  const order = [
    ShiftTimeCategory.day,
    ShiftTimeCategory.evening,
    ShiftTimeCategory.night
  ];
  return (order.indexOf(to) - order.indexOf(from)) % 3 == 2;
}

// ⭐ 2026-09-22 - 낮잠은 화면 칸(2개)이 아니라 그날 귀속된 전부를 센다(위젯·자동 감지로 3개 이상일 수 있음)
int _slotTotal(SleepDaySlots s) =>
    (s.mainSleep?.durationMinutes ?? 0) + s.napMinutes;

class _RankedAction {
  final int rank;
  final int order;
  final BriefingAction action;
  const _RankedAction(this.rank, this.order, this.action);
}

RecoveryBriefing buildRecoveryBriefing({
  required ShiftPatternAnalyzer analyzer,
  required ConditionResult base,
  required List<SleepRecord> records,
  required DateTime now,
  Map<String, int> otMinutesByDate = const {},
  int pendingCount = 0,
}) {
  final today = _day(now);
  const target =
      ConditionRuleEngine.recommendedSleepMinMinutes; // 7시간 - EVIDENCE-011
  String when(DateTime t) => briefingWhenLabel(t, now);
  String dur(int minutes) => fmtBriefingDuration(minutes);

  // ── 1. 지금 근무 흐름에서의 위치 ─────────────────────────────────────
  ShiftInstance? current;
  for (final offset in const [0, -1]) {
    final inst = _timed(analyzer, today.add(Duration(days: offset)));
    if (inst != null && !now.isBefore(inst.start!) && now.isBefore(inst.end!)) {
      current = inst;
      break;
    }
  }

  ShiftInstance? last;
  for (var i = 0; i <= _kSearchDays; i++) {
    final inst = _timed(analyzer, today.subtract(Duration(days: i)));
    if (inst == null || inst.end!.isAfter(now)) continue;
    if (last == null || inst.end!.isAfter(last.end!)) last = inst;
    if (i >= 1) break;
  }

  ShiftInstance? next;
  for (var i = 0; i <= _kSearchDays; i++) {
    final inst = _timed(analyzer, today.add(Duration(days: i)));
    if (inst != null && inst.start!.isAfter(now)) {
      next = inst;
      break;
    }
  }

  // 출퇴근 시각이 없는 근무가 끼어 있으면 "직전/다음 근무"를 단정하지 않는다(설정 의존성 - 재검토 #4)
  final untimedNames = <String>[];
  for (var i = -7; i <= 7; i++) {
    final inst = analyzer.instanceForDate(today.add(Duration(days: i)));
    if (inst.isWorkDay &&
        inst.start == null &&
        !untimedNames.contains(inst.shiftName)) {
      untimedNames.add(inst.shiftName);
    }
  }
  String? untimedNextName;
  if (next != null) {
    for (var d = today;
        d.isBefore(next.date);
        d = d.add(const Duration(days: 1))) {
      final inst = analyzer.instanceForDate(d);
      if (inst.isWorkDay && inst.start == null) {
        untimedNextName = inst.shiftName;
        break;
      }
    }
    if (untimedNextName != null) next = null;
  }
  if (last != null) {
    for (var d = last.date.add(const Duration(days: 1));
        !d.isAfter(today);
        d = d.add(const Duration(days: 1))) {
      final inst = analyzer.instanceForDate(d);
      if (inst.isWorkDay && inst.start == null) {
        last = null;
        break;
      }
    }
  }

  final todayInst = analyzer.instanceForDate(today);
  final BriefingPhase phase;
  if (current != null) {
    phase = BriefingPhase.onShift;
  } else if (next != null &&
      next.start!.difference(now) <= _kBeforeShiftWindow) {
    phase = BriefingPhase.beforeShift;
  } else if (last != null && now.difference(last.end!) <= _kRecoveringWindow) {
    phase = BriefingPhase.recovering;
  } else if (todayInst.isOff) {
    phase = BriefingPhase.offDay;
  } else if (next != null && _day(next.start!) == today) {
    phase = BriefingPhase.laterToday;
  } else {
    phase = BriefingPhase.unknown;
  }

  final nextText = next != null
      ? '다음 근무 ${next.shiftName} ${when(next.start!)}'
      : (untimedNextName != null ? '다음 근무 $untimedNextName(시각 미입력)' : null);
  final String situation = switch (phase) {
    BriefingPhase.onShift =>
      '지금 ${current!.shiftName} 근무 중 · ${when(current.end!)} 퇴근 '
          '(${dur(current.end!.difference(now).inMinutes)} 남음)',
    BriefingPhase.beforeShift =>
      '곧 ${next!.shiftName} 출근 · ${when(next.start!)} (${dur(next.start!.difference(now).inMinutes)} 뒤)',
    BriefingPhase.recovering =>
      '${last!.shiftName} 근무 마친 지 ${dur(now.difference(last.end!).inMinutes)}'
          '${nextText != null ? ' · $nextText' : ''}',
    BriefingPhase.offDay => '오늘은 휴무${nextText != null ? ' · $nextText' : ''}',
    BriefingPhase.laterToday =>
      '오늘 ${next!.shiftName} 근무 · ${when(next.start!)} 출근 (${dur(next.start!.difference(now).inMinutes)} 뒤)',
    BriefingPhase.unknown => todayInst.isUnset
        ? '오늘은 근무 일정이 없는 날이에요'
        : '오늘 ${todayInst.shiftName} 근무 (출퇴근 시각 미입력)',
  };

  // ── 2. 수면 기록 ────────────────────────────────────────────────────
  final confirmed = records
      .where((r) =>
          r.status == SleepStatus.confirmed &&
          r.end != null &&
          r.end!.isAfter(r.start))
      .toList();
  // ⭐ 2026-09-22 - 겹친 기록의 겹친 시간을 두 번 세지 않도록 합집합으로 계산(sleep_overlap.dart 참고)
  int sleptBetween(DateTime from, DateTime until) =>
      mergedSleepMinutesBetween(confirmed, from, until);

  final hasRecentRecords = confirmed
      .any((r) => r.end!.isAfter(now.subtract(const Duration(days: 14))));
  final sleepingNow =
      records.any((r) => r.end == null && !r.start.isAfter(now));

  // ⭐ 2026-09-21 - 오늘 칸까지 같이 만든다. 아래 3-1의 "출근 전 수면"이 미니 달력과
  // 정확히 같은 귀속 규칙을 쓰게 하기 위함(귀속 규칙은 sleep_day_slots.dart의
  // _attributedDay 하나만 신뢰 - 여기서 다시 구현하지 않는다). 평균·어제 수면은
  // 여전히 "이미 끝난 날"만 쓰므로 오늘 칸은 빼고 계산한다.
  final slotsIncludingToday = buildSleepDaySlots(
    records: records,
    from: today.subtract(const Duration(days: 7)),
    to: today,
    analyzer: analyzer,
  );
  final slots =
      slotsIncludingToday.where((s) => s.date.isBefore(today)).toList();
  final dayTotals = [for (final s in slots) _slotTotal(s)];

  // [inst] 근무일 칸에 귀속된 수면 중 출근 시각 전에 끝난 것의 합 = "출근 전 수면".
  // (야간 첫날의 전날 밤잠은 전날 칸에, 연속 야간의 아침 회복수면은 어제 칸에
  // 귀속되므로 여기 섞이지 않는다 - 순수하게 "그 근무를 위해 미리 잔 잠"만 남는다.)
  int preShiftSleepFor(ShiftInstance inst) {
    var total = 0;
    for (final slot in slotsIncludingToday) {
      if (slot.date != inst.date) continue;
      for (final r in [slot.mainSleep, ...slot.allNaps]) {
        if (r?.end == null || r!.end!.isAfter(inst.start!)) continue;
        total += r.durationMinutes ?? 0;
      }
    }
    return total;
  }

  final recordedDays = dayTotals.where((m) => m > 0).toList();
  final yesterdayTotal = dayTotals.isEmpty ? 0 : dayTotals.last;
  final int? avgRecent = recordedDays.length >= _kMinRecordedDaysForAverage
      ? (recordedDays.reduce((a, b) => a + b) / recordedDays.length).round()
      : null;

  // 가장 최근에 끝난 수면일을 같은 근무 유형의 과거 30일 평균과 비교한다.
  // 비교 대상 날짜 자체는 평균에서 제외해, 짧았던 오늘 기록이 기준선을 끌어내리지
  // 않게 한다. 최근 이틀보다 오래된 결과는 오늘 카드에 다시 꺼내지 않는다.
  ({
    SleepDaySlots slot,
    SleepCategoryAverage average,
    int actual,
    int deficit
  })? personalSleepDeficit;
  for (final slot in slots.reversed) {
    final age = today.difference(slot.date).inDays;
    if (age > 2) break;
    final actual = _slotTotal(slot);
    if (actual <= 0) continue;
    final category = analyzer.instanceForDate(slot.date).category;
    if (category == ShiftTimeCategory.unspecified) continue;
    final historic = buildSleepCategoryAverages(
      records: records,
      analyzer: analyzer,
      now: slot.date,
    );
    SleepCategoryAverage? comparable;
    for (final average in historic) {
      if (average.category == category) {
        comparable = average;
        break;
      }
    }
    if (comparable == null) continue;
    final deficit = comparable.averageMinutes - actual;
    if (deficit >= _kMeaningfulPersonalSleepDeficitMinutes) {
      personalSleepDeficit =
          (slot: slot, average: comparable, actual: actual, deficit: deficit);
    }
    break;
  }

  final facts = <BriefingFact>[];
  final ranked = <_RankedAction>[];
  void act(int rank, BriefingAction action) =>
      ranked.add(_RankedAction(rank, ranked.length, action));

  // ── 3. 확인된 사실 ───────────────────────────────────────────────────
  // ⭐ 2026-09-21 - 수면 기록이 비어 있는 구간이면 "그래서 뭘 하면 되는지"를 항상
  // 같이 준다(예전엔 "출근 전 수면 기록이 없어요"에서 문장이 끊겼음 - 사용자 지적).
  var sleepDataMissing = false;

  // 3-1. 지난 24시간 수면(근무 중 / 출근 전 / 오늘 근무 대기)
  // ⭐ 2026-09-21 재설계(사용자 지적) - 예전엔 "직전 퇴근 이후 ~ 출근까지"만 세어
  //   "출근 전 수면 2시간 — 권장 7시간보다 짧아요"라고 말했다. 야간 근무에서는 출근
  //   전에 7시간을 채우는 게 애초에 불가능하거나(어제 주간 → 오늘 야간) 그 7시간이
  //   "출근 전 낮잠 + 퇴근 후 회복수면"으로 쪼개지는 게 정상이라, 출근 전 수면만
  //   떼어 7시간과 비교하는 건 실행 불가능한 요구가 된다. 권장 7~9시간(EVIDENCE-011)은
  //   원래 **24시간당** 기준이므로 비교 대상도 지난 24시간 총 수면으로 바꾼다 -
  //   야간 첫날(전날 밤잠 + 출근 전 낮잠)이든 연속 야간 둘째 날(아침 회복수면 +
  //   출근 전 낮잠)이든, 경우를 나눠 세지 않아도 그 사람이 실제로 확보한 수면이
  //   그대로 잡힌다. 출근 전에 따로 눈을 붙인 게 있으면 그 값만 괄호로 덧붙인다.
  var last24hSleep = 0;
  final beforeOrOnShift = phase == BriefingPhase.onShift ||
      phase == BriefingPhase.beforeShift ||
      phase == BriefingPhase.laterToday;
  if (beforeOrOnShift) {
    final shiftInst = (current ?? next)!;
    last24hSleep = sleptBetween(now.subtract(_kSleepDayWindow), now);
    final preShiftSleep = preShiftSleepFor(shiftInst);
    if (last24hSleep > 0) {
      final enough = last24hSleep >= target;
      // 괄호는 "24시간 총량과 다른 값일 때"만 - 같으면 같은 말을 두 번 하는 셈이라 뺀다.
      final preNote = (preShiftSleep > 0 && preShiftSleep < last24hSleep)
          ? ' (출근 전 ${dur(preShiftSleep)} 포함)'
          : '';
      facts.add(BriefingFact(
        '지난 24시간 수면 ${dur(last24hSleep)}$preNote${enough ? '' : ', 권장 7시간보다 적어요'}',
        tone: enough ? BriefingTone.good : BriefingTone.caution,
        evidenceIds: const [_eSleepAmount],
        topic: BriefingTopic.sleepAmount,
      ));
    } else if (!sleepingNow) {
      sleepDataMissing = true;
      if (hasRecentRecords) {
        facts.add(const BriefingFact('지난 24시간 수면 기록이 없어요',
            topic: BriefingTopic.sleepAmount));
      }
    }
  }

  // 3-2. 퇴근 후 수면
  var sleepSinceLast = 0;
  if (phase == BriefingPhase.recovering) {
    final l = last!;
    sleepSinceLast = sleptBetween(graceAdjustedShiftEnd(l), now);
    if (sleepSinceLast > 0) {
      final canStillSleep = next == null
          ? target
          : math.max(
              0, next.start!.subtract(_kPrepBuffer).difference(now).inMinutes);
      final enough = sleepSinceLast >= target;
      final cannotReach = !enough && sleepSinceLast + canStillSleep < target;
      facts.add(BriefingFact(
        '퇴근(${when(l.end!)}) 후 수면 ${dur(sleepSinceLast)}${cannotReach ? ', 다음 출근 전까지 7시간을 채우긴 어려워요' : ''}',
        tone: enough
            ? BriefingTone.good
            : (cannotReach ? BriefingTone.caution : BriefingTone.neutral),
        evidenceIds: const [_eSleepAmount],
        topic: BriefingTopic.sleepAmount,
      ));
    } else if (sleepingNow) {
      facts.add(const BriefingFact('지금 수면 중으로 기록돼 있어요'));
    } else if (now.difference(l.end!) >= _kNoSleepNudgeAfter) {
      sleepDataMissing = true;
      if (hasRecentRecords)
        facts.add(BriefingFact('퇴근(${when(l.end!)}) 후 기록된 수면이 아직 없어요'));
    }
  }

  // 3-3. 어제 수면(휴무·일정 불명일)
  if (phase == BriefingPhase.offDay || phase == BriefingPhase.unknown) {
    final y = today.subtract(const Duration(days: 1));
    if (yesterdayTotal > 0) {
      final enough = yesterdayTotal >= target;
      facts.add(BriefingFact(
        '어제(${y.month}/${y.day}) 수면 ${dur(yesterdayTotal)}${enough ? '' : ', 권장 7시간보다 적어요'}',
        tone: enough ? BriefingTone.good : BriefingTone.caution,
        evidenceIds: const [_eSleepAmount],
        topic: BriefingTopic.sleepAmount,
      ));
    } else {
      sleepDataMissing = true;
      if (hasRecentRecords)
        facts.add(BriefingFact('어제(${y.month}/${y.day}) 수면 기록이 없어요'));
    }
  }

  // 3-4. 개인의 같은 근무 유형 평균과 비교. 이 값은 기록에서 확인되는 보조 사실과
  // 행동 제안에만 쓰고, 일정 기반 3단계 ConditionLevel을 임의로 올리지는 않는다.
  final comparison = personalSleepDeficit;
  if (comparison != null) {
    final category = comparison.average.category;
    final categoryLabel =
        category == ShiftTimeCategory.off ? '휴무일' : '${category.label} 근무일';
    final age = today.difference(comparison.slot.date).inDays;
    final dayLabel = age == 1 ? '어제' : '그제';
    facts.add(BriefingFact(
      '$dayLabel $categoryLabel 수면 ${dur(comparison.actual)}, 개인 평균 '
      '${dur(comparison.average.averageMinutes)}보다 ${dur(comparison.deficit)} 적어요 '
      '(최근 30일 ${comparison.average.sampleDays}일 기준)',
      tone: BriefingTone.caution,
      // ⭐ 2026-09-22 - 근거 ID를 달지 않는다. 이 사실은 "내 기록끼리의 비교"라 순수 사실에 속하고,
      // EVIDENCE-011(성인 7~9시간)은 절대 기준이라 이 비교의 근거가 아니다(달아 두면 "7시간 기준으로
      // 판정했다"는 뜻으로 읽힘). 1시간이라는 차이 기준은 이 앱의 판단이다(도움말 근거 목록 머리말에 명시).
      topic: BriefingTopic.personalSleepBaseline,
    ));
    act(
        32,
        BriefingAction(
          'personal_sleep_baseline',
          '최근 $categoryLabel 수면이 평소보다 적었어요. 다음 수면 기회에는 다른 일정보다 회복할 시간을 조금 더 넉넉히 잡아보세요.',
          // 조언(잠을 더 확보하기)은 성인 권장 수면 EVIDENCE-011이 뒷받침한다.
          evidenceIds: const [_eSleepAmount],
          topic: BriefingTopic.personalSleepBaseline,
        ));
  }

  // 3-5. 근무 사이 회복시간
  final ShiftInstance? gapFrom = phase == BriefingPhase.onShift
      ? current
      : (phase == BriefingPhase.beforeShift ||
              phase == BriefingPhase.recovering ||
              phase == BriefingPhase.laterToday)
          ? last
          : null;
  final ShiftInstance? gapTo =
      (phase == BriefingPhase.offDay || phase == BriefingPhase.unknown)
          ? null
          : next;
  if (gapFrom != null && gapTo != null) {
    final gap = gapTo.start!.difference(gapFrom.end!).inMinutes;
    if (gap > 0 && gap <= 48 * 60) {
      final short = gap < ConditionRuleEngine.minRecoveryMinutes;
      facts.add(BriefingFact(
        '근무 사이 회복시간 ${dur(gap)} (${when(gapFrom.end!)} 퇴근 → ${when(gapTo.start!)} 출근)'
        '${short ? ', 권장 최소 11시간보다 짧아요' : ''}',
        tone: short ? BriefingTone.caution : BriefingTone.neutral,
        evidenceIds: short ? _eRecovery : const [],
        topic: BriefingTopic.recoveryGap,
      ));
    }
  }

  // 3-5. 근무 부담(일정 기반 - ConditionRuleEngine과 같은 기준값)
  // ⭐ 2026-09-17 재설계 - "오늘 근무가 12시간이면 그 자체로 캐션"이라는 절대 임계값
  // 문구를 폐지함(사용자 지적: 12시간이 표준 근무인 사람에게 매번 뜨는 뻔한 경고였음).
  // 근무시간/근무명은 이미 위 situation 줄에서 중립적으로 보여주고, "정말 부담인지"는
  // 아래 RULE_EXTENDED_STREAK_SHORT_BREAK(연속 며칠째+짧은 회복)와 RULE_WEEKLY_TOTAL_LOAD
  // (최근 7일 총량)로만 판단한다.
  final ShiftInstance? ctx = switch (phase) {
    BriefingPhase.onShift => current,
    BriefingPhase.beforeShift || BriefingPhase.laterToday => next,
    BriefingPhase.recovering => last,
    _ => null,
  };

  var nightStreak = 0;
  var nightStreakCapped = false;
  if (ctx != null && ctx.category == ShiftTimeCategory.night) {
    final nightStreakResult = analyzer.consecutiveNightStreakEndingAt(ctx.date);
    nightStreak = nightStreakResult.days;
    nightStreakCapped = nightStreakResult.capped;
    if (nightStreak >= 2) {
      final severe = nightStreak >= 3;
      final text = ConditionRuleEngine.streakClause(
        nightStreakResult,
        normal: (days) => phase == BriefingPhase.recovering
            ? '야간 $days일 연속 근무 후'
            : '연속 야간 $days일째',
        capped: phase == BriefingPhase.recovering
            ? '야간 근무가 휴무 없이 매우 오래 이어진 후'
            : '연속 야간 근무가 휴무 없이 매우 오래 이어지고 있음',
      );
      facts.add(BriefingFact(
        severe ? '$text. 연속될수록 피로와 실수가 쌓이기 쉬워요' : text,
        tone: severe ? BriefingTone.caution : BriefingTone.neutral,
        evidenceIds: severe ? _eNightStreak : const [],
        topic: BriefingTopic.nightStreak,
      ));
    }
  }

  // ⭐ 2026-09-18 재설계 - RULE_EXTENDED_STREAK_SHORT_BREAK(근무시간대별 버킷)와
  // RULE_CONSECUTIVE_WORKDAYS(근무시간 무관 연속일수)는 같은 근본 사실("쉬지 않고
  // 이어지는 근무")을 가리켜서, 예전엔 각자 독립적으로 fact/action을 만들어 같은
  // 정보를 두 문장으로 반복했음(예: "12시간 이상 근무 5일 연속" + "5일째 연속
  // 근무"). 여기서 한 번에 계산해서 topic: longWorkStreak 하나만 만든다(대표
  // 시나리오 회귀는 test/recovery_briefing_overlap_scenarios_test.dart 참고).
  // ⭐ ctx가 null인 phase(휴무 첫날 등)에서도 "방금 힘들게 일했다"가 반영되도록
  // ctx ?? last로 폴백 - 예전엔 연속근무일수 쪽이 `if (ctx != null)`로 막혀 있어
  // 휴무 첫날에 직전 연속근무 정보가 통째로 안 뜨는 공백이 있었음(재검토로 발견).
  final streakInst = ctx ?? last;
  if (streakInst != null) {
    final bucket = streakInst.durationMinutes != null
        ? ConditionRuleEngine.streakBucketFor(streakInst.durationMinutes!)
        : null;
    ConsecutiveStreak? bucketStreak;
    if (bucket != null) {
      final s = analyzer.consecutiveLongShiftStreakEndingAt(streakInst.date,
          thresholdMinutes: bucket.floorMinutes);
      if (s.days >= bucket.thresholdDays) bucketStreak = s;
    }
    // ⭐ RULE_CONSECUTIVE_WORKDAYS는 base(오늘 날짜 기준)가 휴무일엔 늘 0으로
    // 리셋해서(engine 쪽 "오늘의 레벨"용 설계) base.levelFindings로 확인하면 이
    // ctx-null 폴백 케이스를 못 잡는다 - streakInst.date를 직접 다시 계산한다.
    final workStreak = analyzer.consecutiveWorkStreakEndingAt(streakInst.date);
    final workStreakFired = workStreak.days >=
        ConditionRuleEngine.consecutiveWorkdayAttentionThreshold;

    if (bucketStreak != null && bucket != null) {
      final floorHours = bucket.floorMinutes ~/ 60;
      final breakDays = (bucket.requiredBreakMinutes / (24 * 60)).ceil();
      // 하루 근무시간과 무관한 전체 연속근무일수가 버킷 연속일수보다 더 길면(짧은
      // 근무를 섞어가며 계속 일한 경우) 괄호로 덧붙여 정보 손실 없이 한 문장으로 합친다.
      final totalNote = (!workStreak.capped &&
              !bucketStreak.capped &&
              workStreak.days > bucketStreak.days)
          ? '(전체 연속근무는 ${workStreak.days}일째)'
          : '';
      facts.add(BriefingFact(
        ConditionRuleEngine.streakClause(
          bucketStreak,
          normal: (days) => '$floorHours시간 이상 근무 $days일 연속$totalNote',
          capped: '$floorHours시간 이상 근무가 휴무 없이 매우 오래 이어지고 있어요',
        ),
        tone: BriefingTone.caution,
        evidenceIds: bucket.evidenceIds,
        topic: BriefingTopic.longWorkStreak,
      ));
      act(
          60,
          BriefingAction(
            'extended_streak_rest',
            '$floorHours시간 근무가 '
                '${ConditionRuleEngine.streakClause(bucketStreak, normal: (days) => '$days일', capped: '휴무 없이 매우 오래')} '
                '이어졌어요. 근무 조정이 가능하다면 이어서 $breakDays일 정도는 쉬어보세요.',
            evidenceIds: bucket.evidenceIds,
            topic: BriefingTopic.longWorkStreak,
          ));
    } else if (workStreakFired) {
      final severe = workStreak.days >=
          ConditionRuleEngine.consecutiveWorkdaySevereThreshold;
      facts.add(BriefingFact(
        ConditionRuleEngine.streakClause(
          workStreak,
          normal: (days) => '$days일째 연속 근무 중이에요. 쉬는 날 없이 이어지면 피로가 쌓이기 쉬워요',
          capped: '휴무 없이 매우 오래 근무가 이어지고 있어요. 쉬는 날 없이 이어지면 피로가 쌓이기 쉬워요',
        ),
        tone: BriefingTone.caution,
        evidenceIds: _eConsecutiveWorkdays,
        topic: BriefingTopic.longWorkStreak,
      ));
      if (severe) {
        act(
            65,
            const BriefingAction(
              'consecutive_workdays_rest',
              '연속 근무가 길게 이어지고 있어요. 근무 조정이 가능하다면 하루라도 쉬는 날을 만들어보세요.',
              evidenceIds: _eConsecutiveWorkdays,
              topic: BriefingTopic.longWorkStreak,
            ));
      }
    } else if (workStreak.days >= _kLongWorkStreakDays) {
      facts.add(BriefingFact(
        ConditionRuleEngine.streakClause(workStreak,
            normal: (days) => '$days일째 연속 근무',
            capped: '휴무 없이 매우 오래 근무가 이어지고 있어요'),
        topic: BriefingTopic.longWorkStreak,
      ));
    }
  }

  // ⭐ 2026-09-17 재설계 - "최근 7일 초과근무"에서 "최근 7일 총 실근무시간"(기본근무+
  // 초과근무)으로 확장. 2026-09-18 재설계 - EU/IOM 절대값이 아니라 개인 기준선 대비
  // 증가 폭으로 판단(ConditionRuleEngine.weeklyLoadIncrease - evaluate()가 이미 계산한
  // base.weeklyBaselineMinutes를 그대로 재사용해서 여기서 다시 계산하지 않음. 원칙 4 -
  // 같은 주장에 다른 숫자를 쓰지 않는다).
  var weeklyBase = 0;
  for (var i = 0; i < ConditionRuleEngine.overtimeLookbackDays; i++) {
    final inst = analyzer.instanceForDate(today.subtract(Duration(days: i)));
    if (inst.isWorkDay) weeklyBase += inst.durationMinutes ?? 0;
  }
  var otTotal = 0;
  for (var i = 0; i < ConditionRuleEngine.overtimeLookbackDays; i++) {
    otTotal += otMinutesByDate[
            ConditionRuleEngine.dateKey(today.subtract(Duration(days: i)))] ??
        0;
  }
  final weeklyTotal = weeklyBase + otTotal;
  final loadIncrease = ConditionRuleEngine.weeklyLoadIncrease(
    actualWeeklyMinutes: weeklyTotal,
    baselineWeeklyMinutes: base.weeklyBaselineMinutes,
  );
  if (loadIncrease.heavy) {
    // heavy가 true면 weeklyLoadIncrease() 정의상 baseline/extraMinutes는 항상 non-null.
    final baseline = base.weeklyBaselineMinutes!;
    final extra = loadIncrease.extraMinutes!;
    facts.add(BriefingFact(
      '최근 7일 실근무시간 ${dur(weeklyTotal)}, 평소(주 ${dur(baseline)} 안팎)보다 ${dur(extra)} 많아요',
      tone: BriefingTone.caution,
      evidenceIds: loadIncrease.severe ? _eOvertimeSevere : _eOvertime,
      topic: BriefingTopic.weeklyLoad,
    ));
    act(
        70,
        BriefingAction(
          'overtime',
          loadIncrease.severe
              ? '최근 7일 근무시간이 평소보다 많이 쌓였어요. 가능하면 추가 근무를 줄이고 쉬는 시간부터 먼저 챙기세요.'
              : '이번 주는 평소보다 근무가 좀 더 많아요. 가능하면 추가 근무를 줄이고 휴식을 챙겨보세요.',
          evidenceIds: loadIncrease.severe ? _eOvertimeSevere : _eOvertime,
          topic: BriefingTopic.weeklyLoad,
        ));
  }

  if (ctx != null &&
      base.levelFindings.any((f) => f.ruleId == 'RULE_BACKWARD_DIRECTION')) {
    ShiftInstance? prev;
    for (var i = 1; i <= 7; i++) {
      final inst = _timed(analyzer, ctx.date.subtract(Duration(days: i)));
      if (inst != null) {
        prev = inst;
        break;
      }
    }
    if (prev != null &&
        _isRotating(prev.category) &&
        _isRotating(ctx.category) &&
        prev.category != ctx.category &&
        _isBackwardStep(prev.category, ctx.category)) {
      facts.add(BriefingFact(
        '역방향 교대 전환(${prev.category.label} → ${ctx.category.label}). 정방향보다 몸이 적응하기 어려운 편이에요',
        tone: BriefingTone.caution,
        evidenceIds: _eDirection,
        topic: BriefingTopic.direction,
      ));
    }
  }

  // ── 4. 추천 행동(우선순위: 안전 > 수면 > 낮잠 > 카페인 > 식사 > 누적 부담 > 기록) ─────────
  BriefingAction caffeineAction(DateTime bed) {
    final cutoff = bed.subtract(_kCaffeineCutoff);
    return cutoff.isAfter(now)
        ? BriefingAction(
            'caffeine',
            '${when(cutoff)} 이후엔 커피·에너지음료를 피하세요(잠드는 목표 ${when(bed)}).',
            evidenceIds: _eCaffeine,
          )
        : BriefingAction(
            'caffeine',
            '잠드는 목표(${when(bed)})까지 6시간이 안 남았어요. 지금부터는 커피·에너지음료를 피하세요.',
            evidenceIds: _eCaffeine,
          );
  }

  if (phase == BriefingPhase.onShift) {
    final c = current!;
    final isNight = c.category == ShiftTimeCategory.night;
    final bed = c.end!.add(_kPrepBuffer);
    if (isNight && c.end!.difference(now) <= _kCommuteWindow)
      act(0, _commuteAction);
    if (next != null) {
      final wakeBy = next.start!.subtract(_kPrepBuffer);
      final available = wakeBy.difference(bed).inMinutes;
      if (available < 60) {
        act(
            10,
            const BriefingAction(
              'sleep_after_shift',
              '퇴근 후 다음 출근까지 잘 수 있는 시간이 거의 없어요. 가능하다면 근무 조정을 요청하거나 근무 중에라도 잠깐 쉴 수 있는지 알아보세요.',
              evidenceIds: _eRecovery,
            ));
      } else if (available < target) {
        act(
            10,
            BriefingAction(
              'sleep_after_shift',
              '퇴근 후 잘 수 있는 시간은 ${when(bed)}~${when(wakeBy)}, 약 ${dur(available)}뿐이에요. 퇴근하면 다른 일정보다 수면을 먼저 챙기세요.',
              evidenceIds: [_eSleepAmount, if (isNight) _eAfterNight],
            ));
      } else if (isNight) {
        act(
            10,
            BriefingAction(
              'sleep_after_shift',
              '퇴근 후엔 수면을 먼저 챙기세요. ${when(bed)}쯤 잠들면 다음 출근 전까지 7시간 이상 잘 수 있어요.',
              evidenceIds: const [_eAfterNight, _eSleepAmount],
            ));
      }
    } else if (isNight) {
      act(
          10,
          const BriefingAction(
              'sleep_after_shift', '퇴근 후엔 다른 일정보다 수면을 먼저 챙기세요.',
              evidenceIds: [_eAfterNight]));
    }
    act(30, caffeineAction(bed));
    if (isNight && (now.hour >= 22 || now.hour < 6)) act(40, _mealAction);
  }

  if (phase == BriefingPhase.beforeShift || phase == BriefingPhase.laterToday) {
    final n = next!;
    final isNight = n.category == ShiftTimeCategory.night;
    final lead = n.start!.difference(now);
    if (isNight &&
        lead >= _kNapMinLead &&
        lead <= _kNapMaxLead &&
        last24hSleep < target) act(20, _napAction);
    final bedAfter = n.end!.add(_kPrepBuffer);
    if (last24hSleep > 0 && last24hSleep < target) {
      act(
          15,
          BriefingAction(
            'sleep_after_next',
            '지난 24시간 수면이 권장량보다 적어요. 이번 근무를 마치면(${when(bedAfter)}쯤) 다른 일정보다 수면을 먼저 챙기세요.',
            evidenceIds: const [_eSleepAmount],
          ));
    }
    if (bedAfter.subtract(_kCaffeineCutoff).isAfter(now))
      act(30, caffeineAction(bedAfter));
    if (isNight) act(40, _mealAction);
  }

  if (phase == BriefingPhase.recovering) {
    final l = last!;
    final afterNight = l.category == ShiftTimeCategory.night;
    final need = math.max(0, target - sleepSinceLast);
    if (afterNight &&
        sleepSinceLast == 0 &&
        !sleepingNow &&
        now.difference(l.end!) <= _kCommuteWindow) {
      act(0, _commuteAction);
    }
    if (need > 0 && !sleepingNow) {
      final prefix = afterNight ? '야간 근무 뒤에는 수면이 우선이에요. ' : '';
      final ids = [if (afterNight) _eAfterNight, _eSleepAmount];
      if (next != null) {
        final wakeBy = next.start!.subtract(_kPrepBuffer);
        final latestBed = wakeBy.subtract(Duration(minutes: need));
        if (latestBed.isAfter(now.add(const Duration(minutes: 30)))) {
          final goal = sleepSinceLast > 0 ? '${dur(need)} 더 자려면' : '7시간을 자려면';
          act(
              10,
              BriefingAction(
                'sleep_plan',
                '$prefix다음 출근(${when(next.start!)}) 전에 $goal 늦어도 ${when(latestBed)}에는 잠자리에 드세요.',
                evidenceIds: ids,
              ));
          act(30, caffeineAction(latestBed));
        } else {
          final available = wakeBy.difference(now).inMinutes;
          if (available >= 30) {
            act(
                10,
                BriefingAction(
                  'sleep_now',
                  '$prefix지금 바로 자도 출근 준비 전까지 최대 ${dur(available)}이에요. 다른 일정은 미루고 수면부터 챙기세요.',
                  evidenceIds: ids,
                ));
            act(
                30,
                const BriefingAction(
                    'caffeine', '곧 잠들어야 해요. 지금부터는 커피·에너지음료를 피하세요.',
                    evidenceIds: _eCaffeine));
          }
        }
      } else {
        act(
            10,
            BriefingAction(
              'sleep_plan',
              afterNight
                  ? '야간 근무 뒤에는 다른 일정보다 수면을 먼저 챙기세요.'
                  : '오늘은 7시간 이상 자는 걸 목표로 하세요.',
              evidenceIds: ids,
            ));
      }
    }
    if (next != null && next.category == ShiftTimeCategory.night) {
      final lead = next.start!.difference(now);
      if (lead >= _kNapMinLead && lead <= _kNapMaxLead && sleepSinceLast > 0)
        act(20, _napAction);
    }
  }

  if (phase == BriefingPhase.offDay) {
    final yInst =
        analyzer.instanceForDate(today.subtract(const Duration(days: 1)));
    if (yInst.isWorkDay && yInst.category == ShiftTimeCategory.night) {
      final streak = analyzer.consecutiveNightStreakEndingAt(yInst.date);
      facts.add(BriefingFact(
        ConditionRuleEngine.streakClause(
          streak,
          normal: (days) => '어제까지 야간 $days일 연속 근무',
          capped: '어제까지 야간 근무가 휴무 없이 매우 오래 이어짐',
        ),
        topic: BriefingTopic.nightStreak,
      ));
      act(
          10,
          const BriefingAction(
            'off_after_night',
            '야간 근무 뒤 휴무예요. 약속이나 집안일보다 수면 회복을 먼저 챙기세요.',
            evidenceIds: [_eAfterNight],
          ));
    }
    if (next != null &&
        next.start!.difference(now) <= const Duration(hours: 24)) {
      final latestBed = next.start!
          .subtract(_kPrepBuffer)
          .subtract(const Duration(minutes: target));
      if (latestBed.isAfter(now)) {
        act(
            12,
            BriefingAction(
              'sleep_plan',
              '다음 근무(${next.shiftName}, ${when(next.start!)})에 맞춰 7시간을 자려면 늦어도 ${when(latestBed)}에는 잠자리에 드세요.',
              evidenceIds: const [_eSleepAmount],
            ));
        act(30, caffeineAction(latestBed));
      }
    }
    if (avgRecent != null &&
        avgRecent < target &&
        personalSleepDeficit == null) {
      act(
          14,
          const BriefingAction(
            'catch_up',
            '최근 수면이 권장량(7시간)보다 적었어요. 쉬는 날엔 수면 시간을 넉넉히 잡아보세요.',
            evidenceIds: [_eSleepAmount],
          ));
    }
  }

  // ⭐ 2026-09-21 - 수면 기록이 비어 있으면 어느 phase든 "기록하면 반영된다"는 다음
  // 단계를 준다(예전엔 퇴근 후 구간에서만 안내해서, 출근 전·휴무엔 "기록이 없어요"로
  // 문장이 끊겼음 - 사용자 지적). 수면을 하나도 모르는 상태에서는 일반적인 야간 식사
  // 팁(rank 40)보다 이쪽이 먼저 나와야 해서 카페인(30)과 식사(40) 사이에 둔다.
  if (sleepDataMissing && !sleepingNow) act(35, _recordSleepAction);

  // 평균 수면은 사실 목록 맨 끝(오늘 판단의 보조 정보)
  if (avgRecent != null) {
    final low = avgRecent < target;
    facts.add(BriefingFact(
      '최근 7일 평균 수면 ${dur(avgRecent)} (기록한 ${recordedDays.length}일 기준)${low ? ', 권장 7시간보다 적어요' : ''}',
      tone: low ? BriefingTone.caution : BriefingTone.neutral,
      evidenceIds: const [_eSleepAmount],
      topic: BriefingTopic.sleepAverage,
    ));
  }

  if (nightStreak >= 4 &&
      (phase == BriefingPhase.onShift ||
          phase == BriefingPhase.beforeShift ||
          phase == BriefingPhase.laterToday)) {
    final nightStreakLabel = nightStreakCapped
        ? '연속 야간 근무가 휴무 없이 매우 오래 이어지고 있어요'
        : '연속 야간 $nightStreak일째예요';
    act(
        50,
        BriefingAction(
          'night_streak',
          '$nightStreakLabel. 운전이나 위험한 작업은 특히 조심하세요.',
          evidenceIds: _eNightStreak,
          topic: BriefingTopic.nightStreak,
        ));
  }

  // ── 5. 판단 범위 ────────────────────────────────────────────────────
  final limitations = <String>[];
  if (!hasRecentRecords) {
    limitations.add('최근 2주 수면 기록이 없어 근무 일정만 보고 안내했어요.');
  } else if (recordedDays.isNotEmpty && avgRecent == null) {
    limitations.add('최근 7일 중 기록이 ${recordedDays.length}일뿐이라 평균 수면은 계산하지 않았어요.');
  }
  if (untimedNames.isNotEmpty) {
    final names = untimedNames.map((n) => "'$n'").join(', ');
    limitations.add('$names 근무는 출퇴근 시각이 없어 그날은 계산에서 빠졌어요. (설정 → 근무시간 및 OT 설정)');
  }
  if (pendingCount > 0) {
    limitations.add('확인하지 않은 자동 수면 기록 $pendingCount건은 반영하지 않았어요.');
  }

  ranked.sort((a, b) =>
      a.rank != b.rank ? a.rank.compareTo(b.rank) : a.order.compareTo(b.order));
  final seen = <String>{};
  final seenTopics = <BriefingTopic>{};
  final actions = <BriefingAction>[];
  for (final r in ranked) {
    if (!seen.add(r.action.id)) continue;
    // ⭐ 2026-09-18 - id가 달라도(예: extended_streak_rest/consecutive_workdays_rest)
    // 같은 topic이면 먼저 뽑힌(=더 우선순위 높은) 것 하나만 남긴다.
    if (r.action.topic != BriefingTopic.other &&
        !seenTopics.add(r.action.topic)) continue;
    actions.add(r.action);
    if (actions.length == kBriefingMaxActions) break;
  }

  // ⭐ 2026-09-18 - facts도 같은 원칙으로 topic 중복을 한 번 더 거른다(위 longWorkStreak
  // 통합으로 지금은 실제로 겹치는 topic이 없지만, 앞으로 신호가 늘어날 때의 안전망).
  final dedupedFacts = _dedupByTopic(facts, (f) => f.topic);

  return RecoveryBriefing(
    level: base.level,
    phase: phase,
    situation: situation,
    facts: dedupedFacts.take(kBriefingMaxFacts).toList(),
    actions: actions,
    limitations: limitations,
  );
}
