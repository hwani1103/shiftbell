// lib/models/shift_time_range.dart
//
// ⭐ 컨디션 매니저 전용(컨디션매니저_설계.md 참고) - 근무명별 "실제 출퇴근
// 시각"(자정 기준 분)을 담는 모델. 기존 ShiftSchedule.shiftDurations(설정 탭의
// "근로시간 및 OT 설정"에서 쓰는 분 단위 근로시간)와는 완전히 별개 데이터임 -
// 그건 "하루 몇 시간 근무"만 알고 정확한 출퇴근 시각(자정 넘김 포함)은 모름.
// 컨디션 매니저는 근무 사이 회복시간·추천 수면 시간대 계산을 위해 시각 자체가
// 필요해서 이 모델을 새로 둠.
//
// ⚠️ 이 파일은 알람/근무패턴 로직 어디에서도 참조되지 않음 - condition_* 코드
// 안에서만 쓰임. DB에는 condition_shift_times 테이블(신규, v21)로 저장.

class ShiftTimeRange {
  final String shiftName;
  final int startMinutes; // 0~1439, 자정 기준 분
  final int endMinutes; // 0~1439, 자정 기준 분

  const ShiftTimeRange({
    required this.shiftName,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// 자정을 넘기는 근무인지(예: 19:00~07:00). end<=start면 다음날로 넘어간 것으로 해석.
  bool get crossesMidnight => endMinutes <= startMinutes;

  /// 실제 근무시간(분). 자정을 넘기면 24시간을 더해 계산.
  int get durationMinutes =>
      crossesMidnight ? (endMinutes + 24 * 60 - startMinutes) : (endMinutes - startMinutes);

  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  factory ShiftTimeRange.fromMap(Map<String, dynamic> map) => ShiftTimeRange(
        shiftName: map['shift_name'] as String,
        startMinutes: map['start_minutes'] as int,
        endMinutes: map['end_minutes'] as int,
      );

  Map<String, dynamic> toMap() => {
        'shift_name': shiftName,
        'start_minutes': startMinutes,
        'end_minutes': endMinutes,
      };
}
