// lib/providers/date_schedule_provider.dart
//
// ⭐ 2026-08-27 - 일정관리 탭(date_schedules 테이블, DB v20) 전용 상태 관리.
// date_memos(메모)를 다루는 memo_provider.dart와는 완전히 별개 - 절대 섞지 말 것.
// 날짜별로 캐싱하는 구조도 memo_provider.dart와 동일한 패턴.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/date_schedule.dart';
import '../services/database_service.dart';
import '../services/schedule_notification_service.dart';
import '../services/app_analytics.dart';

final dateScheduleProvider = StateNotifierProvider<DateScheduleNotifier,
    Map<String, List<DateSchedule>>>((ref) {
  return DateScheduleNotifier();
});

class DateScheduleNotifier
    extends StateNotifier<Map<String, List<DateSchedule>>> {
  DateScheduleNotifier() : super({});

  final _db = DatabaseService.instance;

  /// 이미 로드된 날짜면 다시 안 읽음 - 날짜칩 왔다갔다할 때마다 매번 쿼리하지
  /// 않도록. 새로고침이 필요하면 [forceReloadForDate]를 쓸 것.
  Future<void> loadForDate(String date) async {
    if (state.containsKey(date)) return;
    await forceReloadForDate(date);
  }

  Future<void> forceReloadForDate(String date) async {
    final items = await _db.getSchedulesForDate(date);
    state = {...state, date: items};
  }

  /// ⭐ 2026-09-14 (출시전 감사 #13) - notifyScheduled: 필요한 알림 예약이 실패했으면 false
  /// (ScheduleNotificationService.syncForSchedule 참고). 일정 자체는 이미 저장된 상태.
  Future<({DateSchedule saved, bool notifyScheduled})> create(
      DateSchedule schedule) async {
    final saved = await _db.createSchedule(schedule);
    // 알림 사용 여부만 분류값으로 보낸다 - 일정 내용·시각은 보내지 않음
    AppAnalytics.track(AnalyticsEvent.scheduleCreated,
        params: {'notify': schedule.notifyEnabled ? 'on' : 'off'});
    final list = [...(state[schedule.date] ?? const <DateSchedule>[]), saved];
    state = {...state, schedule.date: list};
    // ⭐ 2026-09-12 - "일정에 맞춰서 알림받기". id가 확정된 뒤(saved)에만
    // Native에 예약 가능(PendingIntent 식별자로 이 id를 씀) - schedule.id는
    // 아직 null이라 반드시 saved를 넘겨야 함.
    final notifyScheduled =
        await ScheduleNotificationService.syncForSchedule(saved);
    if (schedule.notifyEnabled && notifyScheduled) {
      AppAnalytics.track(AnalyticsEvent.scheduleNotificationChanged,
          params: {'enabled': 'on'});
    }
    return (saved: saved, notifyScheduled: notifyScheduled);
  }

  /// 반환값: 필요한 알림 예약이 실패했으면 false (#13, [create] 참고)
  Future<bool> update(DateSchedule schedule) async {
    final previous = state.values.expand((items) => items)
        .where((s) => s.id == schedule.id)
        .firstOrNull;
    await _db.updateSchedule(schedule);
    AppAnalytics.track(AnalyticsEvent.scheduleEdited);
    // 날짜를 옮기면 이전 날짜 캐시에서도 제거하고 새 날짜에는 즉시 반영한다.
    // DB만 이동하면 이미 방문한 두 날짜에서 옛 카드/빈 화면이 남는다.
    final updated = <String, List<DateSchedule>>{
      for (final entry in state.entries)
        entry.key: entry.key == schedule.date
            ? entry.value.map((s) => s.id == schedule.id ? schedule : s).toList()
            : entry.value.where((s) => s.id != schedule.id).toList(),
    };
    final destination = updated[schedule.date] ?? <DateSchedule>[];
    if (!destination.any((s) => s.id == schedule.id)) destination.add(schedule);
    updated[schedule.date] = destination;
    state = updated;
    // ⭐ 알림 on/off·N분전 값·내용이 뭐가 바뀌었든 한 번에 재동기화(취소 후
    // 필요하면 재예약) - syncForSchedule 주석 참고, 매번 취소부터 하는 게
    // 항상 안전하고 단순함.
    final synchronized =
        await ScheduleNotificationService.syncForSchedule(schedule);
    if (synchronized &&
        previous != null &&
        (previous.notifyEnabled != schedule.notifyEnabled ||
            previous.notifyOffsetMinutes != schedule.notifyOffsetMinutes)) {
      AppAnalytics.track(AnalyticsEvent.scheduleNotificationChanged,
          params: {'enabled': schedule.notifyEnabled ? 'on' : 'off'});
    }
    return synchronized;
  }

  Future<void> delete(DateSchedule schedule) async {
    if (schedule.id == null) return;
    await _db.deleteSchedule(schedule.id!);
    AppAnalytics.track(AnalyticsEvent.scheduleDeleted);
    final list = (state[schedule.date] ?? const <DateSchedule>[])
        .where((s) => s.id != schedule.id)
        .toList();
    state = {...state, schedule.date: list};
    await ScheduleNotificationService.cancelForSchedule(schedule.id!);
  }
}
