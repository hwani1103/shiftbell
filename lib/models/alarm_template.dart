class AlarmTemplate {
  final int? id;
  final String shiftType;
  final String time;
  final int alarmTypeId;

  /// ⭐ 이 알람이 shiftType이 배정된 날짜 기준으로 며칠째에 울리는지.
  /// -1=전날, 0=당일(기본값), 1=다음날. [[AlarmDayOffset]] 참고.
  final int dayOffset;

  AlarmTemplate({
    this.id,
    required this.shiftType,
    required this.time,
    required this.alarmTypeId,
    this.dayOffset = 0,
  });

  factory AlarmTemplate.fromMap(Map<String, dynamic> map) {
    return AlarmTemplate(
      id: map['id'],
      shiftType: map['shift_type'],
      time: map['time'],
      alarmTypeId: map['alarm_type_id'],
      dayOffset: map['day_offset'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shift_type': shiftType,
      'time': time,
      'alarm_type_id': alarmTypeId,
      'day_offset': dayOffset,
    };
  }
}
