// lib/services/condition/condition_score.dart
//
// ⭐ 2026-09-01 후속10 - "오늘의 컨디션 점수"(0~100). condition_rule_engine.dart/
// today_forecast_engine.dart 상단에 반복 명시돼 있던 "숫자 점수 절대 금지"
// 원칙을, 사용자가 이 축에 한해 명시적으로 요청해서 의도적으로 뒤집음 -
// "가중치는 내가 직접 조정하고, 근거는 나중에 별도로 설명할 계획"이라고
// 스스로 밝힘. 기존 3단계(NORMAL/ATTENTION/HIGH_LOAD) 판정과 "오늘의 컨디션"
// 문구 레이어(today_forecast_engine.dart)는 이 파일이 전혀 안 건드리고 읽기만
// 함 - 이 점수는 완전히 새로운 추가 레이어. 근거 없는 진단·질병 위험도로
// 오인되지 않도록 "점수"라는 표현 자체는 계속 쓰되, %/의학적 확신을 암시하는
// 문구는 UI 쪽에서 절대 안 씀(단순 상대적 지표라는 톤 유지).
//
// ⚠️ 아래 가중치는 전부 1차 설계값(사용자가 나중에 직접 재조정할 걸 전제).
// 일부(장시간 근무/수면 축)는 evidence_database.dart 수치를 참고해 대략
// 정했지만, 정밀 최적화는 안 됨 - 가중치 상수를 한 곳(_w* 그룹)에 모아서
// 나중에 쉽게 바꿀 수 있게 함.

import 'condition_rule_engine.dart';
import 'shift_pattern_analyzer.dart';
import 'shift_time_category.dart';

// ═══════════════════════════════════════════════════════════════════════
// 가중치(감점량) - 전부 100점 만점에서 빼는 방식. 여러 개 겹치면 전부 누적.
// ═══════════════════════════════════════════════════════════════════════

const int _wRecoveryMax = 20; // 회복시간(11시간 미만, EVIDENCE-002/003) - 부족할수록 비례 감점
const int _wLongShift = 10; // 오늘 근무 12시간 이상(EVIDENCE-004, Folkard&Lombardi 상대위험 +27%)
const int _wExtendedStreak = 15; // 장시간근무 연속+짧은 회복(RULE_EXTENDED_STREAK_SHORT_BREAK, EVIDENCE-004+005)
const int _wNightFrequency = 8; // 최근 5일 중 3일 이상 야간
const int _wWorkStreak = 8; // 연속 근무일 5일 이상
const int _wHeavyOt = 6; // 최근 5일 누적 초과근무 8시간 이상(EVIDENCE-012)
const int _wBackwardDirection = 5; // 역방향 교대(EVIDENCE-001 - 정방향이 상대적으로 유리하다고 보고됨)
// ⭐ 2026-09-04 - 연속 야간근무(EVIDENCE-013, Folkard & Tucker 2003) - 3일째부터,
// 4일 이상(원 연구가 "가속화"라고 명시하는 구간)이면 추가로 더 깎음. _wNightFrequency
// (최근 7일 중 야간 횟수, 느슨한 신호)와는 별개 축 - 이쪽은 "끊기지 않고 연속"인지만 봄.
const int _wConsecutiveNightStreak = 10;
const int _wConsecutiveNightStreakSevere = 10; // 4일 이상일 때 위에 추가로 더
const int _wSleepMax = 20; // 수면 부족(7시간 미만, EVIDENCE-011 권장 최소) - 부족할수록 비례 감점
const int _wShiftWorkNightEvening = 15; // 오늘이 오후/야간 근무 자체인 기본 부담(설계값 - 특정 evidence 아님)
const int _wShiftWorkRotatingDay = 8; // 오늘은 주간이지만 스케줄 자체가 로테이션이라 생기는 기본 부담(설계값)
// ⭐ 2026-09-01 후속12(사용자 요청) - "컨디션이 너무 쉽게 100점이 나온다"는
// 지적의 실제 원인: 최근 수면 데이터가 아예 없어도(avgRecentSleepMinutes==null)
// 그 사실 자체는 어떤 factor에서도 감점되지 않았음 - "확인해보니 좋다"와
// "몰라서 못 깎았다"가 점수상 구분이 안 됐던 것. 최근 [_kScoreWindowDays]일 중
// 실제 수면 기록이 있는 비율이 낮을수록 이 감점이 커진다 - 데이터가 완전할
// 때(비율 1.0)만 0.
const int _wDataIncompleteMax = 6;

const int _kRecoveryThresholdMinutes = 11 * 60;
// ⭐ 2026-09-05 - _kLongShiftThresholdMinutes(12*60)는 삭제함 - 장시간근무
// 임계값은 이제 ConditionRuleEngine의 RULE_LONG_SHIFT 판정을 그대로 읽으므로
// (위 factor 2 참고) 여기서 또 정의할 필요가 없어짐(중복 정의가 바로 이번
// 버그의 원인이었음 - 재발 방지).
const int _kSleepThresholdMinutes = 7 * 60; // EVIDENCE-011과 동일 기준(today_forecast_engine.dart _kSufficientMinutes와 통일)
// ⭐ 2026-09-01 후속21(사용자 요청) - "최근"의 정의를 5일 → 7일로 넓힘.
// today_forecast_engine.dart의 _kFatigueWindowDays와 항상 같은 값을 유지할 것 -
// 워딩(그쪽)과 점수(여기)가 서로 다른 기간을 "최근"이라고 부르면 둘이
// 어긋나 보임. 야간 "잦다" 판정 기준(3)은 창을 넓혀도 절대값 그대로 유지
// (그쪽과 동일 - 비율로 환산해 올리면 "3일 연속 야간" 같은 명백한 신호를
// 놓치는 회귀가 있었음, today_forecast_engine.dart 주석 참고).
const int _kScoreWindowDays = 7; // 축4(최근 7일 실측 피로도)와 동일 창
const int _kManyNightsThreshold = 3; // 7일 중 3일 이상 야간이면 "잦다" - 절대 기준(today_forecast_engine.dart와 동일)
// ⭐ "연속 근무가 길다"는 절대 기준 - 위 window와 분리(같은 이유로
// today_forecast_engine.dart의 _kWorkStreakThresholdDays와 동일하게 유지).
const int _kWorkStreakThresholdDays = 5;

// ⭐ 2026-09-01 후속11(사용자 요청) - "아무리 나빠도 최악이 40~50점 선"이 되게
// 조정. 개별 가중치를 전부 낮추는 대신(그러면 보통날/나쁜날 차이가 뭉개짐),
// "문제 축"(회복/장시간/연속스트릭/연속야간/야간빈도/연속근무/OT/역방향/수면)의
// 합계에만 상한을 씌움 - 요인 한두 개짜리 보통 수준 나쁜 날은 상한 밑이라
// 그대로 세밀하게 감점되고, 여러 개가 한꺼번에 겹치는 극단적인 날만 이
// 상한에서 걸려 수렴함(위 개별 가중치 합계가 92라 만약 상한이 없었다면
// 최악 케이스가 한 자릿수까지 떨어졌었음 - 1차 버전 실측).
// "교대근무 자체" 기본 부담(_wShiftWork*)은 상한과 별개로 항상 그대로 적용.
// ⭐ 후속12 - "최악이 38점 선"으로 요청 재조정(기존 45→47, 야간/오후 기본부담
// 15와 합쳐 100-47-15=38). 45일 때는 40이 바닥이었음.
const int _kMaxProblemDeduction = 47;

enum ConditionScoreTier { excellent, veryGood, good, fair, attention, poor, veryPoor, severe }

class ConditionScoreTierInfo {
  final ConditionScoreTier tier;
  final String emoji;
  final String label;
  const ConditionScoreTierInfo(this.tier, this.emoji, this.label);
}

/// ⭐ "연결성 있는" 아이콘 세트 요청 - 표정이 점점 굳어가는 하나의 계열로
/// 통일(excellent만 예외적으로 별표 - "만점"이라는 특별함을 표시). 8단계로
/// 나눔(사용자가 말한 "5점 단위"는 카드에 항상 같이 보이는 정확한 숫자로
/// 충족하고, 아이콘 자체는 20개를 억지로 구분하기보다 한눈에 읽히는 8단계로
/// 묶음 - 이 부분은 임의 조정임을 명시).
const List<ConditionScoreTierInfo> kConditionScoreTiers = [
  ConditionScoreTierInfo(ConditionScoreTier.excellent, '🌟', '최상'),
  ConditionScoreTierInfo(ConditionScoreTier.veryGood, '😄', '좋음'),
  ConditionScoreTierInfo(ConditionScoreTier.good, '🙂', '양호'),
  ConditionScoreTierInfo(ConditionScoreTier.fair, '😌', '보통'),
  ConditionScoreTierInfo(ConditionScoreTier.attention, '😐', '주의'),
  ConditionScoreTierInfo(ConditionScoreTier.poor, '😕', '부담'),
  ConditionScoreTierInfo(ConditionScoreTier.veryPoor, '😣', '과부하'),
  ConditionScoreTierInfo(ConditionScoreTier.severe, '😫', '심각'),
];

// ⭐ 후속11 - 문제축 상한(_kMaxProblemDeduction) 도입으로 점수 실분포가
// 대략 40~100 사이로 좁혀져서, 예전 경계(95/85/75/65/50/35/20 - 0~34는
// 사실상 도달 불가능해짐)를 이 범위에 맞게 다시 등분함.
ConditionScoreTierInfo conditionScoreTierFor(int score) {
  if (score >= 95) return kConditionScoreTiers[0];
  if (score >= 88) return kConditionScoreTiers[1];
  if (score >= 80) return kConditionScoreTiers[2];
  if (score >= 72) return kConditionScoreTiers[3];
  if (score >= 64) return kConditionScoreTiers[4];
  if (score >= 56) return kConditionScoreTiers[5];
  if (score >= 48) return kConditionScoreTiers[6];
  return kConditionScoreTiers[7];
}

class ConditionScoreFactor {
  final String label;
  final int deduction; // 양수(감점량)
  const ConditionScoreFactor(this.label, this.deduction);
}

class ConditionScoreResult {
  final int score; // 0~100
  final List<ConditionScoreFactor> factors; // 실제로 감점된 항목만(원인순)
  const ConditionScoreResult(this.score, this.factors);
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [avgRecentSleepMinutes]는 오늘까지 최근 7일(_kScoreWindowDays) 내 실제 수면
/// 평균(분) - 데이터가
/// 없으면 null. ⚠️ "수면이 나쁘다고 단정"하는 감점은 여전히 안 함(그 원칙은
/// 그대로 유지) - 다만 [recentSleepTrackedDays]/[recentSleepDaysWithData]로
/// "그 판단을 내릴 수 있을 만큼 데이터가 있는가"는 별도로 감점한다(아래
/// _wDataIncompleteMax 참고 - "몰라서 안 깎인 것"과 "확인해보니 좋아서 안 깎인
/// 것"을 구분하기 위함). [isRotatingSchedule]은 근무명이 2종류 이상 섞여 도는
/// 스케줄인지(주간 고정 근무자는 false).
ConditionScoreResult computeConditionScore({
  required ConditionResult baseResult,
  required ShiftPatternAnalyzer analyzer,
  required DateTime today,
  required Map<String, int> otMinutesByDate,
  double? avgRecentSleepMinutes,
  required bool isRotatingSchedule,
  int recentSleepTrackedDays = 0,
  int recentSleepDaysWithData = 0,
}) {
  // ⭐ "문제 축"(1~7번)과 "교대근무 자체 기본 부담"(8번)을 분리해서 모은다 -
  // 전자의 합계에만 상한(_kMaxProblemDeduction)을 씌우기 위함(위 상수 설명
  // 참고). factors 리스트에는 실제 개별 감점량을 그대로 남겨서(캡 적용 전
  // 값) 어떤 요인이 얼마나 기여했는지 투명하게 보이게 함.
  final problemFactors = <ConditionScoreFactor>[];
  void deductProblem(String label, int amount) {
    if (amount <= 0) return;
    problemFactors.add(ConditionScoreFactor(label, amount));
  }

  final baselineFactors = <ConditionScoreFactor>[];
  void deductBaseline(String label, int amount) {
    if (amount <= 0) return;
    baselineFactors.add(ConditionScoreFactor(label, amount));
  }

  final todayInstance = baseResult.today;

  // 1. 회복시간(EVIDENCE-002/003)
  final recovery = baseResult.recoveryMinutes;
  if (recovery != null && recovery < _kRecoveryThresholdMinutes) {
    final shortfall = (_kRecoveryThresholdMinutes - recovery).clamp(0, _kRecoveryThresholdMinutes);
    deductProblem('회복시간 부족', (shortfall / _kRecoveryThresholdMinutes * _wRecoveryMax).round());
  }

  // 2. 장시간근무 12시간 이상(EVIDENCE-004) - ConditionRuleEngine이 이미 판정한
  // 결과(RULE_LONG_SHIFT)를 그대로 읽음(3번 항목과 동일 패턴으로 통일).
  // ⭐ 2026-09-05 - CRITICAL FIX: 예전엔 `todayInstance.isWorkDay &&
  // durationMinutes >= 12h`로 "오늘 자체가 근무일일 때만" 따로 재계산했는데,
  // 그러면 "어제 12시간 야간근무하고 오늘은 쉬는 날"처럼 오늘이 근무일이
  // 아닌데 직전 근무의 영향이 아직 유효한 경우를 놓침 - RULE_LONG_SHIFT는
  // 오늘이 근무일이 아니어도 회복구간을 만든 직전 근무가 12시간 이상이면
  // 이미 정확히 잡아주는데, 여기만 그 결과를 재사용 안 하고 있었음(실기기
  // DB로 재현·확인: 야간근무 12시간 직후의 휴무일에 이 -10점이 통째로
  // 빠져서 점수가 부풀려짐). 1번(회복시간)/3번(연속+짧은회복) 항목은 이미
  // baseResult 기반이라 오늘이 쉬는 날이어도 정상 반영되고 있었음 - 이
  // 항목만 그 패턴에서 벗어나 있던 것.
  if (baseResult.levelFindings.any((f) => f.ruleId == 'RULE_LONG_SHIFT')) {
    deductProblem('장시간 근무(12시간 이상)', _wLongShift);
  }

  // 3. 장시간근무 연속 + 짧은 회복(EVIDENCE-004+005) - ConditionRuleEngine이
  // 이미 판정한 결과를 그대로 읽음(임계값 중복 정의 안 함).
  if (baseResult.levelFindings.any((f) => f.ruleId == 'RULE_EXTENDED_STREAK_SHORT_BREAK')) {
    deductProblem('장시간 근무 연속 + 짧은 회복', _wExtendedStreak);
  }

  // 3-2. 연속 야간근무(EVIDENCE-013) - 마찬가지로 ConditionRuleEngine의
  // RULE_CONSECUTIVE_NIGHT_SHIFTS 판정을 그대로 읽음(3일 이상 기준을 여기서
  // 또 정의하지 않음). 4일 이상(원 연구가 명시하는 가속화 구간)이면 추가 감점.
  if (baseResult.levelFindings.any((f) => f.ruleId == 'RULE_CONSECUTIVE_NIGHT_SHIFTS')) {
    deductProblem('연속 야간근무', _wConsecutiveNightStreak);
    if ((baseResult.consecutiveNightDays ?? 0) >= 4) {
      deductProblem('연속 야간근무 가속화(4일 이상)', _wConsecutiveNightStreakSevere);
    }
  }

  // 4. 최근 7일(오늘 포함) 중 야간근무 빈도 / 5. 연속 근무일수 / OT 누적 -
  // today_forecast_engine.dart 축4와 동일한 7일 창을 재계산(그쪽은 private라
  // 재사용 불가 - 같은 임계값을 여기서도 그대로 씀).
  var nightCount = 0;
  var otTotal = 0;
  for (var i = 0; i < _kScoreWindowDays; i++) {
    final day = today.subtract(Duration(days: i));
    if (analyzer.instanceForDate(day).category == ShiftTimeCategory.night) nightCount++;
    otTotal += otMinutesByDate[_dateKey(day)] ?? 0;
  }
  if (nightCount >= _kManyNightsThreshold) deductProblem('최근 야간근무 잦음', _wNightFrequency);

  final consecutiveWorkDays = baseResult.consecutiveWorkDays;
  if (consecutiveWorkDays != null && consecutiveWorkDays >= _kWorkStreakThresholdDays) {
    deductProblem('연속 근무일 김', _wWorkStreak);
  }

  if (otTotal >= 8 * 60) deductProblem('초과근무 누적', _wHeavyOt);

  // 6. 교대 방향(EVIDENCE-001) - 판단 불가능한 스케줄(2교대 등)이면 건드리지 않음.
  final direction = analyzer.analyzeDirection();
  if (direction != null && direction.direction == ShiftDirection.backward) {
    deductProblem('역방향 교대', _wBackwardDirection);
  }

  // 7. 수면 부족(EVIDENCE-011, 권장 최소 7시간 - today_forecast_engine.dart와 동일 기준)
  if (avgRecentSleepMinutes != null && avgRecentSleepMinutes < _kSleepThresholdMinutes) {
    final shortfall = (_kSleepThresholdMinutes - avgRecentSleepMinutes).clamp(0, _kSleepThresholdMinutes.toDouble());
    deductProblem('수면 부족', (shortfall / _kSleepThresholdMinutes * _wSleepMax).round());
  }

  // 8. "교대근무 자체"의 기본 부담(설계값 - 특정 논문 수치 아님, 오늘이
  // 근무일일 때만 적용, 휴무일엔 0). 오후/야간 근무는 그 자체로 생체리듬
  // 부담이 크다고 보고 더 크게, 주간 근무라도 스케줄이 로테이션이면 패턴
  // 변화 자체의 부담을 작게 반영. ⭐ 상한(_kMaxProblemDeduction) 적용 대상이
  // 아님 - 위 "문제 축"과 별개로 항상 그대로 뺀다.
  if (todayInstance.isWorkDay) {
    if (todayInstance.category == ShiftTimeCategory.night || todayInstance.category == ShiftTimeCategory.evening) {
      deductBaseline('교대근무 기본 부담(오후/야간)', _wShiftWorkNightEvening);
    } else if (isRotatingSchedule) {
      deductBaseline('교대근무 기본 부담(로테이션)', _wShiftWorkRotatingDay);
    }
  }

  // 9. 수면 데이터 완전성(후속12, 사용자 요청) - "너무 쉽게 100점" 문제의
  // 실제 원인이 여기 있었음: 수면 기록이 아예 없어도 위 7번(수면 부족)이 그냥
  // 통과돼서(avgRecentSleepMinutes==null) 어떤 감점도 안 걸렸음 - "몰라서 안
  // 깎은 것"과 "확인해보니 좋아서 안 깎은 것"이 점수상 구분이 안 됐던 것.
  // 최근 [_kScoreWindowDays]일 중 실제 수면 기록이 있는 비율이 낮을수록 비례
  // 감점 - 이 비율이 1.0(완전)일 때만 0. recentSleepTrackedDays가 0이면(호출부가
  // 이 정보를 안 넘긴 경우 - 기존 테스트 등) 판단 근거 자체가 없으므로 이
  // 축은 건드리지 않음(기존 동작 그대로 유지).
  if (recentSleepTrackedDays > 0) {
    final ratio = (recentSleepDaysWithData / recentSleepTrackedDays).clamp(0.0, 1.0);
    if (ratio < 1.0) {
      deductBaseline('수면 기록 불완전', ((1.0 - ratio) * _wDataIncompleteMax).round());
    }
  }

  final rawProblemTotal = problemFactors.fold<int>(0, (sum, f) => sum + f.deduction);
  final cappedProblemTotal = rawProblemTotal > _kMaxProblemDeduction ? _kMaxProblemDeduction : rawProblemTotal;
  final baselineTotal = baselineFactors.fold<int>(0, (sum, f) => sum + f.deduction);

  final factors = <ConditionScoreFactor>[...problemFactors, ...baselineFactors];
  if (rawProblemTotal > _kMaxProblemDeduction) {
    // ⭐ 상한이 실제로 적용된 경우 투명하게 표시(디버그/실험실 화면에서 보임) -
    // 개별 factor 값은 원래 그대로 두고, 상한으로 얼마나 "구제"됐는지만 별도 표기.
    factors.add(ConditionScoreFactor(
      '(문제 요인 상한 적용: 원래 합계 $rawProblemTotal → $_kMaxProblemDeduction으로 캡)',
      0,
    ));
  }

  // ⭐ 후속12 - 만점을 100 대신 98로 하드 캡(사용자 요청 - "그때부터 97 96
  // 95 다 나올 수 있게"). 위 9번(수면 데이터 완전성) 감점이 실질적으로도
  // "완전한 데이터 + 좋은 조건"에서만 98 근처에 닿게 만들지만, 그 감점 축을
  // 호출부가 안 넘긴 극단적인 경우(recentSleepTrackedDays==0)에도 100이
  // 다시 나오지 않도록 여기서 한 번 더 확실히 막아둠.
  final score = (100 - cappedProblemTotal - baselineTotal).clamp(0, 98);
  return ConditionScoreResult(score, factors);
}
