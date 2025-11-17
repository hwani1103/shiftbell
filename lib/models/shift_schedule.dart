import 'dart:convert';

class ShiftSchedule {
  final int? id;
  final bool isRegular;
  final List<String>? pattern;
  final int? todayIndex;
  final List<String> shiftTypes;
  final DateTime? startDate;
  final Map<String, int>? shiftColors;  // ⭐ 신규

  ShiftSchedule({
    this.id,
    required this.isRegular,
    this.pattern,
    this.todayIndex,
    required this.shiftTypes,
    this.startDate,
    this.shiftColors,  // ⭐ 신규
  });

  factory ShiftSchedule.fromMap(Map<String, dynamic> map) {
    return ShiftSchedule(
      id: map['id'],
      isRegular: map['is_regular'] == 1,
      pattern: map['pattern'] != null ? (map['pattern'] as String).split(',') : null,
      todayIndex: map['today_index'],
      shiftTypes: (map['shift_types'] as String).split(','),
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date']) : null,
      shiftColors: map['shift_colors'] != null  // ⭐ 신규
          ? Map<String, int>.from(jsonDecode(map['shift_colors']))
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'is_regular': isRegular ? 1 : 0,
      'pattern': pattern?.join(','),
      'today_index': todayIndex,
      'shift_types': shiftTypes.join(','),
      'start_date': startDate?.toIso8601String(),
      'shift_colors': shiftColors != null ? jsonEncode(shiftColors) : null,  // ⭐ 신규
    };
  }

  String getShiftForDate(DateTime date) {
    if (!isRegular || pattern == null || todayIndex == null || startDate == null) {
      return '미설정';
    }

    final adjustedStartDate = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    
    final daysDiff = targetDate.difference(adjustedStartDate).inDays;
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  }
}