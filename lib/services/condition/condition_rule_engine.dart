// lib/services/condition/condition_rule_engine.dart
//
// ⭐ 컨디션 매니저 Phase 2~3 - Evidence 기반 Rule Engine + 수면 추천.
// shift_pattern_analyzer.dart가 계산한 "사실"에 이름 붙은 rule을 적용해서
// ConditionLevel(NORMAL/ATTENTION/HIGH_LOAD)과 Finding/Tip을 만든다.
//
// ⚠️ 지켜야 할 원칙(컨디션매니저_설계.md 5장 → 2026-09-04 v2로 개정,
// 컨디션매니저_근거자료.md 결론, 2026-09-17 v3 재설계 - CLAUDE.md 설계 기록 참고):
//  1. ConditionLevel을 올리는 조건은 evidence_database.dart에 실제로 대응
//     항목이 있는 신호만 쓴다 - "여기 없는 근거는 어떤 Rule에도 안 쓴다"는
//     원칙 자체는 그대로 유지. 2026-09-17에 "절대 12시간 임계값 단독 트리거"
//     (RULE_LONG_SHIFT)를 폐지하고, 그 자리를 근무시간대별 일반화된 연속근무
//     버킷(streakBucketFor, EVIDENCE-005)과 "최근 7일 총 실근무시간"(기본근무+
//     초과근무, RULE_WEEKLY_TOTAL_LOAD, EVIDENCE-012/014)으로 대체함 - 절대적인
//     하루 근무시간이 아니라 "쉬지 못하고 누적됐는지"를 본다. 근거가 약한 항목
//     (연속근무일수 자체, RULE_CONSECUTIVE_WORKDAYS)은 RULE_COMPOUND_HIGH_LOAD와
//     같은 방식으로 "이 앱의 판단"임을 문구에 명시하고 쓴다. 2026-09-18 - "최근 7일
//     총 실근무시간"까지도 EU/IOM 절대값 비교가 12시간 표준 근무자에게 매일
//     발동하는 문제가 있어(실측 8주 시뮬레이션 NORMAL 0%), RULE_WEEKLY_TOTAL_LOAD를
//     RULE_WEEKLY_LOAD_INCREASE로 개명하고 개인 기준선(analyzer.baselineWeeklyMinutesAsOf)
//     대비 증가 폭으로 재설계함(weeklyLoadIncrease 참고). EU/IOM 절대값은
//     ScheduleLoadProfile(레벨과 무관한 구조적 배경 정보)로 분리.
//  2. 모든 Finding/Tip은 evidenceIds를 최소 1개 가져야 한다.
//  3. 숫자 점수(0~100)나 %, 질병 위험도는 어디에도 만들지 않는다(2026-09-15 - 유일한 예외였던
//     condition_score.dart를 출시 적합성 재검토 후 삭제함).
//  4. 아래 기준값 상수는 recovery_briefing_engine.dart("오늘의 컨디션")가 그대로 가져다 쓴다 -
//     같은 주장에 다른 숫자를 쓰지 않도록 여기 한 곳에만 둔다.

import 'dart:math' as math;

import 'package:flutter/material.dart' show DateTimeRange;
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';

enum ConditionLevel { normal, attention, highLoad }

extension ConditionLevelLabel on ConditionLevel {
  String get emoji {
    switch (this) {
      case ConditionLevel.normal:
        return '🟢';
      case ConditionLevel.attention:
        return '🟡';
      case ConditionLevel.highLoad:
        return '🔴';
    }
  }

  String get label {
    switch (this) {
      case ConditionLevel.normal:
        return '일반';
      case ConditionLevel.attention:
        return '주의가 필요한 날';
      case ConditionLevel.highLoad:
        return '회복 부담이 큰 날';
    }
  }
}

/// "왜 이런 상태인지/왜 이런 맥락인지"를 설명하는 한 줄. ruleId가 있으면
/// ConditionLevel 판정에 실제로 관여한 rule, 없으면 순수 설명용(방향/연속일수 등).
class ConditionFinding {
  final String? ruleId;
  final String message;
  final List<String> evidenceIds;

  const ConditionFinding({this.ruleId, required this.message, required this.evidenceIds});
}

class ConditionTip {
  final String ruleId;
  final String category; // sleep/caffeine/meal/exercise/light/fatigue/recovery (Firebase 확장 대비, 스펙 20장과 동일 값)
  final String emoji;
  final String title;
  final String message;
  final List<String> evidenceIds;

  const ConditionTip({
    required this.ruleId,
    required this.category,
    required this.emoji,
    required this.title,
    required this.message,
    required this.evidenceIds,
  });
}

class ConditionResult {
  final DateTime date;
  final ShiftInstance today;
  final ConditionLevel level;
  final List<ConditionFinding> levelFindings; // 상태 판정에 실제로 쓰인 이유
  final List<ConditionFinding> contextFindings; // 판정에 안 쓰인 설명용 맥락
  final List<ConditionTip> tips; // 우선순위 순
  final DateTimeRange? recommendedSleepWindow;
  final bool sleepWindowShorterThanRecommended;
  final int? recoveryMinutes;
  final int? consecutiveNightDays;
  final int? consecutiveWorkDays;
  // ⭐ 2026-09-18 - 개인 기준선(baselineWeeklyMinutesAsOf 결과)을 그대로 노출해서
  // recovery_briefing_engine.dart와 scheduleLoadProfileProvider(condition_provider.dart)가
  // 같은 값을 재계산 없이 재사용하게 함(원칙 4 - 같은 주장에 다른 숫자를 쓰지 않는다).
  final int? weeklyBaselineMinutes;

  const ConditionResult({
    required this.date,
    required this.today,
    required this.level,
    required this.levelFindings,
    required this.contextFindings,
    required this.tips,
    required this.recommendedSleepWindow,
    required this.sleepWindowShorterThanRecommended,
    required this.recoveryMinutes,
    required this.consecutiveNightDays,
    required this.consecutiveWorkDays,
    required this.weeklyBaselineMinutes,
  });
}

/// 근무시간대별로 일반화한 "연속 장시간근무 후 필요 휴식" 한 세트(EVIDENCE-005,
/// 2026-09-17 재조사 - NIOSH mod5/05.html은 근무시간대(8h/10h/12h)별로 다른 연속일수
/// 기준을 원문에 명시함). [floorMinutes]는 이 구간의 최소 근무시간 - 연속일수는 이
/// 값 이상인 날만 센다(ShiftPatternAnalyzer.consecutiveLongShiftStreakEndingAt에 그대로
/// 넘김).
class ShiftStreakBucket {
  final int floorMinutes;
  final int thresholdDays;
  final int requiredBreakMinutes;
  final List<String> evidenceIds;

  const ShiftStreakBucket({
    required this.floorMinutes,
    required this.thresholdDays,
    required this.requiredBreakMinutes,
    required this.evidenceIds,
  });
}

/// ⭐ 2026-09-18 - "이 근무 패턴 자체가 구조적으로 EU/IOM 절대 기준을 넘는지"를
/// 담는 조용한 배경 정보. RULE_WEEKLY_LOAD_INCREASE(개인 기준선 대비 늘었는지)와는
/// 완전히 다른 질문이라 [ConditionLevel]에 전혀 영향을 안 준다 - 스케줄 자체가
/// 안 바뀌면 매일 똑같은 값이라, "오늘의 알림"이 아니라 "이 근무의 배경 정보"로
/// 화면에 한 번만 조용히 보여줘야 한다(사용자 지적 - 매일 반복되는 캐션 취급 금지).
class ScheduleLoadProfile {
  final int baselineWeeklyMinutes;
  final bool exceedsIomLimit; // 주 60시간 이상(EVIDENCE-014)
  final String note;
  final List<String> evidenceIds;

  const ScheduleLoadProfile({
    required this.baselineWeeklyMinutes,
    required this.exceedsIomLimit,
    required this.note,
    required this.evidenceIds,
  });
}

class ConditionRuleEngine {
  static const minRecoveryMinutes = 11 * 60; // EVIDENCE-002, EVIDENCE-003
  static const longShiftThresholdMinutes = 12 * 60; // EVIDENCE-004, EVIDENCE-005 12시간대 구간
  static const extendedStreakDays = 3; // EVIDENCE-005 원문 숫자(12시간대)
  static const extendedStreakRequiredBreakMinutes = 48 * 60; // EVIDENCE-005 원문 숫자("2일", 12시간대)
  // ⭐ 2026-09-17 - EVIDENCE-005 재조사로 확인한 10시간대/8시간대 구간(원문: "10시간
  // 근무 4일 또는 8시간 근무 5일 후 1~2일의 완전한 휴식"). 필요 휴식은 원문이 "1~2일"로
  // 폭을 주므로 보수적으로 짧은 쪽(1일=24시간)을 임계값으로 씀 - 12시간대(원문이 "2일"로
  // 단일 수치를 명시)와 구분.
  static const midShiftThresholdMinutes = 10 * 60;
  static const midStreakDays = 4;
  static const shortShiftThresholdMinutes = 8 * 60;
  static const shortStreakDays = 5;
  static const genericRequiredBreakMinutes = 24 * 60;
  static const recommendedSleepMinMinutes = 7 * 60; // EVIDENCE-011
  static const recommendedSleepMaxMinutes = 9 * 60; // EVIDENCE-011
  static const sleepBufferMinutes = 60; // ⚠️ 연구값 아님 - 이동/정리 여유(설계 문서 6장 명시)
  static const caffeineCutoffHoursBeforeSleep = 6; // EVIDENCE-008
  // ⭐ 2026-09-04 v2 추가, 2026-09-17 재설계, 2026-09-18 재설계 - 최근 7일 "총 실근무시간"
  // (기본근무+초과근무, 근무시간대와 무관하게 누적)을 더 이상 EU 48시간(EVIDENCE-012)/
  // IOM 60시간(EVIDENCE-014) 절대값과 비교하지 않는다(계기: 12시간 표준 근무자는
  // 구조적으로 주 48~60시간이 정상이라, 절대 임계값으로는 "보통인 날"이 하루도
  // 없었음 - 실측 8주 시뮬레이션 NORMAL 0%). 이제 개인 기준선(analyzer.
  // baselineWeeklyMinutesAsOf) 대비 "얼마나 늘었는지"로 판단한다(weeklyLoadIncrease
  // 참고) - 아래 두 값은 그 증가 폭 임계값(퍼센트/최소분 하한, 정확한 수치는
  // 논문값이 아니라 이 앱의 판단). EU/IOM 절대 수치는 이제 ScheduleLoadProfile
  // (구조적 배경 정보, 레벨과 무관)에서만 쓴다.
  // 2026-09-15 - 예전엔 condition_score.dart/today_forecast_engine.dart에도 같은 값이 따로 있었는데 둘 다
  // 삭제됐고, recovery_briefing_engine.dart는 이 상수를 직접 참조한다(값은 여기서만 바꿀 것).
  static const overtimeLookbackDays = 7;
  static const weeklyLoadAttentionMinutes = 48 * 60; // EVIDENCE-012 - ScheduleLoadProfile에서만 씀
  static const weeklyLoadSevereMinutes = 60 * 60; // EVIDENCE-014 - ScheduleLoadProfile에서만 씀
  // ⭐ 2026-09-18 - 개인 기준선 대비 증가 폭 임계값. 퍼센트(기준선의 15%/25%)와
  // 최소분 하한(6시간/12시간) 중 큰 쪽을 씀 - 기준선이 아주 짧은 사람(예: 주
  // 20시간 파트타임)에게 퍼센트만 쓰면 몇 십 분 차이로도 발동해버리는 걸 막고,
  // 기준선이 아주 긴 사람에게 최소분만 쓰면 둔감해지는 걸 막는 절충. 정확한
  // 15%/25%/6h/12h 수치는 논문 근거가 아니라 이 앱이 보수적으로 정한 값.
  static const weeklyLoadIncreaseAttentionRatio = 0.15;
  static const weeklyLoadIncreaseSevereRatio = 0.25;
  static const weeklyLoadIncreaseMinAttentionMinutes = 6 * 60;
  static const weeklyLoadIncreaseMinSevereMinutes = 12 * 60;
  // ⭐ 2026-09-17 - "근무시간과 무관하게 쉬는 날 없이 이어지는 근무 자체"(EVIDENCE-005의
  // 일반 원칙 "며칠 몰아 일하고 몰아 쉬는 패턴을 피하라"만 빌림 - 정확한 일수는 이 앱의
  // 판단이라 appUsage에도 명시함).
  static const consecutiveWorkdayAttentionThreshold = 7;
  static const consecutiveWorkdaySevereThreshold = 10;

  final ShiftPatternAnalyzer analyzer;

  const ConditionRuleEngine(this.analyzer);

  /// 오늘 근무의 실제 근무시간(분)에 맞는 연속근무 버킷(EVIDENCE-005 일반화). 8시간
  /// 미만은 이 근거가 다루지 않아 null(레벨 판정에 안 씀 - RULE_CONSECUTIVE_WORKDAYS가
  /// 근무시간과 무관하게 별도로 다룸).
  static ShiftStreakBucket? streakBucketFor(int shiftMinutes) {
    if (shiftMinutes >= longShiftThresholdMinutes) {
      return const ShiftStreakBucket(
        floorMinutes: longShiftThresholdMinutes,
        thresholdDays: extendedStreakDays,
        requiredBreakMinutes: extendedStreakRequiredBreakMinutes,
        evidenceIds: ['EVIDENCE-004', 'EVIDENCE-005'],
      );
    }
    if (shiftMinutes >= midShiftThresholdMinutes) {
      return const ShiftStreakBucket(
        floorMinutes: midShiftThresholdMinutes,
        thresholdDays: midStreakDays,
        requiredBreakMinutes: genericRequiredBreakMinutes,
        evidenceIds: ['EVIDENCE-005'],
      );
    }
    if (shiftMinutes >= shortShiftThresholdMinutes) {
      return const ShiftStreakBucket(
        floorMinutes: shortShiftThresholdMinutes,
        thresholdDays: shortStreakDays,
        requiredBreakMinutes: genericRequiredBreakMinutes,
        evidenceIds: ['EVIDENCE-005'],
      );
    }
    return null;
  }

  /// ⭐ 2026-09-18 - 연속일수([ConsecutiveStreak], shift_pattern_analyzer.dart)를 문구로
  /// 바꾸는 유일한 경로. 안전 상한(capped)에 도달했으면 [normal]의 숫자 대신 [capped]
  /// 문장 전체를 쓴다 - 숫자만 치환하면("휴무 없이 매우 오래일째") 문법이 깨지므로
  /// 항상 완결된 문장 두 개를 따로 받는다. condition_rule_engine.dart와
  /// recovery_briefing_engine.dart가 연속일수를 문구에 넣는 모든 곳에서 이걸 거친다.
  static String streakClause(
    ConsecutiveStreak streak, {
    required String Function(int days) normal,
    required String capped,
  }) {
    return streak.capped ? capped : normal(streak.days);
  }

  /// ⭐ 2026-09-18 - "최근 7일 실근무시간이 이 사람의 평소보다 얼마나 늘었는지"
  /// 판정을 여기 하나로 통일(원칙 4 - 같은 주장에 다른 숫자를 쓰지 않는다).
  /// evaluate()와 recovery_briefing_engine.dart(오늘의 컨디션)가 둘 다 이 함수만
  /// 부른다. [baselineWeeklyMinutes]가 null이면(불규칙 근무라 기준선 계산 불가 등)
  /// "비교할 평소가 없다"는 뜻이라 항상 조용하다(근거 없으면 신호를 안 낸다는
  /// 기존 원칙과 동일).
  static ({bool heavy, bool severe, int? extraMinutes}) weeklyLoadIncrease({
    required int actualWeeklyMinutes,
    required int? baselineWeeklyMinutes,
  }) {
    if (baselineWeeklyMinutes == null) return (heavy: false, severe: false, extraMinutes: null);
    final extra = actualWeeklyMinutes - baselineWeeklyMinutes;
    final attentionThreshold = math.max(
      weeklyLoadIncreaseMinAttentionMinutes,
      (baselineWeeklyMinutes * weeklyLoadIncreaseAttentionRatio).round(),
    );
    final severeThreshold = math.max(
      weeklyLoadIncreaseMinSevereMinutes,
      (baselineWeeklyMinutes * weeklyLoadIncreaseSevereRatio).round(),
    );
    return (heavy: extra >= attentionThreshold, severe: extra >= severeThreshold, extraMinutes: extra);
  }

  /// ⭐ 2026-09-18 - 개인 기준선이 EU 48시간(EVIDENCE-012)/IOM 60시간(EVIDENCE-014)
  /// 절대 기준 자체를 구조적으로 넘는지(레벨과 무관, 조용한 배경 정보 - 클래스
  /// 설명 참고). 기준선을 모르거나(null) 둘 다 안 넘으면 보여줄 게 없어 null.
  static ScheduleLoadProfile? scheduleLoadProfileFor(int? baselineWeeklyMinutes) {
    if (baselineWeeklyMinutes == null || baselineWeeklyMinutes < weeklyLoadAttentionMinutes) return null;
    final severe = baselineWeeklyMinutes >= weeklyLoadSevereMinutes;
    return ScheduleLoadProfile(
      baselineWeeklyMinutes: baselineWeeklyMinutes,
      exceedsIomLimit: severe,
      note: severe
          ? '이 근무 패턴은 평균 주 ${_formatHours(baselineWeeklyMinutes)} 안팎이에요. 간호사 근무시간 권고 상한(주 60시간)과 '
              'EU 근로시간지침 기준(주 48시간)을 구조적으로 넘는 편이에요.'
          : '이 근무 패턴은 평균 주 ${_formatHours(baselineWeeklyMinutes)} 안팎이에요. EU 근로시간지침 기준(주 48시간)을 '
              '구조적으로 넘는 편이에요.',
      evidenceIds: severe ? const ['EVIDENCE-012', 'EVIDENCE-014'] : const ['EVIDENCE-012'],
    );
  }

  // ⭐ 2026-09-04 v2 - [otMinutesByDate]는 RULE_WEEKLY_OVERTIME(EVIDENCE-012)
  // 계산용. 기본값(빈 맵)이라 기존 호출부(테스트 등)는 그대로 컴파일되지만,
  // 그러면 이 신호는 항상 꺼진 채로 평가됨 - 실제 앱 배선은
  // condition_provider.dart의 todayConditionResultProvider가 담당.
  ConditionResult evaluate(DateTime date, {Map<String, int> otMinutesByDate = const {}}) {
    final today = analyzer.instanceForDate(date);

    if (today.isUnset) {
      return ConditionResult(
        date: date,
        today: today,
        level: ConditionLevel.normal,
        levelFindings: const [],
        contextFindings: const [
          ConditionFinding(message: '근무 일정이 아직 설정되지 않았습니다.', evidenceIds: []),
        ],
        tips: const [],
        recommendedSleepWindow: null,
        sleepWindowShorterThanRecommended: false,
        recoveryMinutes: null,
        consecutiveNightDays: null,
        consecutiveWorkDays: null,
        weeklyBaselineMinutes: null,
      );
    }

    final levelFindings = <ConditionFinding>[];
    final contextFindings = <ConditionFinding>[];
    final tips = <ConditionTip>[];

    // ── 회복구간(가장 최근 근무 종료 ~ 다음 근무 시작) 계산 ──────────────
    final window = analyzer.recoveryWindowContaining(date);
    final recoveryMinutes = window?.start.difference(window.end).inMinutes;

    final shortRecovery = recoveryMinutes != null && recoveryMinutes < minRecoveryMinutes;
    // "오늘/이 회복구간을 만든 근무"의 길이 - today가 근무일이면 그 근무, 아니면
    // 회복구간을 시작시킨 직전 근무의 길이를 최근접 근무일에서 다시 조회.
    int? relevantShiftMinutes = today.durationMinutes;
    if (relevantShiftMinutes == null && window != null) {
      // window.end는 직전 근무의 종료시각 - 그 날짜의 인스턴스를 다시 찾음(최대 14일 역탐색)
      for (var i = 0; i <= 14; i++) {
        final d = date.subtract(Duration(days: i));
        final inst = analyzer.instanceForDate(d);
        if (inst.end == window.end) {
          relevantShiftMinutes = inst.durationMinutes;
          break;
        }
      }
    }
    // ⭐ 2026-09-17 재설계 - "절대 12시간이면 위험" 단독 트리거를 폐지함(사용자 지적:
    // 12시간이 표준 근무인 사람에게 매 근무일 캐션이 뜨는 건 실행 불가능한 정보이자
    // 경고 피로만 유발함). 대신 relevantShiftMinutes는 아래 RULE_EXTENDED_STREAK_SHORT_
    // BREAK의 버킷 선택에만 쓰고(연속 며칠째인지 + 그 다음 회복시간이 짧은지로 판단),
    // "오늘 하루 12시간 자체"는 더 이상 levelFindings에 안 올린다.

    // ⭐ 2026-09-04 v2 최초 추가, 2026-09-17 재설계, 2026-09-18 재설계 - 최근 7일 "총
    // 실근무시간"(기본근무+초과근무, 근무시간대와 무관하게 누적). 예전엔 초과근무
    // (date_overtime)만 더했는데, 그러면 "12시간×15일/월"과 "8시간×22일/월"처럼 총량은
    // 비슷한데 하루 근무시간만 다른 두 패턴을 공정하게 비교할 수 없었음(기본근무가
    // 누적 대상에서 아예 빠져 있었기 때문) - 이제 기본근무까지 합산한다. 2026-09-18 -
    // 이 총량을 EU/IOM 절대값과 비교하는 대신 개인 기준선과 비교(weeklyLoadIncrease,
    // 위 클래스 주석 참고).
    var weeklyBaseMinutes = 0;
    for (var i = 0; i < overtimeLookbackDays; i++) {
      final inst = analyzer.instanceForDate(date.subtract(Duration(days: i)));
      if (inst.isWorkDay) weeklyBaseMinutes += inst.durationMinutes ?? 0;
    }
    var otTotalMinutes = 0;
    for (var i = 0; i < overtimeLookbackDays; i++) {
      otTotalMinutes += otMinutesByDate[dateKey(date.subtract(Duration(days: i)))] ?? 0;
    }
    final weeklyTotalMinutes = weeklyBaseMinutes + otTotalMinutes;
    final weeklyBaselineMinutes = analyzer.baselineWeeklyMinutesAsOf(date);
    final loadIncrease = weeklyLoadIncrease(
      actualWeeklyMinutes: weeklyTotalMinutes,
      baselineWeeklyMinutes: weeklyBaselineMinutes,
    );
    final heavyLoad = loadIncrease.heavy;
    final severeLoad = loadIncrease.severe;

    // ⭐ 2026-09-04 v2 - 교대 방향(EVIDENCE-001). 비교 연구 수준 근거("정방향이
    // 상대적으로 유리한 경향"이지 절대 위험 수치가 아님)라 이 신호 하나만으로는
    // 아래에서 ATTENTION까지만 - HIGH_LOAD는 다른 신호와 겹칠 때만(근거 강도에
    // 맞게 취급을 다르게 함 - "빠짐없이 활용"하되 근거가 약한 항목을 강한 항목과
    // 동일한 무게로 쓰진 않음).
    final direction = analyzer.analyzeDirection();
    final isBackward = direction != null && direction.direction == ShiftDirection.backward;

    // ⭐ 2026-09-04 v2 후속 - 연속 야간근무 횟수(EVIDENCE-013, Folkard & Tucker
    // 2003 - 재인용 출처는 Frontiers 2024 rapid evidence review). "장시간근무
    // 연속"(EVIDENCE-004/005, 근무시간 축)과는 다른 축 - 근무 "종류"가 야간이고
    // "연속 횟수"가 쌓일수록 사고·실수 위험이 누적되며, 특히 야간근무의 연속은
    // 낮/오후근무 연속보다 위험 증가가 더 가파르다고 보고됨. 원 연구가 "4일째부터
    // 가속화"라고 명시하므로 여기서도 3일은 ATTENTION급(아래 신호군에 합류),
    // 4일 이상은 그 자체로 단독 HIGH_LOAD로 취급을 다르게 함(주석 아래
    // RULE_EXTENDED_STREAK_SHORT_BREAK와 동일한 패턴).
    // (consecutiveNightStreakEndingAt은 오늘이 야간이 아니면 항상 0을 반환하므로
    // 별도로 "오늘이 야간인지"를 다시 확인할 필요 없음 - shift_pattern_analyzer.dart 참고.)
    final consecutiveNight = analyzer.consecutiveNightStreakEndingAt(date);
    final nightStreakAttention = consecutiveNight.days >= 3;
    final nightStreakSevere = consecutiveNight.days >= 4;

    // ⭐ 2026-09-17 재설계 - 근무시간과 무관하게 "쉬는 날 없이 이어지는 근무 일수"
    // 자체(사용자 지적: "4시간짜리 근무여도 7일 연속이면 힘들다"). EVIDENCE-005 원문에
    // 정확한 상한 수치는 없고 "며칠 몰아 일하고 몰아 쉬는 패턴을 피하라"는 일반 원칙만
    // 있어서, 정확한 일수 기준(7일/10일)은 이 앱이 보수적으로 정한 값임을 문구에도 명시함
    // (RULE_COMPOUND_HIGH_LOAD와 동일한 "이 앱의 판단" 취급).
    final consecutiveWork =
        today.isWorkDay ? analyzer.consecutiveWorkStreakEndingAt(date) : (days: 0, capped: false);
    final workStreakAttention = consecutiveWork.days >= consecutiveWorkdayAttentionThreshold;
    final workStreakSevere = consecutiveWork.days >= consecutiveWorkdaySevereThreshold;

    // ⭐ 2026-09-04 v2 - ATTENTION급 개별 신호(회복시간 부족/주간 총 근무시간 초과/
    // 역방향 교대/연속 야간근무 3일 이상/연속근무일수 누적)를 한데 모아 "몇 개나
    // 겹치는지"로 최종 레벨을 정함: 1개면 ATTENTION, 2개 이상이면 HIGH_LOAD.
    // "2개 이상이면 심각"이라는 조합 기준 자체는 특정 논문 수치가 아니라 이 앱의
    // 설계 판단(여러 연구가 개별적으로 뒷받침하는 부담이 겹치면 누적된다는
    // 상식적 추론) - 문구에도 그 점을 명시함. 각 신호 자체의 evidenceIds는 개별
    // Finding에 그대로 남아 있어 "무엇이 왜"는 항상 추적 가능함.
    final attentionSignalIds = <String>[
      if (shortRecovery) 'RULE_SHORT_RECOVERY',
      if (heavyLoad) 'RULE_WEEKLY_LOAD_INCREASE',
      if (isBackward) 'RULE_BACKWARD_DIRECTION',
      if (nightStreakAttention) 'RULE_CONSECUTIVE_NIGHT_SHIFTS',
      if (workStreakAttention) 'RULE_CONSECUTIVE_WORKDAYS',
    ];
    var level = attentionSignalIds.isEmpty ? ConditionLevel.normal : ConditionLevel.attention;

    if (shortRecovery) {
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_SHORT_RECOVERY',
        message: '다음 근무까지 회복시간이 ${_formatHours(recoveryMinutes)}로, '
            '권장 최소 기준(11시간)보다 짧습니다.',
        evidenceIds: const ['EVIDENCE-002', 'EVIDENCE-003'],
      ));
    }
    if (heavyLoad) {
      // heavyLoad가 true면 weeklyLoadIncrease() 정의상 baseline/extraMinutes는 항상 non-null.
      final baseline = weeklyBaselineMinutes!;
      final extra = loadIncrease.extraMinutes!;
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_WEEKLY_LOAD_INCREASE',
        message: severeLoad
            ? '최근 7일간 실제 근무시간이 총 ${_formatHours(weeklyTotalMinutes)}으로, 평소(주 '
                '${_formatHours(baseline)} 안팎)보다 ${_formatHours(extra)} 더 많습니다. 평소보다 근무가 많이 '
                '누적되면 피로가 커질 수 있습니다(정확한 증가 폭 기준은 특정 연구 수치가 아니라 이 앱이 '
                '보수적으로 정한 값입니다).'
            : '최근 7일간 실제 근무시간이 총 ${_formatHours(weeklyTotalMinutes)}으로, 평소(주 '
                '${_formatHours(baseline)} 안팎)보다 ${_formatHours(extra)} 더 많습니다. 평소보다 근무가 '
                '누적되면 피로가 커질 수 있습니다(정확한 증가 폭 기준은 이 앱의 판단입니다).',
        evidenceIds: severeLoad ? const ['EVIDENCE-012', 'EVIDENCE-014'] : const ['EVIDENCE-012'],
      ));
    }
    if (workStreakAttention) {
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_CONSECUTIVE_WORKDAYS',
        message: streakClause(
          consecutiveWork,
          normal: (days) => workStreakSevere
              ? '오늘로 연속 근무 $days일째입니다. 하루 근무시간과 무관하게 쉬는 날 '
                  '없이 근무가 길게 이어지는 것 자체가 피로 누적으로 이어질 수 있습니다 '
                  '(정확한 일수 기준은 특정 연구 수치가 아니라 이 앱이 보수적으로 정한 값입니다).'
              : '오늘로 연속 근무 $days일째입니다. 하루 근무시간과 무관하게 쉬는 날 없이 '
                  '근무가 이어지면 피로가 쌓일 수 있습니다(정확한 일수 기준은 이 앱의 판단입니다).',
          capped: '휴무 없이 매우 오랜 기간 근무가 이어지고 있습니다. 하루 근무시간과 무관하게 '
              '쉬는 날 없이 근무가 길게 이어지는 것 자체가 피로 누적으로 이어질 수 있습니다 '
              '(정확한 일수 기준은 특정 연구 수치가 아니라 이 앱이 보수적으로 정한 값입니다).',
        ),
        evidenceIds: const ['EVIDENCE-005'],
      ));
    }
    if (isBackward) {
      levelFindings.add(const ConditionFinding(
        ruleId: 'RULE_BACKWARD_DIRECTION',
        message: '오늘은 역방향 교대 전환에 해당합니다. 일부 연구에서는 역방향이 '
            '정방향보다 적응에 상대적으로 불리한 경향으로 보고돼, 다른 부담과 '
            '겹치면 회복이 더 어려울 수 있습니다.',
        evidenceIds: ['EVIDENCE-001'],
      ));
    }
    if (nightStreakAttention) {
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_CONSECUTIVE_NIGHT_SHIFTS',
        message: streakClause(
          consecutiveNight,
          normal: (days) => nightStreakSevere
              ? '연속 야간근무가 $days일째로 접어들었습니다. 관련 연구는 '
                  '이 시점부터 사고·실수 위험이 뚜렷하게 가속화된다고 보고하며, 일부 '
                  '안전 최우선 산업의 근무 규정은 연속 야간근무를 보통 4일로 상한선을 '
                  '둡니다.'
              : '연속 야간근무 $days일째입니다. 관련 연구는 야간근무가 '
                  '연속될수록(특히 낮·오후근무 연속보다 더 가파르게) 사고·실수 위험이 '
                  '누적된다고 보고합니다.',
          capped: '연속 야간근무가 휴무 없이 매우 오래 이어지고 있습니다. 관련 연구는 '
              '이 시점부터 사고·실수 위험이 뚜렷하게 가속화된다고 보고하며, 일부 '
              '안전 최우선 산업의 근무 규정은 연속 야간근무를 보통 4일로 상한선을 둡니다.',
        ),
        evidenceIds: const ['EVIDENCE-013'],
      ));
    }

    if (attentionSignalIds.length >= 2) {
      level = ConditionLevel.highLoad;
      final compoundLabels = [
        if (shortRecovery) '회복시간 부족',
        if (heavyLoad) '평소보다 근무 누적',
        if (isBackward) '역방향 교대 전환',
        if (nightStreakAttention) '연속 야간근무',
        if (workStreakAttention) '연속근무일수 누적',
      ];
      final compoundEvidenceIds = <String>{
        if (shortRecovery) ...['EVIDENCE-002', 'EVIDENCE-003'],
        if (heavyLoad) ...(severeLoad ? ['EVIDENCE-012', 'EVIDENCE-014'] : ['EVIDENCE-012']),
        if (isBackward) 'EVIDENCE-001',
        if (nightStreakAttention) 'EVIDENCE-013',
        if (workStreakAttention) 'EVIDENCE-005',
      };
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_COMPOUND_HIGH_LOAD',
        message: '${compoundLabels.join(' + ')}이 오늘 함께 겹쳐 회복 부담이 큰 '
            '날로 판단됩니다. (여러 부담이 겹치면 누적된다고 보는 것은 이 앱의 '
            '판단이며, 개별 요인 각각의 근거는 위 항목을 참고하세요.)',
        evidenceIds: compoundEvidenceIds.toList(),
      ));
    }

    // ⭐ 2026-09-17 재설계 - 근무시간대별 일반화(EVIDENCE-005): 오늘/이 회복구간을 만든
    // 근무의 실제 길이에 맞는 버킷(8h→5일, 10h→4일, 12h→3일)을 고르고, 그 길이 이상인
    // 날이 버킷 기준일수 이상 연속됐는데 그 다음 회복시간까지 짧으면 근거가 강해(원문이
    // 제시하는 정량적 권고) 위 조합 규칙과 무관하게 그 자체로도 단독 HIGH_LOAD. 8시간
    // 미만 근무는 이 근거가 다루지 않아 버킷이 없음(streakBucketFor가 null 반환) -
    // RULE_CONSECUTIVE_WORKDAYS가 근무시간과 무관하게 별도로 다룸.
    final longShiftStreakDate = window != null
        ? _findInstanceDateByEnd(date, window.end) ?? date
        : date;
    final streakBucket = relevantShiftMinutes != null ? streakBucketFor(relevantShiftMinutes) : null;
    if (streakBucket != null) {
      final bucketStreak = analyzer.consecutiveLongShiftStreakEndingAt(
        longShiftStreakDate,
        thresholdMinutes: streakBucket.floorMinutes,
      );
      if (bucketStreak.days >= streakBucket.thresholdDays &&
          (recoveryMinutes == null || recoveryMinutes < streakBucket.requiredBreakMinutes)) {
        final floorHours = streakBucket.floorMinutes ~/ 60;
        final breakDays = (streakBucket.requiredBreakMinutes / (24 * 60)).ceil();
        levelFindings.add(ConditionFinding(
          ruleId: 'RULE_EXTENDED_STREAK_SHORT_BREAK',
          message: streakClause(
            bucketStreak,
            normal: (days) => '$floorHours시간 이상 근무가 $days일 연속 이어졌습니다. 관련 훈련자료는 '
                '이런 경우 최소 $breakDays일의 휴식을 고려할 것을 제안합니다.',
            capped: '$floorHours시간 이상 근무가 휴무 없이 매우 오래 이어지고 있습니다. 관련 '
                '훈련자료는 이런 경우 최소 $breakDays일의 휴식을 고려할 것을 제안합니다.',
          ),
          evidenceIds: streakBucket.evidenceIds,
        ));
        level = ConditionLevel.highLoad;
      }
    }

    // ⭐ 2026-09-04 v2 후속 - 연속 야간근무 4일 이상 / 2026-09-17 - 주간 누적 근무시간
    // 60시간 이상 / 연속근무일수 10일 이상은 그 자체로 단독 HIGH_LOAD(원 연구·근거가
    // "이 시점부터 가속화·상한 초과"라고 명시하는 구간 - 위 RULE_EXTENDED_
    // STREAK_SHORT_BREAK와 동일한 취급).
    if (nightStreakSevere || severeLoad || workStreakSevere) {
      level = ConditionLevel.highLoad;
    }

    // ── 설명용 맥락(판정에는 영향 없음) ──────────────────────────────
    if (consecutiveNight.days >= 1 && !nightStreakAttention) {
      // 3일 미만은 여전히 순수 계산값(대응 evidence 없음)이라 판정에도 안 쓰고
      // 사실만 서술 - 3일 이상은 이제 위에서 RULE_CONSECUTIVE_NIGHT_SHIFTS로
      // 이미 다뤘으니 여기서 중복 표시 안 함. (1~2일뿐이라 캡에 걸릴 수 없음 -
      // streakClause 불필요.)
      contextFindings.add(ConditionFinding(
        message: '오늘로 연속 야간근무 ${consecutiveNight.days}일째입니다.',
        evidenceIds: const [],
      ));
    }
    if (today.isOff && consecutiveNight.days == 0) {
      final ySt = analyzer.consecutiveNightStreakEndingAt(date.subtract(const Duration(days: 1)));
      if (ySt.days >= 1) {
        contextFindings.add(ConditionFinding(
          ruleId: 'RULE_NIGHT_FOLLOWED_BY_OFF',
          message: streakClause(
            ySt,
            normal: (days) => '어제까지 이어진 야간근무($days일) 이후의 휴무입니다. 회복을 위한 '
                '수면·휴식 구간으로 활용해보세요.',
            capped: '휴무 없이 매우 오래 이어진 야간근무 이후의 휴무입니다. 회복을 위한 '
                '수면·휴식 구간으로 활용해보세요.',
          ),
          evidenceIds: const ['EVIDENCE-006'],
        ));
      }
    }

    // ⭐ 2026-09-04 v2 - 역방향은 이미 위에서 RULE_BACKWARD_DIRECTION(레벨
    // Finding)으로 다뤘으니 여기선 정방향일 때만 - 같은 내용을 두 번 보여주지
    // 않기 위함(direction 변수 자체는 위에서 이미 계산해둔 걸 재사용).
    if (direction != null && direction.direction == ShiftDirection.forward) {
      contextFindings.add(const ConditionFinding(
        ruleId: 'RULE_SHIFT_DIRECTION',
        message: '현재 교대는 정방향(주간→오후→야간)으로 진행됩니다. 일부 교대근무 '
            '연구에서는 정방향이 역방향보다 적응에 상대적으로 유리한 것으로 '
            '보고됩니다.',
        evidenceIds: ['EVIDENCE-001'],
      ));
    }

    // ── 추천(Tip) - 판정과 무관, 조건이 맞을 때만 노출 ───────────────
    DateTimeRange? sleepWindow;
    var sleepShorterThanRecommended = false;

    if (window != null) {
      final sleepStart = window.end.add(const Duration(minutes: sleepBufferMinutes));
      final maxBySleepLength = sleepStart.add(const Duration(minutes: recommendedSleepMaxMinutes));
      final maxByNextShift = window.start.subtract(const Duration(minutes: sleepBufferMinutes));
      final sleepEnd = maxBySleepLength.isBefore(maxByNextShift) ? maxBySleepLength : maxByNextShift;

      if (sleepEnd.isAfter(sleepStart)) {
        sleepWindow = DateTimeRange(start: sleepStart, end: sleepEnd);
        final actualMinutes = sleepEnd.difference(sleepStart).inMinutes;
        sleepShorterThanRecommended = actualMinutes < recommendedSleepMinMinutes;

        tips.add(ConditionTip(
          ruleId: 'RULE_SLEEP_WINDOW',
          category: 'sleep',
          emoji: '😴',
          title: '수면',
          message: '${_formatTime(sleepStart)} ~ ${_formatTime(sleepEnd)} 사이에 수면을 '
              '확보하기 좋은 시간대입니다. (목표 수면 7~9시간 기준)'
              '${sleepShorterThanRecommended ? " 다만 오늘은 가용 시간이 권장 범위보다 짧습니다." : ""}',
          evidenceIds: const ['EVIDENCE-011'],
        ));

        final cutoff = sleepStart.subtract(const Duration(hours: caffeineCutoffHoursBeforeSleep));
        tips.add(ConditionTip(
          ruleId: 'RULE_CAFFEINE_CUTOFF',
          category: 'caffeine',
          emoji: '☕',
          title: '카페인',
          message: '취침 목표 시각(${_formatTime(sleepStart)}) 6시간 전인 '
              '${_formatTime(cutoff)} 이후부터는 카페인 섭취를 줄이는 것이 좋습니다.',
          evidenceIds: const ['EVIDENCE-008'],
        ));
      } else {
        contextFindings.add(const ConditionFinding(
          message: '다음 근무까지 회복시간이 매우 짧아 별도의 수면 시간대를 제안하기 '
              '어렵습니다.',
          evidenceIds: [],
        ));
      }
    }

    if (today.category == ShiftTimeCategory.night) {
      tips.add(const ConditionTip(
        ruleId: 'RULE_MEAL_NIGHT_SHIFT',
        category: 'meal',
        emoji: '🍽',
        title: '식사',
        message: '야간근무 중에는 과식이나 기름지고 자극적인 음식을 피하고, 가벼운 '
            '식사 위주로 하는 것이 좋습니다.',
        evidenceIds: ['EVIDENCE-010'],
      ));
      tips.add(const ConditionTip(
        ruleId: 'RULE_LIGHT_COMMUTE_AFTER_NIGHT',
        category: 'light',
        emoji: '🕶',
        title: '빛 노출',
        message: '야간근무 후 귀가길에 강한 햇빛 노출을 줄이면(선글라스 등) 이후 '
            '수면에 도움이 될 수 있습니다. 단, 많이 졸린 상태라면 안전을 우선하고 '
            '가능하면 다른 사람이 운전하게 하세요.',
        evidenceIds: ['EVIDENCE-009'],
      ));
      tips.add(const ConditionTip(
        ruleId: 'RULE_NAP_BEFORE_NIGHT',
        category: 'fatigue',
        emoji: '💤',
        title: '낮잠',
        message: '야간근무 전 짧은 낮잠이 졸림을 줄이는 데 도움이 될 수 있다고 '
            '보고됩니다(근거 수준은 높지 않음). 낮잠 직후엔 잠시 몽롱할 수 있으니 '
            '운전 등은 피하세요.',
        evidenceIds: ['EVIDENCE-007'],
      ));
    }

    // 우선순위: sleep > light > caffeine > meal > fatigue > recovery
    const order = ['sleep', 'light', 'caffeine', 'meal', 'fatigue', 'recovery', 'exercise'];
    tips.sort((a, b) => order.indexOf(a.category).compareTo(order.indexOf(b.category)));

    return ConditionResult(
      date: date,
      today: today,
      level: level,
      levelFindings: levelFindings,
      contextFindings: contextFindings,
      tips: tips,
      recommendedSleepWindow: sleepWindow,
      sleepWindowShorterThanRecommended: sleepShorterThanRecommended,
      recoveryMinutes: recoveryMinutes,
      consecutiveNightDays: consecutiveNight.days,
      consecutiveWorkDays: consecutiveWork.days,
      weeklyBaselineMinutes: weeklyBaselineMinutes,
    );
  }

  DateTime? _findInstanceDateByEnd(DateTime around, DateTime end) {
    for (var i = 0; i <= 14; i++) {
      final d = around.subtract(Duration(days: i));
      if (analyzer.instanceForDate(d).end == end) return d;
    }
    return null;
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _formatHours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  // RULE_WEEKLY_TOTAL_LOAD에서 씀 - condition_score.dart의 동명 헬퍼와 동일 형식.
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
