class AlarmHistory {
  final int? id;
  final int alarmId;
  final String scheduledTime;
  final DateTime scheduledDate;
  final DateTime actualRingTime;
  final String dismissType;  // 'swiped', 'snoozed', 'timeout', 'ringing'
  final int snoozeCount;
  final String? shiftType;
  final DateTime createdAt;

  AlarmHistory({
    this.id,
    required this.alarmId,
    required this.scheduledTime,
    required this.scheduledDate,
    required this.actualRingTime,
    required this.dismissType,
    required this.snoozeCount,
    this.shiftType,
    required this.createdAt,
  });

  // 안전한 DateTime 파싱 (예외 시 현재 시각 반환)
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    try {
      return DateTime.parse(value.toString());
    } catch (e) {
      print('⚠️ DateTime 파싱 실패: $value');
      return DateTime.now();
    }
  }

  factory AlarmHistory.fromMap(Map<String, dynamic> map) {
    return AlarmHistory(
      id: map['id'],
      alarmId: map['alarm_id'] ?? 0,
      scheduledTime: map['scheduled_time'] ?? '',
      scheduledDate: _parseDate(map['scheduled_date']),
      actualRingTime: _parseDate(map['actual_ring_time']),
      dismissType: map['dismiss_type'] ?? 'unknown',
      snoozeCount: map['snooze_count'] ?? 0,
      shiftType: map['shift_type'],
      createdAt: _parseDate(map['created_at']),
    );
  }

  String get dismissTypeText {
    switch (dismissType) {
      case 'swiped':
        return '스와이프로 끔';
      case 'snoozed':
        return '스누즈 ${snoozeCount}회';
      case 'timeout':
        return '자동 종료 (놓침)';
      case 'ringing':
        return '울리는 중...';
      default:
        return dismissType;
    }
  }
}