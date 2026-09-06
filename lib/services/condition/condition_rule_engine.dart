// lib/services/condition/condition_rule_engine.dart
//
// ⭐ 컨디션 매니저 Phase 2~3 - Evidence 기반 Rule Engine + 수면 추천.
// shift_pattern_analyzer.dart가 계산한 "사실"에 이름 붙은 rule을 적용해서
// ConditionLevel(NORMAL/ATTENTION/HIGH_LOAD)과 Finding/Tip을 만든다.
//
// ⚠️ 지켜야 할 원칙(컨디션매니저_설계.md 5장 → 2026-09-04 v2로 개정,
// 컨디션매니저_근거자료.md 결론):
//  1. ConditionLevel을 올리는 조건은 evidence_database.dart에 실제로 대응
//     항목이 있는 신호만 쓴다 - "여기 없는 근거는 어떤 Rule에도 안 쓴다"는
//     원칙 자체는 그대로 유지. 다만 2026-09-04에 "앱이 이미 계산 가능한
//     evidence 신호는 빠짐없이 판정에 활용해달라"는 요청으로 대상을 6개로
//     넓힘(v1의 회복시간/장시간근무/장시간연속에 주간 초과근무·역방향 교대를
//     추가) - 아래 5장 표 참고. 반대로 대응 evidence가 없는 순수 계산값
//     (연속 야간근무 일수 자체, 연속근무일수)은 여전히 판정에 안 쓴다 -
//     워딩(설명 문구)에만 활용.
//  2. 모든 Finding/Tip은 evidenceIds를 최소 1개 가져야 한다.
//  3. 숫자 점수(0~100)나 %, 질병 위험도는 condition_score.dart(사용자 요청으로
//     승인된 예외, CLAUDE.md 참고) 외에는 어디에도 만들지 않는다.

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
  });
}

class ConditionRuleEngine {
  static const _minRecoveryMinutes = 11 * 60; // EVIDENCE-002, EVIDENCE-003
  static const _longShiftThresholdMinutes = 12 * 60; // EVIDENCE-004
  static const _extendedStreakDays = 3; // EVIDENCE-005 원문 숫자
  static const _extendedStreakRequiredBreakMinutes = 48 * 60; // EVIDENCE-005 원문 숫자("2일")
  static const _recommendedSleepMinMinutes = 7 * 60; // EVIDENCE-011
  static const _recommendedSleepMaxMinutes = 9 * 60; // EVIDENCE-011
  static const _sleepBufferMinutes = 60; // ⚠️ 연구값 아님 - 이동/정리 여유(설계 문서 6장 명시)
  static const _caffeineCutoffHoursBeforeSleep = 6; // EVIDENCE-008
  // ⭐ 2026-09-04 v2 추가 - condition_score.dart/today_forecast_engine.dart가
  // 이미 쓰던 것과 동일한 값(최근 7일 중 누적 8시간 이상 = "유의미한 초과근무",
  // EVIDENCE-012). 세 파일에 각각 정의돼 있어 값 하나 바뀌면 서로 어긋날 수
  // 있음 - 바꿀 땐 반드시 세 곳 다 같이 맞출 것(Dart↔Kotlin 상수 동기화와
  // 같은 이유의 위험).
  static const _overtimeLookbackDays = 7;
  static const _heavyOvertimeThresholdMinutes = 8 * 60;

  final ShiftPatternAnalyzer analyzer;

  const ConditionRuleEngine(this.analyzer);

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
      );
    }

    final levelFindings = <ConditionFinding>[];
    final contextFindings = <ConditionFinding>[];
    final tips = <ConditionTip>[];

    // ── 회복구간(가장 최근 근무 종료 ~ 다음 근무 시작) 계산 ──────────────
    final window = analyzer.recoveryWindowContaining(date);
    final recoveryMinutes = window?.start.difference(window.end).inMinutes;

    final shortRecovery = recoveryMinutes != null && recoveryMinutes < _minRecoveryMinutes;
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
    final longShift = relevantShiftMinutes != null && relevantShiftMinutes >= _longShiftThresholdMinutes;

    // ⭐ 2026-09-04 v2 - 주간 초과근무(EVIDENCE-012, EU 근로시간지침 48h 기준을
    // condition_score.dart/today_forecast_engine.dart와 동일하게 "최근 7일
    // 누적 8시간 이상"으로 적용). 원래 이 신호는 today_forecast_engine.dart
    // (문구 레이어)에서만 읽었는데(그때는 ConditionRuleEngine을 "0줄 수정"하는게
    // 원칙이었음 - 컨디션매니저_설계.md 14장 참고), 이번엔 사용자가 명시적으로
    // 판정 자체에 반영해달라고 요청해서 그 원칙을 의도적으로 갱신함.
    var otTotalMinutes = 0;
    for (var i = 0; i < _overtimeLookbackDays; i++) {
      otTotalMinutes += otMinutesByDate[_dateKey(date.subtract(Duration(days: i)))] ?? 0;
    }
    final heavyOvertime = otTotalMinutes >= _heavyOvertimeThresholdMinutes;

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
    final nightStreakAttention = consecutiveNight >= 3;
    final nightStreakSevere = consecutiveNight >= 4;

    // ⭐ 2026-09-04 v2 - ATTENTION급 개별 신호 5개(회복시간 부족/장시간근무/
    // 주간 초과근무/역방향 교대/연속 야간근무 3일 이상)를 한데 모아 "몇 개나
    // 겹치는지"로 최종 레벨을 정함: 1개면 ATTENTION, 2개 이상이면 HIGH_LOAD.
    // "2개 이상이면 심각"이라는 조합 기준 자체는 특정 논문 수치가 아니라 이 앱의
    // 설계 판단(여러 연구가 개별적으로 뒷받침하는 부담이 겹치면 누적된다는
    // 상식적 추론) - 문구에도 그 점을 명시함. 각 신호 자체의 evidenceIds는 개별
    // Finding에 그대로 남아 있어 "무엇이 왜"는 항상 추적 가능함.
    final attentionSignalIds = <String>[
      if (shortRecovery) 'RULE_SHORT_RECOVERY',
      if (longShift) 'RULE_LONG_SHIFT',
      if (heavyOvertime) 'RULE_WEEKLY_OVERTIME',
      if (isBackward) 'RULE_BACKWARD_DIRECTION',
      if (nightStreakAttention) 'RULE_CONSECUTIVE_NIGHT_SHIFTS',
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
    if (longShift) {
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_LONG_SHIFT',
        message: '${_formatHours(relevantShiftMinutes)} 근무입니다. 관련 연구에서는 '
            '근무시간이 길어질수록 피로·사고 위험이 상대적으로 높아지는 경향이 '
            '보고됩니다.',
        evidenceIds: const ['EVIDENCE-004'],
      ));
    }
    if (heavyOvertime) {
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_WEEKLY_OVERTIME',
        message: '최근 7일간 초과근무가 ${_formatHours(otTotalMinutes)} 누적됐습니다. '
            'EU 근로시간지침 등은 평균 주간 근무시간이 48시간을 넘지 않을 것을 '
            '기준으로 제시합니다.',
        evidenceIds: const ['EVIDENCE-012'],
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
        message: nightStreakSevere
            ? '연속 야간근무가 $consecutiveNight일째로 접어들었습니다. 관련 연구는 '
                '이 시점부터 사고·실수 위험이 뚜렷하게 가속화된다고 보고하며, 일부 '
                '안전 최우선 산업의 근무 규정은 연속 야간근무를 보통 4일로 상한선을 '
                '둡니다.'
            : '연속 야간근무 $consecutiveNight일째입니다. 관련 연구는 야간근무가 '
                '연속될수록(특히 낮·오후근무 연속보다 더 가파르게) 사고·실수 위험이 '
                '누적된다고 보고합니다.',
        evidenceIds: const ['EVIDENCE-013'],
      ));
    }

    if (attentionSignalIds.length >= 2) {
      level = ConditionLevel.highLoad;
      final compoundLabels = [
        if (shortRecovery) '회복시간 부족',
        if (longShift) '장시간 근무',
        if (heavyOvertime) '초과근무 누적',
        if (isBackward) '역방향 교대 전환',
        if (nightStreakAttention) '연속 야간근무',
      ];
      final compoundEvidenceIds = <String>{
        if (shortRecovery) ...['EVIDENCE-002', 'EVIDENCE-003'],
        if (longShift) 'EVIDENCE-004',
        if (heavyOvertime) 'EVIDENCE-012',
        if (isBackward) 'EVIDENCE-001',
        if (nightStreakAttention) 'EVIDENCE-013',
      };
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_COMPOUND_HIGH_LOAD',
        message: '${compoundLabels.join(' + ')}이 오늘 함께 겹쳐 회복 부담이 큰 '
            '날로 판단됩니다. (여러 부담이 겹치면 누적된다고 보는 것은 이 앱의 '
            '판단이며, 개별 요인 각각의 근거는 위 항목을 참고하세요.)',
        evidenceIds: compoundEvidenceIds.toList(),
      ));
    }

    // 연속 장시간근무 + 짧은 다음 회복 (EVIDENCE-004 + EVIDENCE-005) - 근거가
    // 강해(원문이 제시하는 정량적 권고) 위 조합 규칙과 무관하게 그 자체로도
    // 단독 HIGH_LOAD.
    final longShiftStreakDate = window != null
        ? _findInstanceDateByEnd(date, window.end) ?? date
        : date;
    final longStreak = analyzer.consecutiveLongShiftStreakEndingAt(
      longShiftStreakDate,
      thresholdMinutes: _longShiftThresholdMinutes,
    );
    if (longStreak >= _extendedStreakDays &&
        (recoveryMinutes == null || recoveryMinutes < _extendedStreakRequiredBreakMinutes)) {
      levelFindings.add(ConditionFinding(
        ruleId: 'RULE_EXTENDED_STREAK_SHORT_BREAK',
        message: '12시간 이상 근무가 $longStreak일 연속 이어졌습니다. 관련 훈련자료는 '
            '이런 경우 최소 2일의 휴식을 고려할 것을 제안합니다.',
        evidenceIds: const ['EVIDENCE-004', 'EVIDENCE-005'],
      ));
      level = ConditionLevel.highLoad;
    }

    // ⭐ 2026-09-04 v2 후속 - 연속 야간근무 4일 이상은 그 자체로 단독 HIGH_LOAD
    // (원 연구가 "이 시점부터 가속화"라고 명시하는 구간 - 위 RULE_EXTENDED_
    // STREAK_SHORT_BREAK와 동일한 취급).
    if (nightStreakSevere) {
      level = ConditionLevel.highLoad;
    }

    // ── 설명용 맥락(판정에는 영향 없음) ──────────────────────────────
    final consecutiveWork = today.isWorkDay ? analyzer.consecutiveWorkStreakEndingAt(date) : 0;

    if (consecutiveNight >= 1 && !nightStreakAttention) {
      // 3일 미만은 여전히 순수 계산값(대응 evidence 없음)이라 판정에도 안 쓰고
      // 사실만 서술 - 3일 이상은 이제 위에서 RULE_CONSECUTIVE_NIGHT_SHIFTS로
      // 이미 다뤘으니 여기서 중복 표시 안 함.
      contextFindings.add(ConditionFinding(
        message: '오늘로 연속 야간근무 $consecutiveNight일째입니다.',
        evidenceIds: const [],
      ));
    }
    if (today.isOff && consecutiveNight == 0) {
      final ySt = analyzer.consecutiveNightStreakEndingAt(date.subtract(const Duration(days: 1)));
      if (ySt >= 1) {
        contextFindings.add(ConditionFinding(
          ruleId: 'RULE_NIGHT_FOLLOWED_BY_OFF',
          message: '어제까지 이어진 야간근무($ySt일) 이후의 휴무입니다. 회복을 위한 '
              '수면·휴식 구간으로 활용해보세요.',
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
      final sleepStart = window.end.add(const Duration(minutes: _sleepBufferMinutes));
      final maxBySleepLength = sleepStart.add(const Duration(minutes: _recommendedSleepMaxMinutes));
      final maxByNextShift = window.start.subtract(const Duration(minutes: _sleepBufferMinutes));
      final sleepEnd = maxBySleepLength.isBefore(maxByNextShift) ? maxBySleepLength : maxByNextShift;

      if (sleepEnd.isAfter(sleepStart)) {
        sleepWindow = DateTimeRange(start: sleepStart, end: sleepEnd);
        final actualMinutes = sleepEnd.difference(sleepStart).inMinutes;
        sleepShorterThanRecommended = actualMinutes < _recommendedSleepMinMinutes;

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

        final cutoff = sleepStart.subtract(const Duration(hours: _caffeineCutoffHoursBeforeSleep));
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
      consecutiveNightDays: consecutiveNight,
      consecutiveWorkDays: consecutiveWork,
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

  // RULE_WEEKLY_OVERTIME에서 씀 - condition_score.dart의 동명 헬퍼와 동일 형식.
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
