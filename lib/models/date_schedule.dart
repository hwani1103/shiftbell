// lib/models/date_schedule.dart
//
// ⭐ 2026-08-27 - 일정관리 탭(schedule_management_tab.dart)의 영구 저장 모델.
// DB v20에서 신설된 date_schedules 테이블과 1:1 대응. date_memos(달력 탭 메모)와는
// 완전히 별개 테이블/CRUD - 절대 섞지 말 것(메모_자동분류_ML_계획.md, 2026-08-27
// "Phase 4~5 완료 기록" 참고).
//
// predictedCategory/isUserCorrected는 메모_자동분류_ML_계획.md Phase 5의 카테고리
// 자동배정 결과를 기록하는 필드 - 지금은 화면에서 안 쓰지만(UI에 노출 안 함),
// v1부터 캡처해둬야 나중에 재학습용 피드백(Phase 7)을 놓치지 않는다는 그 계획서의
// 경고를 그대로 따른 것.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 일정 아이콘 색 팔레트 - 새 일정마다 순서대로 하나씩 돌아가며 배정됨
/// (schedule_management_tab.dart의 _colorCursor 참고). DB엔 이 리스트의
/// index만 저장(color_index) - Color 자체는 저장/복원 시 이 리스트를 통해서만 오간다.
const List<Color> kScheduleBlockColors = [
  Color(0xFF4FC3F7),
  Color(0xFFFFA726),
  Color(0xFF81C784),
  Color(0xFF9575CD),
  Color(0xFFE57373),
  Color(0xFF4DB6AC),
  Color(0xFFF06292),
  Color(0xFF7986CB),
];

class DateSchedule {
  final int? id; // null = 아직 저장 안 됨(신규 생성 중)
  final String date; // 'YYYY-MM-DD'
  final String content;
  final int startMinutes;
  // ⭐ 2026-08-27 - null 허용으로 변경(요청: "몇 시간 할지는 안 정해도 되게").
  // DB(date_schedules.duration_minutes)는 여전히 NOT NULL이라 스키마 변경 없이
  // 0을 "미정" sentinel로 씀(0분짜리 실제 프리셋은 없어서 안전) - fromMap/toMap
  // 참고. 0은 절대 실제 소요시간으로 쓰지 말 것.
  final int? durationMinutes;
  final Color color;
  // ⭐ _kScheduleCategoryIcons(schedule_management_tab.dart) 인덱스(0-based),
  // 내용 렌더 스타일(1~8), 내용 폰트(1~5).
  final int iconIndex;
  final int styleIndex;
  final int fontIndex;
  // 메모_자동분류_ML_계획.md Phase 5 - MemoCategoryClassifier가 처음 제안했던
  // 카테고리 키('work' 등). 사용자가 아이콘을 직접 골라서 저장한 경우 null.
  final String? predictedCategory;
  // 최종 iconIndex가 predictedCategory의 아이콘과 다르면 true(=사용자가 자동
  // 배정을 고쳤다는 뜻 - 재학습용 신호).
  final bool isUserCorrected;
  final String createdAt;
  final String? updatedAt;

  const DateSchedule({
    this.id,
    required this.date,
    required this.content,
    required this.startMinutes,
    required this.durationMinutes,
    this.color = kAppMainAccent,
    this.iconIndex = 0,
    this.styleIndex = 1,
    this.fontIndex = 1,
    this.predictedCategory,
    this.isUserCorrected = false,
    required this.createdAt,
    this.updatedAt,
  });

  // ⭐ durationMinutes는 nullable이라 "안 건드림"과 "명시적으로 null로
  // 지움"을 구분해야 함 - clearDuration:true를 넘기면 durationMinutes 인자를
  // 무시하고 null로 지운다(소요시간 미정으로 되돌리는 경로용).
  DateSchedule copyWith({
    int? id,
    String? date,
    String? content,
    int? startMinutes,
    int? durationMinutes,
    bool clearDuration = false,
    Color? color,
    int? iconIndex,
    int? styleIndex,
    int? fontIndex,
    String? predictedCategory,
    bool? isUserCorrected,
    String? createdAt,
    String? updatedAt,
  }) {
    return DateSchedule(
      id: id ?? this.id,
      date: date ?? this.date,
      content: content ?? this.content,
      startMinutes: startMinutes ?? this.startMinutes,
      durationMinutes:
          clearDuration ? null : (durationMinutes ?? this.durationMinutes),
      color: color ?? this.color,
      iconIndex: iconIndex ?? this.iconIndex,
      styleIndex: styleIndex ?? this.styleIndex,
      fontIndex: fontIndex ?? this.fontIndex,
      predictedCategory: predictedCategory ?? this.predictedCategory,
      isUserCorrected: isUserCorrected ?? this.isUserCorrected,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DateSchedule.fromMap(Map<String, dynamic> map) {
    final colorIndex = (map['color_index'] as int?) ?? 0;
    final rawDuration = map['duration_minutes'] as int? ?? 0;
    return DateSchedule(
      id: map['id'] as int?,
      date: map['date'] as String,
      content: map['content'] as String,
      startMinutes: map['start_minutes'] as int,
      durationMinutes: rawDuration == 0 ? null : rawDuration,
      color: kScheduleBlockColors[colorIndex % kScheduleBlockColors.length],
      iconIndex: (map['icon_index'] as int?) ?? 0,
      styleIndex: (map['style_index'] as int?) ?? 1,
      fontIndex: (map['font_index'] as int?) ?? 1,
      predictedCategory: map['predicted_category'] as String?,
      isUserCorrected: ((map['is_user_corrected'] as int?) ?? 0) == 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    var colorIndex = kScheduleBlockColors.indexOf(color);
    if (colorIndex == -1) colorIndex = 0;
    return {
      if (id != null) 'id': id,
      'date': date,
      'content': content,
      'start_minutes': startMinutes,
      'duration_minutes': durationMinutes ?? 0,
      'color_index': colorIndex,
      'icon_index': iconIndex,
      'style_index': styleIndex,
      'font_index': fontIndex,
      'predicted_category': predictedCategory,
      'is_user_corrected': isUserCorrected ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
