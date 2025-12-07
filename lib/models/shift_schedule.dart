// models/shift_schedule.dart

import 'dart:convert';
import 'package:flutter/material.dart';

// models/shift_schedule.dart

class ShiftSchedule {

  // ⭐ 파스텔 팔레트 8색 (서로 구분되는 순서로 배치)
  static final List<Color> shiftPalette = [
    Color(0xFFB3E5FC), // 1. 하늘색 (Sky Blue) - 파랑 계열
    Color(0xFFCFD8DC), // 2. 청회색 (Blue Grey) - 차분한 회색
    Color(0xFFD7CCC8), // 3. 베이지색 (Warm Beige) - 중립 톤
    Color(0xFFB2DFDB), // 4. 민트색 (Mint Green) - 초록 계열
    Color(0xFFE1BEE7), // 5. 보라색 (Lavender Purple) - 보라 계열
    Color(0xFFFFF9C4), // 6. 노란색 (Sunny Yellow) - 밝은 노랑
    Color(0xFFFFCCBC), // 7. 코랄색 (Coral) - 따뜻한 핑크/주황
    Color(0xFFFFE0B2), // 8. 주황색 (Peach Orange) - 코랄색과 비슷
  ];

  // ⭐ 휴무 고정 색상 (명확한 빨강, 파스텔 아님)
  static final Color offColor = Color(0xFFEF5350); // Red (진한 빨강)
  
  // ⭐ 배경색 밝기 판단 (파스텔 톤용 기준 낮춤)
  static bool isBright(Color c) {
    final luminance = (c.red * 0.299 + c.green * 0.587 + c.blue * 0.114);
    return luminance > 150;  // 파스텔은 대부분 밝으므로 기준 낮춤
  }

  // ⭐ 자동 텍스트 색상 (배경에 따라 대비 최적화)
  static Color getTextColor(Color bg) {
    return isBright(bg)
        ? Color(0xFF212121)  // 진한 회색 (파스텔 배경에 잘 보임)
        : Colors.white;
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
    // ⭐ CRITICAL FIX #4-5: 예외 처리 추가 (DB 손상 시 앱 크래시 방지)
    DateTime? parsedStartDate;
    if (map['start_date'] != null) {
      try {
        parsedStartDate = DateTime.parse(map['start_date']);
      } catch (e) {
        print('❌ startDate 파싱 실패: ${map['start_date']}, error: $e');
        parsedStartDate = null;
      }
    }

    Map<String, int>? parsedShiftColors;
    if (map['shift_colors'] != null) {
      try {
        parsedShiftColors = Map<String, int>.from(jsonDecode(map['shift_colors']));
      } catch (e) {
        print('❌ shiftColors 파싱 실패: ${map['shift_colors']}, error: $e');
        parsedShiftColors = null;
      }
    }

    Map<String, String>? parsedAssignedDates;
    if (map['assigned_dates'] != null) {
      try {
        parsedAssignedDates = Map<String, String>.from(jsonDecode(map['assigned_dates']));
      } catch (e) {
        print('❌ assignedDates 파싱 실패: ${map['assigned_dates']}, error: $e');
        parsedAssignedDates = null;
      }
    }

    return ShiftSchedule(
      id: map['id'],
      isRegular: map['is_regular'] == 1,
      pattern: map['pattern'] != null ? (map['pattern'] as String).split(',').toList() : null,
      todayIndex: map['today_index'],
      shiftTypes: (map['shift_types'] as String).split(','),
      activeShiftTypes: map['active_shift_types'] != null
          ? (map['active_shift_types'] as String).split(',')
          : null,
      startDate: parsedStartDate,
      shiftColors: parsedShiftColors,
      assignedDates: parsedAssignedDates,
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

  // ⭐ 패턴상의 근무만 반환 (수동 할당 무시)
  String getPatternShiftForDate(DateTime date) {
    if (!isRegular || pattern == null || todayIndex == null || startDate == null) {
      return '';
    }

    final adjustedStartDate = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    final daysDiff = targetDate.difference(adjustedStartDate).inDays;
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  }
}