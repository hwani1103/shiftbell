// lib/utils/schedule_focus_request.dart
//
// ⭐ 2026-09-12 - 일정 알림을 탭했을 때 "일정관리 탭으로 이동 + 그 일정이 있는
// 시간대로 바로 focusing"하기 위한 1회성 신호. Native(ScheduleNotificationReceiver.kt)가
// 만든 알림을 탭하면 MainActivity가 Dart로 openDateSchedule을 invokeMethod하고,
// main.dart의 핸들러가 여기에 요청을 채운 뒤 탭을 일정관리로 전환함
// (kScheduleManagementTabIndex 참고) - schedule_management_tab.dart가 이 값을
// 읽어서 날짜/시간축 위치를 맞추고 즉시 소비(clear)한다.
//
// 이 파일이 main.dart와 schedule_management_tab.dart 양쪽에서 참조돼야 해서
// (그 두 파일이 서로를 import하지 않는 관계라) 별도 유틸로 뺌 - 이 탭 안의
// 다른 세션 한정 캐시들(예: 과거 _scheduleNotifyDraftCache)과 달리, 이건 탭
// 전환 시점의 짧은 릴레이용이라 상태가 파일 하나에 묶여있지 않아도 안전함.
import 'package:flutter/foundation.dart';

class ScheduleFocusRequest {
  /// 'YYYY-MM-DD'. schedule_management_tab.dart의 dateKey 포맷과 동일.
  final String date;
  final int startMinutes;
  const ScheduleFocusRequest({required this.date, required this.startMinutes});
}

/// 대기 중인 포커스 요청 - null이면 없음. schedule_management_tab.dart가
/// 소비하는 즉시 다시 null로 되돌려서, 그 뒤 날짜를 스와이프하거나 탭을
/// 오갈 때 같은 요청이 반복 적용되지 않게 함.
final ValueNotifier<ScheduleFocusRequest?> pendingScheduleFocusRequest =
    ValueNotifier<ScheduleFocusRequest?>(null);
