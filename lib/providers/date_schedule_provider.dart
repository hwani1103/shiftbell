// lib/providers/date_schedule_provider.dart
//
// ⭐ 2026-08-27 - 일정관리 탭(date_schedules 테이블, DB v20) 전용 상태 관리.
// date_memos(메모)를 다루는 memo_provider.dart와는 완전히 별개 - 절대 섞지 말 것.
// 날짜별로 캐싱하는 구조도 memo_provider.dart와 동일한 패턴.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/date_schedule.dart';
import '../services/database_service.dart';
import '../services/schedule_notification_service.dart';

final dateScheduleProvider = StateNotifierProvider<DateScheduleNotifier,
    Map<String, List<DateSchedule>>>((ref) {
  return DateScheduleNotifier();
});

class DateScheduleNotifier extends StateNotifier<Map<String, List<DateSchedule>>> {
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

  Future<DateSchedule> create(DateSchedule schedule) async {
    final saved = await _db.createSchedule(schedule);
    final list = [...(state[schedule.date] ?? const <DateSchedule>[]), saved];
    state = {...state, schedule.date: list};
    // ⭐ 2026-09-12 - "일정에 맞춰서 알림받기". id가 확정된 뒤(saved)에만
    // Native에 예약 가능(PendingIntent 식별자로 이 id를 씀) - schedule.id는
    // 아직 null이라 반드시 saved를 넘겨야 함.
    await ScheduleNotificationService.syncForSchedule(saved);
    return saved;
  }

  Future<void> update(DateSchedule schedule) async {
    await _db.updateSchedule(schedule);
    final list = (state[schedule.date] ?? const <DateSchedule>[])
        .map((s) => s.id == schedule.id ? schedule : s)
        .toList();
    state = {...state, schedule.date: list};
    // ⭐ 알림 on/off·N분전 값·내용이 뭐가 바뀌었든 한 번에 재동기화(취소 후
    // 필요하면 재예약) - syncForSchedule 주석 참고, 매번 취소부터 하는 게
    // 항상 안전하고 단순함.
    await ScheduleNotificationService.syncForSchedule(schedule);
  }

  Future<void> delete(DateSchedule schedule) async {
    if (schedule.id == null) return;
    await _db.deleteSchedule(schedule.id!);
    final list = (state[schedule.date] ?? const <DateSchedule>[])
        .where((s) => s.id != schedule.id)
        .toList();
    state = {...state, schedule.date: list};
    await ScheduleNotificationService.cancelForSchedule(schedule.id!);
  }
}
