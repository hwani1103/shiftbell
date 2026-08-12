// models/friend_schedule.dart
//
// ⭐ 친구 공유 기능 - 친구가 보낸 "공유 코드"를 디코딩한 결과물. ShiftSchedule과
// 구조가 거의 같지만 의도적으로 분리된 별도 모델임 - 공유 데이터에는 OT/근로시간
// 설정/알람 설정이 "절대" 안 들어가게 하려는 게 이 파일의 존재 이유라, 나중에
// ShiftSchedule에 새 필드(예: shiftDurations)가 늘어나도 이 모델은 그 필드를
// 아예 모르기 때문에 실수로 같이 공유될 일이 없음.
//
// 공유되는 것: 근무 패턴(pattern/todayIndex/startDate), 근무별 색상(shiftColors),
//            근무변경으로 생긴 예외(assignedDates), 메모(선택 - 보내는 사람이 켜야만 포함).
// 공유 안 되는 것: OT, 근로시간(shiftDurations), 알람 설정 전부.

import 'dart:convert';
import '../models/shift_schedule.dart';

class FriendScheduleData {
  final String ownerName; // ⭐ 코드를 만든 사람이 직접 적은 자기 이름 (공유 코드 안에 내장)
  final bool isRegular;
  final List<String>? pattern;
  final int? todayIndex;
  final DateTime? startDate;
  final Map<String, int> shiftColors; // 근무명 -> ARGB 색상값
  final Map<String, String> assignedDates; // "yyyy-MM-dd" -> 근무명 (근무변경 예외)
  final Map<String, List<String>>? memos; // null이면 메모를 아예 공유 안 한 것
  final DateTime exportedAt;

  const FriendScheduleData({
    required this.ownerName,
    required this.isRegular,
    this.pattern,
    this.todayIndex,
    this.startDate,
    required this.shiftColors,
    required this.assignedDates,
    this.memos,
    required this.exportedAt,
  });

  bool get hasMemos => memos != null;

  // ⭐ ShiftSchedule.getShiftForDate와 완전히 동일한 계산 (assignedDates 우선 →
  // 패턴 인덱스). 로직을 여기서 다시 구현하는 대신 julianDayNumber만 재사용함.
  String getShiftForDate(DateTime date) {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    if (assignedDates.containsKey(dateStr)) {
      return assignedDates[dateStr]!;
    }

    if (isRegular) {
      if (pattern == null || pattern!.isEmpty || todayIndex == null || startDate == null) {
        return '미설정';
      }
      final daysDiff = julianDayNumber(date.year, date.month, date.day) -
          julianDayNumber(startDate!.year, startDate!.month, startDate!.day);
      final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
      return pattern![index];
    }
    return '미설정';
  }

  List<String> memosForDate(DateTime date) {
    if (memos == null) return const [];
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return memos![dateStr] ?? const [];
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
        'memos': memos,
        'exportedAt': exportedAt.toIso8601String(),
      };

  factory FriendScheduleData.fromJson(Map<String, dynamic> json) {
    return FriendScheduleData(
      ownerName: json['ownerName'] as String? ?? '친구',
      isRegular: json['isRegular'] as bool? ?? false,
      pattern: (json['pattern'] as List?)?.map((e) => e.toString()).toList(),
      todayIndex: json['todayIndex'] as int?,
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate'] as String) : null,
      shiftColors: (json['shiftColors'] as Map?)?.map((k, v) => MapEntry(k.toString(), v as int)) ?? {},
      assignedDates: (json['assignedDates'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      memos: (json['memos'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList()),
      ),
      exportedAt: json['exportedAt'] != null ? DateTime.tryParse(json['exportedAt'] as String) ?? DateTime.now() : DateTime.now(),
    );
  }

  String encodeToJsonString() => jsonEncode(toJson());
  factory FriendScheduleData.decodeFromJsonString(String s) => FriendScheduleData.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
