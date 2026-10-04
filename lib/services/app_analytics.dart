// lib/services/app_analytics.dart
//
// ⭐ 2026-09-22 - 관리자 대시보드(admin_dashboard/)가 보여 줄 "사용자 행동" 이벤트.
//
// 원칙
//  - 이벤트 이름과 "언제 남기는가"만 보낸다. 근무표·메모 내용·수면 시각·알람 시각·친구 이름 같은 **내용은 절대 파라미터에 넣지 않는다**
//    (개인정보처리방침: "근무표·메모·수면 기록·알람 내용 같은 앱 데이터는 통계에 넣지 않습니다"). 파라미터는 종류(regular/irregular),
//    개수 같은 제한된 분류값뿐이다.
//  - dev flavor는 Analytics 수집이 꺼져 있어(firebase_bootstrap.dart) 이 로그는 어디에도 전송되지 않는다 → 출시 앱만 집계.
//  - 이 앱 전용 래퍼는 웹에서 보내지 않는다. 웹 뷰어 성공 열람은 web_main.dart가 웹 스트림에 별도 기록한다.
//  - 실패해도 앱 동작에는 영향이 없다(예외를 삼킨다).
//
// ⚠️ 이름을 바꾸거나 추가하면 admin_dashboard/public/assets/js/labels.js 의 EVENT_META도 같이 고칠 것
//    (test/app_analytics_test.dart가 두 목록이 일치하는지 검사한다).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';
import 'firebase_bootstrap.dart' show analytics;

/// 사용자 정의 이벤트 이름(GA4 규칙: 영문 소문자·숫자·밑줄, 40자 이하).
abstract final class AnalyticsEvent {

  static const onboardingComplete = 'onboarding_complete';
  static const backupCreated = 'backup_created';
  static const backupRestored = 'backup_restored';
  static const alarmTemplateSaved = 'alarm_template_saved';
  static const alarmDismissed = 'alarm_dismissed';
  static const alarmSnoozed = 'alarm_snoozed';
  static const alarmNoResponse = 'alarm_no_response';
  static const shiftAssigned = 'shift_assigned';
  static const calendarThemeChanged = 'calendar_theme_changed';
  static const memoSaved = 'memo_saved';
  static const otSaved = 'ot_saved';
  static const scheduleCreated = 'schedule_created';
  static const sleepRecordSaved = 'sleep_record_saved';
  static const friendShareStarted = 'friend_share_started';
  static const friendAdded = 'friend_added';
  static const helpOpened = 'help_opened';
  static const memoEdited = 'memo_edited';
  static const memoDeleted = 'memo_deleted';
  static const scheduleEdited = 'schedule_edited';
  static const scheduleDeleted = 'schedule_deleted';
  static const scheduleNotificationChanged = 'schedule_notification_changed';
  static const autoBackupCreated = 'auto_backup_created';
  static const alarmHistoryCleared = 'alarm_history_cleared';
  static const allShiftsOpened = 'all_shifts_opened';
  static const shiftNameChanged = 'shift_name_changed';
  static const shiftColorChanged = 'shift_color_changed';
  static const alarmSoundChanged = 'alarm_sound_changed';
  static const friendCalendarOpened = 'friend_calendar_opened';
  static const sleepRecordEdited = 'sleep_record_edited';
  static const sleepRecordDeleted = 'sleep_record_deleted';
  static const sleepEstimateRejected = 'sleep_estimate_rejected';

  /// 1.0.24 B - 커스텀 알람 프리셋을 날짜에 할당(파라미터 result = scheduled/past/duplicate/daily_limit/schedule_failed, 시각은 보내지 않음)
  static const customAlarmAssigned = 'custom_alarm_assigned';

  static const oneTapOpened = 'one_tap_opened';
  static const oneTapClosed = 'one_tap_closed';
  static const oneTapPresetEditorOpened = 'one_tap_preset_editor_opened';
  static const oneTapPresetSaved = 'one_tap_preset_saved';
  static const oneTapPresetUpdated = 'one_tap_preset_updated';
  static const oneTapPresetDeleted = 'one_tap_preset_deleted';
  static const oneTapPresetCancelled = 'one_tap_preset_cancelled';
  static const oneTapPresetBlocked = 'one_tap_preset_blocked';
  static const oneTapPresetSelected = 'one_tap_preset_selected';
  static const oneTapAssigned = 'one_tap_assigned';
  static const oneTapAssignRejected = 'one_tap_assign_rejected';
  static const oneTapAlarmDeleted = 'one_tap_alarm_deleted';

  /// 대시보드 EVENT_META와 대조하는 전체 목록(테스트용).
  static const all = <String>[

    oneTapOpened,
    oneTapClosed,
    oneTapPresetEditorOpened,
    oneTapPresetSaved,
    oneTapPresetUpdated,
    oneTapPresetDeleted,
    oneTapPresetCancelled,
    oneTapPresetBlocked,
    oneTapPresetSelected,
    oneTapAssigned,
    oneTapAssignRejected,
    oneTapAlarmDeleted,
    onboardingComplete,
    backupCreated,
    backupRestored,
    alarmTemplateSaved,
    alarmDismissed,
    alarmSnoozed,
    alarmNoResponse,
    shiftAssigned,
    calendarThemeChanged,
    memoSaved,
    otSaved,
    scheduleCreated,
    sleepRecordSaved,
    friendShareStarted,
    friendAdded,
    helpOpened,
    customAlarmAssigned,
    memoEdited,
    memoDeleted,
    scheduleEdited,
    scheduleDeleted,
    scheduleNotificationChanged,
    autoBackupCreated,
    alarmHistoryCleared,
    allShiftsOpened,
    shiftNameChanged,
    shiftColorChanged,
    alarmSoundChanged,
    friendCalendarOpened,
    sleepRecordEdited,
    sleepRecordDeleted,
    sleepEstimateRejected,
  ];
}

class AppAnalytics {
  AppAnalytics._();

  /// 테스트에서 "무엇이 기록됐는지" 확인하는 용도. 설정돼 있으면 Firebase 없이도 호출된다.
  @visibleForTesting
  static void Function(String name, Map<String, Object>? params)? debugSink;

  /// 기록하고 잊는다(호출부가 await 하지 않아도 되게 만든 진입점).
  static void track(String name, {Map<String, Object>? params}) {
    unawaited(_send(name, params));
  }

  static Future<void> _send(String name, Map<String, Object>? params) async {
    try {
      debugSink?.call(name, params);
      if (kIsWeb) return;
      final a = analytics;
      if (a == null) return;
      await a.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('⚠️ Analytics 이벤트 기록 실패($name): $e');
    }
  }
}

/// 알람 사용량. 알람은 Native(Kotlin)에서 울리고 끄기 때문에 Dart가 그 순간을 직접 볼 수 없다.
/// 알람이 울리는 경로에는 Firebase 코드를 넣지 않기로 했으므로(가장 중요한 경로라 위험을 늘리지 않음),
/// 이미 기기에 남는 알람 이력(alarm_history)에서 **새로 쌓인 것만** 앱을 다음에 열 때 이벤트로 보낸다.
/// → 대시보드의 알람 횟수는 "알람이 울린 시각"이 아니라 "그 뒤 처음 앱을 연 날" 기준으로 잡힌다(최대 며칠 지연).
class AlarmUsageAnalytics {
  AlarmUsageAnalytics._();

  static const cursorKey = 'analytics_alarm_history_cursor';

  /// 한 번에 보내는 종류별 최대 건수(장기간 미사용 뒤 한꺼번에 몰리는 것 방지).
  static const maxPerType = 40;

  /// 이보다 오래된 이력은 "새 사용량"으로 보지 않는다(백업 복원으로 들어온 옛 이력 등).
  static const freshWindow = Duration(hours: 72);

  static const _typeToEvent = <String, String>{
    'swiped': AnalyticsEvent.alarmDismissed,
    'snoozed': AnalyticsEvent.alarmSnoozed,
    'timeout': AnalyticsEvent.alarmNoResponse,
  };

  /// 앱 시작·재개 때 호출. [rowsSince]/[maxId]는 테스트에서 DB 대신 주입한다.
  static Future<void> reportNew({
    DateTime? now,
    Future<List<Map<String, Object?>>> Function(int afterId)? rowsSince,
    Future<int> Function()? maxId,
  }) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cursor = prefs.getInt(cursorKey);
      if (cursor == null) {
        // 계측이 들어간 첫 실행: 옛 이력을 새 사용량으로 오인해 한꺼번에 보내지 않도록 기준선만 저장한다.
        await prefs.setInt(cursorKey, await (maxId ?? _maxId)());
        return;
      }
      final rows = await (rowsSince ?? _rowsSince)(cursor);
      if (rows.isEmpty) return;

      final cutoff = (now ?? DateTime.now()).subtract(freshWindow);
      final sent = <String, int>{};
      var lastId = cursor;
      for (final r in rows) {
        final id = r['id'] as int;
        if (id > lastId) lastId = id;
        final event = _typeToEvent[r['dismiss_type']];
        if (event == null) continue; // ringing/removed 등은 사용량이 아님
        final ring = DateTime.tryParse('${r['actual_ring_time']}');
        if (ring == null || ring.isBefore(cutoff)) continue;
        final n = sent[event] ?? 0;
        if (n >= maxPerType) continue;
        sent[event] = n + 1;
        AppAnalytics.track(event);
      }
      await prefs.setInt(cursorKey, lastId);
    } catch (e) {
      debugPrint('⚠️ 알람 사용량 집계 실패: $e');
    }
  }

  static Future<int> _maxId() async {
    final db = await DatabaseService.instance.database;
    final r = await db.rawQuery('SELECT MAX(id) AS m FROM alarm_history');
    return (r.first['m'] as int?) ?? 0;
  }

  static Future<List<Map<String, Object?>>> _rowsSince(int afterId) async {
    final db = await DatabaseService.instance.database;
    return db.rawQuery(
      'SELECT id, dismiss_type, actual_ring_time FROM alarm_history WHERE id > ? ORDER BY id ASC LIMIT 400',
      [afterId],
    );
  }
}
