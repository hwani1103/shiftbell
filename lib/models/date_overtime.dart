// models/date_overtime.dart

class DateOvertime {
  final int? id;
  final String date; // 'YYYY-MM-DD'
  final int minutes; // 30분 단위 누적
  final String updatedAt;

  DateOvertime({
    this.id,
    required this.date,
    required this.minutes,
    required this.updatedAt,
  });

  factory DateOvertime.fromMap(Map<String, dynamic> map) {
    return DateOvertime(
      id: map['id'],
      date: map['date'],
      minutes: map['minutes'],
      updatedAt: map['updated_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'minutes': minutes,
      'updated_at': updatedAt,
    };
  }
}

/// ⭐ "3시간 30분" / "2시간" / "30분" 형식 공용 포맷터
String formatOvertimeMinutes(int totalMinutes) {
  if (totalMinutes <= 0) return '0분';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return '$hours시간 $minutes분';
  if (hours > 0) return '$hours시간';
  return '$minutes분';
}
