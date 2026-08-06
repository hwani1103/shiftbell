// models/shift_schedule.dart

import 'dart:convert';
import 'package:flutter/material.dart';

// models/shift_schedule.dart

// ⭐ 순수 연/월/일만으로 계산하는 Julian Day Number - 시간대/서머타임과 완전히
// 무관해서 두 날짜 사이의 "진짜 날짜 수 차이"를 항상 정확히 구할 수 있음.
// DateTime.difference(...).inDays는 두 시각의 절대적인(마이크로초) 차이를
// 24시간 단위로 나누는 방식이라, 시작일~대상일 사이에 서머타임 전환일(하루가
// 23/25시간)이 껴 있는 지역에서는 패턴 인덱스가 하루씩 밀릴 수 있음
// (Native의 AlarmRefreshEngine.kt에도 동일한 계산을 동일한 방식으로 맞춰둠).
int julianDayNumber(int year, int month, int day) {
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
}

class ShiftSchedule {

  // ⭐ 개선된 팔레트 19색 (중복 제거, 신선한 색상 추가, 대비 최적화)
  // ⭐ CRITICAL FIX: 색상들이 "계열별로 뭉쳐서" 나열돼있었음(하늘색→민트→...→시안이
  // 전부 밝은 청록 계열이라 서로 멀리 떨어진 인덱스에서도 비슷해 보였음, 인디고 계열도
  // 마찬가지). 자동 배정은 이 배열 순서 그대로 앞에서부터 채워나가는데, 근무 카드가
  // 몇 개 안 되면(예: 3~5개) 바로 인접한 색상끼리 배정되기 쉬워서 특히 눈에 띄었음.
  // 계열(파랑/초록/보라/노랑·주황/핑크/무채색)을 매번 바꿔가며 배치해서, 인덱스가
  // 가까운(=먼저 자동 배정되는) 색상일수록 서로 최대한 달라 보이게 재배열함.
  static final List<Color> shiftPalette = [
    Color(0xFFB3E5FC), // 1. 하늘색 (Sky Blue) - 밝은 파랑
    Color(0xFFFFCCBC), // 2. 코랄색 (Coral) - 따뜻한 핑크/주황
    Color(0xFF388E3C), // 3. 진한 초록 (Green 700) - 어두운 초록 (흰 글씨)
    Color(0xFFE1BEE7), // 4. 연한 보라 (Lavender Purple) - 보라 계열
    Color(0xFFFFF9C4), // 5. 노란색 (Sunny Yellow) - 밝은 노랑
    Color(0xFF1976D2), // 6. 진한 파랑 (Blue 700) - 어두운 파랑 (흰 글씨)
    Color(0xFFDCE775), // 7. 라임 (Lime 300) - 연두색
    Color(0xFFEC407A), // 8. 생동감 핑크 (Pink 400) - 명확한 핑크 (흰 글씨)
    Color(0xFFB2DFDB), // 9. 민트색 (Mint Green) - 초록 계열
    Color(0xFF7B1FA2), // 10. 진한 보라 (Purple 700) - 어두운 보라 (흰 글씨)
    Color(0xFFD7CCC8), // 11. 베이지색 (Warm Beige) - 중립 톤
    Color(0xFFFF6F00), // 12. 따뜻한 주황 (Orange 800) - 선명한 주황 (흰 글씨)
    Color(0xFFB0BEC5), // 13. 연한 회색 (Blue Grey 200) - 밝은 회색 (흰 글씨)
    Color(0xFF00897B), // 14. 진한 청록 (Teal 600) - 어두운 청록 (흰 글씨)
    Color(0xFF9FA8DA), // 15. 연한 인디고 (Indigo 200) - 연한 인디고 (흰 글씨)
    Color(0xFF9CCC65), // 16. 올리브 (Light Green 400) - 올리브색 (흰 글씨)
    Color(0xFF80DEEA), // 17. 시안 (Cyan 200) - 청록색 (흰 글씨)
    Color(0xFFAB47BC), // 18. 생동감 보라 (Purple 400) - 명확한 보라 (흰 글씨)
    Color(0xFF5C6BC0), // 19. 밝은 인디고 (Indigo 400) - 인디고 강화 (흰 글씨)
  ];

  // ⭐ 휴무 고정 색상 (명확한 빨강, 파스텔 아님)
  static final Color offColor = Color(0xFFEF5350); // Red (진한 빨강, 흰 글씨)

  // ⭐ 배경색 밝기 판단 (최적 대비를 위해 보수적 기준 적용)
  static bool isBright(Color c) {
    final luminance = (c.red * 0.299 + c.green * 0.587 + c.blue * 0.114);
    return luminance > 200;  // 중간 톤 색상도 흰 글씨 사용하여 대비 강화
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
  final Map<String, int>? shiftDurations;  // ⭐ 근무명 -> 기본 근무시간(분)

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
    this.shiftDurations,
  });

  // ⭐ 근무명별 기본 근무시간(분) 조회. 사용자가 "근로시간 및 OT 설정"에서 직접
  // 설정하기 전까지는 0분이 기본값 - 임의로 8시간을 가정해서 보여주면 사용자가
  // 설정하지 않은 값이 실제 근로시간인 것처럼 오해할 수 있어서, 설정 전에는
  // 아예 "근거 없음" 상태로 취급함 (달력탭 근로시간 팝업들이 이 상태를 감지해서
  // 안내 문구를 보여줌).
  int getDurationMinutes(String shiftName) {
    return shiftDurations?[shiftName] ?? 0;
  }

  // ⭐ 근무카드 중 하나라도 근로시간이 설정돼 있는지. 전부 0분(=미설정)이면
  // 근로시간을 누적할 근거가 없다는 뜻 - 달력탭의 "총 근로시간" 관련 팝업들이
  // 이 상태를 감지해서 리스트 대신 설정 안내 문구를 보여줌.
  bool get hasAnyWorkDuration => shiftTypes.any((s) => getDurationMinutes(s) > 0);

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

    Map<String, int>? parsedShiftDurations;
    if (map['shift_durations'] != null) {
      try {
        parsedShiftDurations = Map<String, int>.from(jsonDecode(map['shift_durations']));
      } catch (e) {
        print('❌ shiftDurations 파싱 실패: ${map['shift_durations']}, error: $e');
        parsedShiftDurations = null;
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
      shiftDurations: parsedShiftDurations,
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
      'shift_durations': shiftDurations != null ? jsonEncode(shiftDurations) : null,
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

    final daysDiff = julianDayNumber(date.year, date.month, date.day) -
        julianDayNumber(startDate!.year, startDate!.month, startDate!.day);
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

    final daysDiff = julianDayNumber(date.year, date.month, date.day) -
        julianDayNumber(startDate!.year, startDate!.month, startDate!.day);
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  }
}