class Alarm {
  final int? id;
  final String time; // HH:mm
  final DateTime? date;
  final String type; // 'fixed' or 'custom'
  final int alarmTypeId;
  final String? shiftType;

  /// ⭐ 이 알람의 "주인"인 근무(shiftType)가 배정된 날짜 기준으로 -1(전날)/0(당일)/
  /// 1(다음날) 중 언제 울리는지. date는 항상 실제로 울리는 날짜(이미 오프셋이
  /// 반영된 값) - dayOffset은 "근무일 대비 표시용" 정보로 별도 보관함.
  /// alarm_day_offset.dart 참고.
  final int dayOffset;

  Alarm({
    this.id,
    required this.time,
    this.date,
    required this.type,
    required this.alarmTypeId,
    this.shiftType,
    this.dayOffset = 0,
  });

  factory Alarm.fromMap(Map<String, dynamic> map) {
  // ⭐ 안전한 날짜 파싱
  DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (e) {
      print('⚠️ 알람 날짜 파싱 실패: $value');
      return null;
    }
  }

  return Alarm(
    id: map['id'],
    time: map['time'],
    date: parseDate(map['date']),  // ⭐ 변경
    type: map['type'],
    alarmTypeId: map['alarm_type_id'],
    shiftType: map['shift_type'],
    dayOffset: map['day_offset'] ?? 0,
  );
}

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'date': date?.toIso8601String(),
      'type': type,
      'alarm_type_id': alarmTypeId,
      'shift_type': shiftType,
      'day_offset': dayOffset,
    };
  }

  // 예정된 알람인지
  bool get isScheduled {
    return date != null && date!.isAfter(DateTime.now());
  }
}
