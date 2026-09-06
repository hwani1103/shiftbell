// lib/services/condition/sleep_condition_extras.dart
//
// ⭐ 2026-09-01 - "실제 수면 기록이 있으면 오늘의 컨디션 안내문구를 그걸로
// 다듬어달라"는 요청으로 추가. ConditionRuleEngine(B번)은 이 파일을 전혀
// 모르고, 이 파일도 ConditionRuleEngine을 import하지 않는다 - 판정
// (ConditionLevel)에는 절대 영향을 주지 않고, 이미 계산된 결과 위에 실제
// 수면 데이터 기반 "보조 설명" 한 줄만 추가로 만드는 순수 함수다
// (수면기록_자동추정_설계.md 5장 "Sleep Detection과 Shift Health Engine
// 완전 분리" 원칙 그대로 유지).
//
// 기준 수치(7~9시간)는 ConditionRuleEngine의 RULE_SLEEP_WINDOW와 완전히 같은
// EVIDENCE-011을 그대로 재사용한다 - 같은 주장에 다른 숫자를 쓰지 않기 위함.

class ActualSleepFinding {
  final String message;
  final bool isShort; // 권장 최소치보다 부족했는지 - 화면에서 강조 색을 다르게 쓸 때 사용
  const ActualSleepFinding({required this.message, required this.isShort});
}

const int kRecommendedSleepMinMinutes = 7 * 60; // EVIDENCE-011
const int kRecommendedSleepMaxMinutes = 9 * 60; // EVIDENCE-011

/// [actualMinutes](오늘의 회복구간과 겹치는, 확정된 실제 수면 시간)을 권장
/// 범위(7~9시간)와 비교해 보조 설명 한 줄을 만든다.
ActualSleepFinding buildActualSleepFinding(int actualMinutes) {
  final h = actualMinutes ~/ 60;
  final m = actualMinutes % 60;
  final durationText = m == 0 ? '$h시간' : '$h시간 $m분';

  if (actualMinutes < kRecommendedSleepMinMinutes) {
    return ActualSleepFinding(
      message: '실제 수면 시간이 $durationText로 권장 범위(7~9시간)보다 부족했어요. '
          '오늘 컨디션에 영향이 있을 수 있으니 평소보다 일찍 잠자리에 들어보세요.',
      isShort: true,
    );
  }
  return ActualSleepFinding(
    message: '실제 수면 시간이 $durationText로 충분했어요.',
    isShort: false,
  );
}
