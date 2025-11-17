class AlarmTemplate {
  final int? id;
  final String shiftType;
  final String time;
  final int alarmTypeId;

  AlarmTemplate({
    this.id,
    required this.shiftType,
    required this.time,
    required this.alarmTypeId,
  });

  factory AlarmTemplate.fromMap(Map<String, dynamic> map) {
    return AlarmTemplate(
      id: map['id'],
      shiftType: map['shift_type'],
      time: map['time'],
      alarmTypeId: map['alarm_type_id'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shift_type': shiftType,
      'time': time,
      'alarm_type_id': alarmTypeId,
    };
  }
}