// lib/utils/sleep_format_util.dart
//
// ⭐ 실제 수면 기록 화면들(condition_tab.dart의 미니 달력 카드, 전체보기 화면)이
// 공유하는 순수 포맷 헬퍼. 원래 condition_tab.dart 안에 private로 있던 것을
// 여러 화면에서 재사용하기 위해 공용 파일로 뺐다 - 계산/판정 로직은 전혀 없음.

import '../models/sleep_record.dart';

const List<String> kWeekdayLabelsKo = ['월', '화', '수', '목', '금', '토', '일'];

String fmtWeekday(DateTime date) => kWeekdayLabelsKo[date.weekday - 1];

/// "9/15 (월)"
String fmtDateWeekday(DateTime date) => '${date.month}/${date.day} (${fmtWeekday(date)})';

/// "9/15 22:00"
String fmtDateTime(DateTime dt) {
  return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// "22:00"
String fmtTimeOnly(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

String fmtDuration(Duration d) {
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  if (h <= 0) return '$m분';
  if (m == 0) return '$h시간';
  return '$h시간 $m분';
}

String fmtMinutesAsClock(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 수면 기록 하나의 표시용 소요시간. 2026-09-04엔 [source]가 자동추정/위젯
/// 버튼 기록이면 10분 단위로 반올림해서 보여줬었는데(사용자 입력만 분 단위
/// 정밀도), 2026-09-05 - "사용자 입력은 정밀한데 나머지만 뭉뚱그려 보이는 게
/// 오히려 일관성이 없다"는 지적으로 원복 - source와 무관하게 항상 [fmtDuration]
/// 그대로(분 단위까지 정확하게) 보여준다. 파라미터는 호출부 3곳(condition_tab.dart/
/// sleep_calendar_full_screen.dart)을 안 건드리려고 시그니처만 유지.
String fmtSleepDuration(Duration d, SleepSource source) => fmtDuration(d);
