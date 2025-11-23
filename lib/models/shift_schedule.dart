// models/shift_schedule.dart

import 'dart:convert';
import 'package:flutter/material.dart';

// models/shift_schedule.dart

class ShiftSchedule {

  // ⭐ 신규: 고정 팔레트 8색
  static final List<Color> shiftPalette = [
    Color(0xFF42A5F5), // Blue (밝음)
    Color(0xFF66BB6A), // Green (중간)
    Color(0xFF26C6DA), // Teal (밝음)
    Color(0xFF5C6BC0), // Indigo (어두움)
    Color(0xFF00BCD4), // Cyan (밝음)
    Color(0xFF7E57C2), // Deep Purple (중간)
    Color(0xFF9CCC65), // Lime (밝음)
    Color(0xFF8D6E63), // Brown (어두움)
  ];
  
  // ⭐ 신규: 휴무 고정 색상
  static final Color offColor = Color(0xFFEF5350); // Red 400
  
  // ⭐ 신규: 배경색 밝기 판단
  static bool isBright(Color c) {
    final luminance = (c.red * 0.299 + c.green * 0.587 + c.blue * 0.114);
    return luminance > 160;
  }
  
  // ⭐ 신규: 자동 텍스트 색상 (배경에 따라)
  static Color getTextColor(Color bg) {
    return isBright(bg) ? Colors.black : Colors.white;
  }

  final int? id;
  final bool isRegular;
  List<String>? pattern;
  final int? todayIndex;
  final List<String> shiftTypes;  // 전체 근무 종류 (기본 5개 + 커스텀 4개)
  List<String>? activeShiftTypes;  // ⭐ 실제 사용 중인 근무 종류
  final DateTime? startDate;
  final Map<String, int>? shiftColors;
  Map<String, String>? assignedDates;

  ShiftSchedule({
    this.id,
    required this.isRegular,
    this.pattern,
    this.todayIndex,
    required this.shiftTypes,
    this.activeShiftTypes,  // ⭐ 추가
    this.startDate,
    this.shiftColors,
    this.assignedDates,
  });

  factory ShiftSchedule.fromMap(Map<String, dynamic> map) {
    return ShiftSchedule(
      id: map['id'],
      isRegular: map['is_regular'] == 1,
      pattern: map['pattern'] != null ? (map['pattern'] as String).split(',').toList() : null,
      todayIndex: map['today_index'],
      shiftTypes: (map['shift_types'] as String).split(','),
      activeShiftTypes: map['active_shift_types'] != null  // ⭐ 추가
          ? (map['active_shift_types'] as String).split(',')
          : null,
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date']) : null,
      shiftColors: map['shift_colors'] != null
          ? Map<String, int>.from(jsonDecode(map['shift_colors']))
          : null,
      assignedDates: map['assigned_dates'] != null
          ? Map<String, String>.from(jsonDecode(map['assigned_dates']))
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
      'active_shift_types': activeShiftTypes?.join(','),  // ⭐ 추가
      'start_date': startDate?.toIso8601String(),
      'shift_colors': shiftColors != null ? jsonEncode(shiftColors) : null,
      'assigned_dates': assignedDates != null ? jsonEncode(assignedDates) : null,
    };
  }

  String getShiftForDate(DateTime date) {
  final dateStr = date.toIso8601String().split('T')[0];
  
  // ⭐ 먼저 예외 확인 (우선순위)
  if (assignedDates != null && assignedDates!.containsKey(dateStr)) {
    return assignedDates![dateStr]!;
  }
  
  // 규칙적인 경우 패턴 계산
  if (isRegular) {
    if (pattern == null || todayIndex == null || startDate == null) {
      return '미설정';
    }

    final adjustedStartDate = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    
    final daysDiff = targetDate.difference(adjustedStartDate).inDays;
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  } else {
    return '미설정';
  }
}
}