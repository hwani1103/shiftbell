// lib/utils/shift_name_util.dart
//
// ⭐ 영어 현지화 작업 중 도입 - "휴무" 근무명 감지 로직을 한 곳으로 모음.
// 예전엔 calendar_theme.dart와 onboarding_screen.dart 두 곳에 각각
// `shift.contains('휴')`로 하드코딩되어 있었는데, 영어권 사용자가 근무명을
// "Off"/"Day Off"/"Rest" 등으로 입력하면 이 조건에 안 걸려서 휴무 고정
// 빨강색이 적용되지 않는 문제가 생김. 완벽한 해결은 아님(사용자가 전혀 다른
// 단어로 근무명을 지으면 여전히 못 잡음 - 한국어도 원래 같은 한계가 있었음)이지만,
// 흔히 쓰이는 표현들은 커버함. (교대시계_영어화_현지화_보고서_영문판.md 참고)
bool isRestShiftName(String name) {
  if (name.contains('휴')) return true;
  final lower = name.toLowerCase();
  return lower.contains('off') || lower.contains('rest') || lower.contains('holiday');
}
