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

  // ⭐ 2026-08-25 추가 - 값(필드) 기준 동등성. 원래 기본 Object identity라
  // DB에서 매번 새로 읽어온 Alarm은 내용이 완전히 같아도 항상 "다른 객체"로
  // 취급됐음. alarm_provider.dart의 AlarmNotifier가 몇 초 간격으로 자동
  // 재조회(refresh)하는데, 그때마다 리스트가 "바뀐 것처럼" 감지돼서
  // Riverpod이 실제로는 아무것도 안 바뀌었는데도 다음알람탭 등 구독하는
  // 화면을 매번 다시 빌드시키던 원인 - 이 == 덕분에 내용이 같으면 리스트
  // 비교(listEquals)에서 "안 바뀜"으로 판정되어 불필요한 재빌드가 사라짐.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Alarm &&
        other.id == id &&
        other.time == time &&
        other.date == date &&
        other.type == type &&
        other.alarmTypeId == alarmTypeId &&
        other.shiftType == shiftType &&
        other.dayOffset == dayOffset;
  }

  @override
  int get hashCode => Object.hash(id, time, date, type, alarmTypeId, shiftType, dayOffset);
}
