// lib/constants/alarm_day_offset.dart
//
// ⭐ 2026-08-24 추가 - 고정 알람이 "근무가 배정된 날짜" 기준으로 전날/당일/다음날
// 중 언제 울리는지 나타내는 값. 예: 8일이 야간 근무이고 이 알람이 kAlarmDayBefore면
// 실제로는 7일에 울림 - 하지만 이 알람의 "주인"은 여전히 8일의 야간 근무임(달력/
// 알람탭/이력 어디서도 "야간" 알람으로 표시되고, 야간 근무 자체가 없어지면 같이
// 사라짐).
//
// DB에는 shift_alarm_templates.day_offset / alarms.day_offset / alarm_history.day_offset /
// alarm_creation_log.day_offset 정수 컬럼(-1/0/1)으로 그대로 저장됨. Kotlin
// AlarmRefreshEngine.kt도 동일한 -1/0/1 정수를 씀 - 이름 있는 상수가 아니라 순수
// 정수값 자체가 프로토콜이라, DB_스키마_변경_가이드.md의 "Dart/Kotlin 상수 동기화"
// 대상(checkPair)에는 해당 안 함(값이 바뀔 일이 없는 -1/0/1 세 값).

const int kAlarmDayBefore = -1;
const int kAlarmDaySame = 0;
const int kAlarmDayAfter = 1;

/// 선택 UI(Chip)에 표시할 순서 - 항상 전날/당일/다음날.
const List<int> kAlarmDayOffsets = [kAlarmDayBefore, kAlarmDaySame, kAlarmDayAfter];
