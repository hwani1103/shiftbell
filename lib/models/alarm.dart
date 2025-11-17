class Alarm {
  final int? id;
  final String time; // HH:mm
  final DateTime? date;
  final String type; // 'fixed' or 'custom'
  final int alarmTypeId;
  final String? shiftType;

  Alarm({
    this.id,
    required this.time,
    this.date,
    required this.type,
    required this.alarmTypeId,
    this.shiftType,
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
    };
  }

  // 예정된 알람인지
  bool get isScheduled {
    return date != null && date!.isAfter(DateTime.now());
  }
}