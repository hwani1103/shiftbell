// lib/utils/weekday_util.dart
//
// ⭐ 로케일에 따라 바뀌어야 하는 "요일 한 글자/짧은 이름" 라벨(일/월/화... vs
// Sun/Mon/Tue...)을 한 곳으로 모음. 예전엔 calendar_tab.dart,
// calendar_theme_lab_screen.dart, next_alarm_tab.dart, all_shifts_view.dart,
// all_alarms_history_view.dart, work_hours_calculator.dart,
// friend_calendar_view.dart 등 최소 6~7곳에 각자 `_weekdayKr = ['일','월',...]`
// 형태로 중복 정의돼 있었음(교대시계_영어화_현지화_보고서_영문판.md 2-4번 참고).
//
// ⭐ 주의: 일부 달력 테마(다크 그리드=boldGrid, 미니멀 언더라인=underline)가 쓰는
// 기존의 _weekdayEn3/_weekdayEn1 배열은 "그 테마에서는 로케일과 무관하게 항상
// 영어 약자로 보이는" 디자인 선택임(한국어 사용자에게도 그렇게 보임) - 그 두
// 배열은 절대 건드리지 말 것. 이 파일은 오직 "로케일에 따라 바뀌어야 하는" 요일
// 표시(기존 _weekdayKr 자리)만 다룸.
//
// ⭐ 요일 시작 순서 결정: 한국(일요일 시작)과 영어권 중 미국(en-US, 일요일 시작
// 관습)이 일치해서, 그대로 일요일(index 0) 시작 고정으로 둠. 영국/유럽식(월요일
// 시작, ISO 8601)은 이번 영어 현지화 범위에서 다루지 않음 - 필요해지면
// Localizations.localeOf(context).countryCode로 분기 추가 가능(보고서 2-4번 결정).
import 'package:flutter/widgets.dart';

// index: 0=일/Sun, 1=월/Mon, 2=화/Tue, 3=수/Wed, 4=목/Thu, 5=금/Fri, 6=토/Sat
// (date.weekday % 7 과 정렬 맞음: DateTime.weekday는 월=1~일=7이라 7%7=0)
const List<String> kWeekdayKo = ['일', '월', '화', '수', '목', '금', '토'];
const List<String> kWeekdayEnShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const List<String> kWeekdayEnNarrow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// 로케일 인식 요일 라벨(기존에 각 화면이 `_weekdayKr[i]`로 직접 참조하던 자리를
/// 대체). [narrow]=true면 영어 로케일에서 한 글자로 줄임(한국어는 원래 한 글자라
/// narrow 여부와 무관하게 항상 한 글자).
String weekdayLabel(BuildContext context, int index, {bool narrow = false}) {
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  if (isKorean) return kWeekdayKo[index];
  return narrow ? kWeekdayEnNarrow[index] : kWeekdayEnShort[index];
}

/// DateTime.weekday(월=1~일=7)를 위 배열 인덱스(일=0~토=6)로 변환.
int weekdayIndexOf(DateTime date) => date.weekday % 7;
