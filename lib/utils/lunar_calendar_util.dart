// lib/utils/lunar_calendar_util.dart
//
// 음력 날짜 변환 - 실제 값은 lunar_calendar_data.dart의 사전 계산 표(2015-01-01~
// 2041-01-31)를 이진 탐색해서 찾음. 음력은 관측/보정이 섞인 KASI 기준이라
// 매번 수식으로 계산하지 않고 표로 저장하는 쪽을 택함(생성 방법은 데이터
// 파일 상단 주석 참고). 범위 밖 날짜는 null.

import 'lunar_calendar_data.dart';

/// 변환된 음력 날짜 - 이 앱에서는 월/일/윤달 여부만 씀(연도는 화면에 안 씀).
class LunarDate {
  final int month;
  final int day;
  final bool isLeapMonth;

  const LunarDate({required this.month, required this.day, required this.isLeapMonth});
}

/// 양력 날짜를 음력으로 변환. 표 범위(kLunarEpoch ~ +kLunarMaxOffset) 밖이면 null.
LunarDate? solarToLunar(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  final offset = normalized.difference(kLunarEpoch).inDays;
  if (offset < 0 || offset > kLunarMaxOffset) return null;

  // kLunarMonthStartOffsets에서 offset보다 작거나 같은 마지막 값의 인덱스 찾기
  // (그 음력월이 시작된 시점 - 이진 탐색, 표는 오름차순 정렬돼 있음)
  int lo = 0;
  int hi = kLunarMonthStartOffsets.length - 1;
  int idx = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (kLunarMonthStartOffsets[mid] <= offset) {
      idx = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  final code = kLunarMonthCodes[idx];
  final isLeap = code > 20;
  final month = isLeap ? code - 20 : code;
  final day = offset - kLunarMonthStartOffsets[idx] + 1;
  return LunarDate(month: month, day: day, isLeapMonth: isLeap);
}

/// 상세 팝업용 - "음력 4.14" / 윤달이면 "음력 윤4.14"
String formatLunarDateFull(LunarDate lunar) {
  final leapPrefix = lunar.isLeapMonth ? '윤' : '';
  return '음력 $leapPrefix${lunar.month}.${lunar.day}';
}

/// 메인 달력 셀용 - "(4.14)" / 윤달이면 "(윤4.14)"
String formatLunarDateCompact(LunarDate lunar) {
  final leapPrefix = lunar.isLeapMonth ? '윤' : '';
  return '($leapPrefix${lunar.month}.${lunar.day})';
}
