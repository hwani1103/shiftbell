// lib/services/schedule_notification_service.dart
//
// ⭐ 2026-09-12 - 일정관리 탭 "일정에 맞춰서 알림받기" 실제 구현. 그동안
// schedule_management_tab.dart에 스위치/칩 UI만 있고 실제 예약 로직이 전혀
// 없던 목업이었음(_scheduleNotifyDraftCache, 세션 한정 메모리 캐시) - 이제
// date_schedules(DB v23) notify_enabled/notify_offset_minutes 컬럼 값을 기준으로
// 실제 Native AlarmManager 알림을 예약/취소한다.
//
// 전체근무표_개선안_및_일정알림_설계메모.md 2장의 결론:
//  - 기존 "알람"(잠금화면/벨소리/스누즈)과 완전히 별개인 가벼운 일반 알림 1건
//  - 소리/진동/무음은 이 알림의 전용 Notification 채널("일정 알림")의 시스템
//    기본값을 그대로 따름 - 여기서 커스텀 사운드/무음을 강제하지 않음(설계
//    옵션 (A): 기존 알람과 같은 Native AlarmManager 기반 - 앱이 완전히 종료돼도
//    정시에 울려야 하므로, flutter_local_notifications 같은 순수 Dart 예약(B)
//    대신 이미 검증된 Native 경로를 재사용함).
//  - 등록/취소 트리거 지점은 date_schedule_provider.dart의 create/update/delete
//    셋뿐 - date_schedules는 알람처럼 반복 패턴이 아니라 개별 1회성 일정이라
//    "10일치 롤링 재생성" 같은 개념 자체가 불필요(설계메모 참고).
//  - 지난(과거) 시각으로 계산되는 트리거는 아예 예약하지 않고 조용히 스킵함
//    (예: 오늘 이미 지난 시각에 알림을 켠 채로 일정을 만드는 경우) - 존재하지
//    않는 과거 시각을 Native에 넘기면 AlarmManager가 즉시(또는 예측 불가능한
//    시점에) 울려버릴 수 있음.
//
// Kotlin 쪽 대응 파일: ScheduleNotificationScheduler.kt(실제 스케줄/취소 +
// 재부팅 재예약), ScheduleNotificationReceiver.kt(수신 시 알림 표시), MainActivity.kt
// (scheduleDateNotification/cancelDateNotification MethodChannel 핸들러).

import 'package:flutter/foundation.dart';

import '../constants/platform_channel.dart';
import '../models/date_schedule.dart';

class ScheduleNotificationService {
  ScheduleNotificationService._();

  /// 저장된 일정 하나의 알림 상태를 Native에 동기화 - 항상 먼저 취소하고,
  /// notifyEnabled면 (그리고 트리거 시각이 미래면) 다시 예약함. update()에서
  /// "알림 설정만 바뀌었는지"를 따로 구분하지 않고 매번 이 순서를 그대로
  /// 타도 되는 이유: 취소는 예약된 게 없어도 안전한 no-op이라(Kotlin 쪽
  /// alarmManager.cancel()이 그렇게 동작함) 중복 취소로 인한 부작용이 없음.
  ///
  /// [schedule]은 반드시 DB에 저장되어 id가 확정된 상태여야 함(취소/예약 둘
  /// 다 이 id를 Native PendingIntent의 식별자로 씀).
  static Future<void> syncForSchedule(DateSchedule schedule) async {
    final id = schedule.id;
    if (id == null) return; // 저장 전 일정 - 아직 예약할 id가 없음
    await _cancel(id);
    if (!schedule.notifyEnabled) return;

    final trigger = _triggerDateTime(schedule);
    if (trigger == null) return;
    // ⭐ 과거 시각이면 예약하지 않음(위 클래스 주석 참고) - "지난 일정 알림
    // 자동 정리" 문제를 애초에 예약을 안 하는 쪽으로 단순하게 해결함.
    if (!trigger.isAfter(DateTime.now())) return;

    try {
      await kAlarmChannel.invokeMethod('scheduleDateNotification', {
        'id': id,
        'triggerAtMillis': trigger.millisecondsSinceEpoch,
        'date': schedule.date,
        'startMinutes': schedule.startMinutes,
        'content': schedule.content,
        // ⭐ 2026-09-13 - 알림 첫 줄 시간 표시("HH:mm" 또는 "HH:mm - HH:mm")용.
        // durationMinutes가 null(지속시간 미정)이면 0으로 보내 Kotlin 쪽이
        // "시작 시각만" 표시하게 함(ScheduleNotificationReceiver.kt 참고).
        'durationMinutes': schedule.durationMinutes ?? 0,
      });
    } catch (e) {
      debugPrint('⚠️ 일정 알림 예약 실패(id=$id): $e');
    }
  }

  /// 일정 삭제 시 - 예약돼 있을 수 있는 알림을 취소함(notifyEnabled 여부와
  /// 무관하게 항상 호출해도 안전 - 예약이 없으면 그냥 no-op).
  static Future<void> cancelForSchedule(int id) => _cancel(id);

  static Future<void> _cancel(int id) async {
    try {
      await kAlarmChannel.invokeMethod('cancelDateNotification', {'id': id});
    } catch (e) {
      debugPrint('⚠️ 일정 알림 취소 실패(id=$id): $e');
    }
  }

  /// ⭐ 2026-09-13 - "일정관리 화면 사용하지 않기"(탭 숨기기, `disable_tab_button.dart`)
  /// 확인 시 호출 - 예약된 일정 알림 + 이미 상태표시줄에 떠 있는 알림을 전부
  /// 없애서, 알림을 탭해 숨겨진 탭으로 강제 진입하게 되는 경로 자체를 닫는다.
  /// DB의 notify_enabled 값은 그대로 두므로 [restoreAllForTabEnable]로 원복 가능.
  static Future<void> cancelAllForTabDisable() async {
    try {
      await kAlarmChannel.invokeMethod('cancelAllScheduleNotifications');
    } catch (e) {
      debugPrint('⚠️ 일정 알림 일괄 취소 실패: $e');
    }
  }

  /// ⭐ 2026-09-13 - "일정관리 화면 사용하기"(탭 복원) 시 호출 - 숨겨져 있던
  /// 동안 취소됐던 일정 알림들을 원래 상태로 전부 복원함(재부팅 재예약과
  /// 동일한 Native 함수를 재사용).
  static Future<void> restoreAllForTabEnable() async {
    try {
      await kAlarmChannel.invokeMethod('rescheduleAllScheduleNotifications');
    } catch (e) {
      debugPrint('⚠️ 일정 알림 일괄 복원 실패: $e');
    }
  }

  /// date('YYYY-MM-DD') 자정 + startMinutes - notifyOffsetMinutes.
  /// Kotlin ScheduleNotificationScheduler.kt의 triggerMillisFor()와 반드시
  /// 같은 계산이어야 함(재부팅 재예약 시 Native가 이 로직을 다시 구현해서
  /// 씀 - 알람 생성 로직의 Dart/Kotlin 이중구현과 같은 선례, DB 스키마
  /// 변경 가이드가 아니라 이 파일 상단 주석에 남겨둠).
  static DateTime? _triggerDateTime(DateSchedule schedule) {
    final parts = schedule.date.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final base = DateTime(year, month, day);
    return base.add(Duration(
        minutes: schedule.startMinutes - schedule.notifyOffsetMinutes));
  }
}
