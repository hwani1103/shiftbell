// lib/providers/date_schedule_provider.dart
//
// ⭐ 2026-08-27 - 일정관리 탭(date_schedules 테이블, DB v20) 전용 상태 관리.
// date_memos(메모)를 다루는 memo_provider.dart와는 완전히 별개 - 절대 섞지 말 것.
// 날짜별로 캐싱하는 구조도 memo_provider.dart와 동일한 패턴.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/date_schedule.dart';
import '../services/database_service.dart';

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
    return saved;
  }

  Future<void> update(DateSchedule schedule) async {
    await _db.updateSchedule(schedule);
    final list = (state[schedule.date] ?? const <DateSchedule>[])
        .map((s) => s.id == schedule.id ? schedule : s)
        .toList();
    state = {...state, schedule.date: list};
  }

  Future<void> delete(DateSchedule schedule) async {
    if (schedule.id == null) return;
    await _db.deleteSchedule(schedule.id!);
    final list = (state[schedule.date] ?? const <DateSchedule>[])
        .where((s) => s.id != schedule.id)
        .toList();
    state = {...state, schedule.date: list};
  }
}
