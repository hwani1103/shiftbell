// models/friend_schedule.dart
//
// ⭐ 친구 공유 기능 - Firestore friend_schedules/{ownerId} 문서를 디코딩한 결과물.
// ShiftSchedule과 구조가 거의 같지만 의도적으로 분리된 별도 모델임 - 공유 데이터에는
// OT/근로시간 설정/알람 설정이 "절대" 안 들어가게 하려는 게 이 파일의 존재 이유라,
// 나중에 ShiftSchedule에 새 필드(예: shiftDurations)가 늘어나도 이 모델은 그 필드를
// 아예 모르기 때문에 실수로 같이 공유될 일이 없음.
//
// 공유되는 것: 근무 패턴(pattern/todayIndex/startDate), 근무별 색상(shiftColors),
//            근무변경으로 생긴 예외(assignedDates).
// 공유 안 되는 것: 메모, OT, 근로시간(shiftDurations), 알람 설정 전부.
// (친구공유_v1_스펙.md 참고 - 메모는 v1에서 완전히 제거됨)

import 'dart:convert';
import '../models/shift_schedule.dart';

class FriendScheduleData {
  static const maxOwnerNameLength = 80;
  static const maxShiftNameLength = 80;
  static const maxPatternLength = 128;
  static const maxMapEntries = 5000;

  /// ⭐ 2026-09-14 (출시전 교차 검토 X-11) - 1.0.22는 공유 이름 길이 제한이 없었음. 그때 만든 긴 이름의 문서·캐시를 거부하면
  /// 업데이트 뒤 친구 근무표가 안 보이고 내 업로드도 계속 보류됨 → 거부 대신 표시·업로드 길이로 자름(runes 기준).
  static String clampOwnerName(String name) {
    final runes = name.runes;
    return runes.length <= maxOwnerNameLength ? name : String.fromCharCodes(runes.take(maxOwnerNameLength));
  }

  final String ownerName; // ⭐ 코드를 만든 사람이 직접 적은 자기 이름
  final bool isRegular;
  final List<String>? pattern;
  final int? todayIndex;
  final DateTime? startDate;
  final Map<String, int> shiftColors; // 근무명 -> ARGB 색상값
  final Map<String, String> assignedDates; // "yyyy-MM-dd" -> 근무명 (근무변경 예외)
  final DateTime updatedAt; // ⭐ Firestore 문서의 마지막 upsert 시각

  const FriendScheduleData({
    required this.ownerName,
    required this.isRegular,
    this.pattern,
    this.todayIndex,
    this.startDate,
    required this.shiftColors,
    required this.assignedDates,
    required this.updatedAt,
  });

  // ⭐ ShiftSchedule.getShiftForDate와 완전히 동일한 계산 (assignedDates 우선 →
  // 패턴 인덱스). 로직을 여기서 다시 구현하는 대신 julianDayNumber만 재사용함.
  String getShiftForDate(DateTime date) {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    if (assignedDates.containsKey(dateStr)) {
      return assignedDates[dateStr]!;
    }

    if (isRegular) {
      if (pattern == null || pattern!.isEmpty || todayIndex == null || startDate == null) {
        return kUnsetShiftSentinel;
      }
      final daysDiff = julianDayNumber(date.year, date.month, date.day) -
          julianDayNumber(startDate!.year, startDate!.month, startDate!.day);
      final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
      return pattern![index];
    }
    return kUnsetShiftSentinel;
  }

  // ⭐ ShiftSchedule.getPatternShiftForDate와 동일 - assignedDates(근무변경 예외) 무시하고
  // 순수 패턴값만 반환. friend_calendar_view.dart가 이걸로 "패턴과 다른 날(근무변경됨)"
  // 표시를 실제 달력탭과 같은 방식으로 재현함.
  String getPatternShiftForDate(DateTime date) {
    if (!isRegular || pattern == null || pattern!.isEmpty || todayIndex == null || startDate == null) {
      return '';
    }
    final daysDiff = julianDayNumber(date.year, date.month, date.day) -
        julianDayNumber(startDate!.year, startDate!.month, startDate!.day);
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  }

  Map<String, dynamic> toJson() => {
        'ownerName': ownerName,
        'isRegular': isRegular,
        'pattern': pattern,
        'todayIndex': todayIndex,
        'startDate': startDate?.toIso8601String(),
        'shiftColors': shiftColors,
        'assignedDates': assignedDates,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static bool _validShiftName(Object? value) =>
      value is String && value.isNotEmpty && value.length <= maxShiftNameLength;

  static bool _validDateKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    final normalized =
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return normalized == value;
  }

  /// Firestore와 로컬 캐시는 외부 입력이다. 잘못된 자료형이나 과도한 컬렉션을
  /// 화면 모델로 바꾸지 않고 null로 거부한다.
  static FriendScheduleData? tryFromJson(Map<String, dynamic> json) {
    final ownerNameRaw = json['ownerName'];
    final isRegularRaw = json['isRegular'];
    final patternRaw = json['pattern'];
    final todayIndexRaw = json['todayIndex'];
    final startDateRaw = json['startDate'];
    final shiftColorsRaw = json['shiftColors'];
    final assignedDatesRaw = json['assignedDates'];
    final updatedAtRaw = json['updatedAt'];

    if (ownerNameRaw is! String ||
        isRegularRaw is! bool ||
        (patternRaw != null && patternRaw is! List) ||
        (todayIndexRaw != null && todayIndexRaw is! int) ||
        (startDateRaw != null && startDateRaw is! String) ||
        (shiftColorsRaw != null && shiftColorsRaw is! Map) ||
        (assignedDatesRaw != null && assignedDatesRaw is! Map) ||
        updatedAtRaw is! String) {
      return null;
    }

    final pattern = patternRaw == null
        ? null
        : List<Object?>.from(patternRaw as List);
    if (pattern != null &&
        (pattern.length > maxPatternLength ||
            pattern.any((value) => !_validShiftName(value)))) {
      return null;
    }

    final startDate = startDateRaw == null
        ? null
        : DateTime.tryParse(startDateRaw as String);
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if ((startDateRaw != null && startDate == null) || updatedAt == null) {
      return null;
    }
    if (isRegularRaw &&
        (pattern == null ||
            pattern.isEmpty ||
            todayIndexRaw == null ||
            todayIndexRaw < 0 ||
            todayIndexRaw >= pattern.length ||
            startDate == null)) {
      return null;
    }

    final rawColors = shiftColorsRaw as Map? ?? const {};
    final rawAssignments = assignedDatesRaw as Map? ?? const {};
    if (rawColors.length > maxMapEntries ||
        rawAssignments.length > maxMapEntries) {
      return null;
    }

    final colors = <String, int>{};
    for (final entry in rawColors.entries) {
      if (!_validShiftName(entry.key) ||
          entry.value is! int ||
          (entry.value as int) < 0 ||
          (entry.value as int) > 0xffffffff) {
        return null;
      }
      colors[entry.key as String] = entry.value as int;
    }

    final assignments = <String, String>{};
    for (final entry in rawAssignments.entries) {
      if (entry.key is! String ||
          !_validDateKey(entry.key as String) ||
          !_validShiftName(entry.value)) {
        return null;
      }
      assignments[entry.key as String] = entry.value as String;
    }

    return FriendScheduleData(
      ownerName: clampOwnerName(ownerNameRaw.trim()),
      isRegular: isRegularRaw,
      pattern: pattern?.cast<String>(),
      todayIndex: todayIndexRaw,
      startDate: startDate,
      shiftColors: colors,
      assignedDates: assignments,
      updatedAt: updatedAt,
    );
  }

  factory FriendScheduleData.fromJson(Map<String, dynamic> json) {
    final parsed = tryFromJson(json);
    if (parsed == null) {
      throw const FormatException('Invalid friend schedule payload');
    }
    return parsed;
  }

  String encodeToJsonString() => jsonEncode(toJson());
  factory FriendScheduleData.decodeFromJsonString(String s) {
    final decoded = jsonDecode(s);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid friend schedule cache');
    }
    return FriendScheduleData.fromJson(decoded);
  }
}
