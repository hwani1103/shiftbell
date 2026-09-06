// lib/services/condition/shift_time_category.dart
//
// ⭐ 근무명 "텍스트"가 아니라 시작 시각만으로 주간/오후/야간을 분류하는
// 휴리스틱. 근무명은 사용자가 자유롭게 짓기 때문에("A조", "1번" 등) 이름으로는
// 분류할 수 없어서, 오직 시작 시각 구간으로만 판단한다.
//
// ⚠️ 이건 과학적 근거가 필요한 "판정"이 아니라 순수한 앱 내부 분류 규칙
// (라벨링용)이다 - 컨디션매니저_근거자료.md의 Evidence와는 무관하고, 위험도를
// 매기지 않는다. 자세한 구간 근거(=근거 없음, 앱 내부 관례)는
// 컨디션매니저_설계.md 4장 참고.
enum ShiftTimeCategory {
  day, // 05:00~10:59 시작
  evening, // 11:00~16:59 시작
  night, // 17:00~04:59 시작 (자정을 넘겨도 포함)
  off, // 휴무
  unspecified, // 근무는 있으나 출퇴근 시각 미입력
}

ShiftTimeCategory classifyByStartMinutes(int startMinutes) {
  final h = (startMinutes ~/ 60) % 24;
  if (h >= 5 && h < 11) return ShiftTimeCategory.day;
  if (h >= 11 && h < 17) return ShiftTimeCategory.evening;
  return ShiftTimeCategory.night;
}

extension ShiftTimeCategoryLabel on ShiftTimeCategory {
  String get label {
    switch (this) {
      case ShiftTimeCategory.day:
        return '주간';
      case ShiftTimeCategory.evening:
        return '오후';
      case ShiftTimeCategory.night:
        return '야간';
      case ShiftTimeCategory.off:
        return '휴무';
      case ShiftTimeCategory.unspecified:
        return '시각 미입력';
    }
  }
}
