// models/date_overtime.dart

import 'package:flutter/widgets.dart';

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

/// ⭐ "3시간 30분" / "2시간" / "30분" 형식 공용 포맷터.
/// 영어 현지화: 시간 단위(시간/분)에 복수형 처리가 필요한 영어 특성상 ICU
/// Intl.plural로 나누면 오히려 코드가 장황해져서, 영어권에서 아주 흔히 쓰이는
/// 압축 표기(예: "3h 30m")로 통일함 - 이러면 "hour(s)/minute(s)" 단복수 분기
/// 자체가 필요 없어짐(보고서 2-7번 카운터 이슈의 실용적 해결책, 상세 근거는
/// 교대시계_영어화_현지화_보고서_영문판.md 참고). context가 필요해져서 기존
/// formatOvertimeMinutes(int) 호출부(calendar_tab.dart 등)는 모두
/// formatOvertimeMinutes(context, int)로 갱신함.
String formatOvertimeMinutes(BuildContext context, int totalMinutes) {
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  if (isKorean) {
    if (totalMinutes <= 0) return '0분';
    if (hours > 0 && minutes > 0) return '$hours시간 $minutes분';
    if (hours > 0) return '$hours시간';
    return '$minutes분';
  }

  if (totalMinutes <= 0) return '0m';
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  return '${minutes}m';
}
