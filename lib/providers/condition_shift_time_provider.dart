// lib/providers/condition_shift_time_provider.dart
//
// ⭐ 컨디션 매니저 전용 - condition_shift_times 테이블(신규, v21)을 Riverpod으로
// 노출. lib/providers/schedule_provider.dart의 ScheduleNotifier 패턴을 그대로
// 따름(StateNotifier + AsyncValue). 기존 scheduleProvider/알람 Provider는 이
// 파일을 참조하지 않음 - 컨디션 매니저 쪽에서만 이 provider를 씀.

import 'data_revision_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_time_range.dart';
import '../services/database_service.dart';

final conditionShiftTimeProvider =
    StateNotifierProvider<ConditionShiftTimeNotifier, AsyncValue<Map<String, ShiftTimeRange>>>(
        (ref) => ConditionShiftTimeNotifier(ref));

class ConditionShiftTimeNotifier extends StateNotifier<AsyncValue<Map<String, ShiftTimeRange>>> {
  ConditionShiftTimeNotifier([this._ref]) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref? _ref;

  // ⭐ 2026-09-14 (출시전 수정 연결 - docs/release_audit/contracts.md §3) - 원본 저장이 성공한 뒤에만 변경 통지.
  // 계산 쪽(G3 컨디션·수면 provider)이 이 revision을 watch해 다시 계산함. 저장 실패·예외면 올리지 않음.
  void _notifyChanged() {
    _ref?.read(dataRevisionProvider(DataDomain.shiftTimes).notifier).state++;
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final map = await DatabaseService.instance.getConditionShiftTimes();
      state = AsyncValue.data(map);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  Future<void> save(String shiftName, int startMinutes, int endMinutes) async {
    final range = ShiftTimeRange(
      shiftName: shiftName,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
    await DatabaseService.instance.upsertConditionShiftTime(range);
    final current = Map<String, ShiftTimeRange>.from(state.value ?? {});
    current[shiftName] = range;
    state = AsyncValue.data(current);
    _notifyChanged();
  }

  /// ⭐ 2026-09-14 (출시전 감사 #28) - DB에는 이미 저장된 값(DatabaseService.saveShiftTimeRange - 근로시간과 한 트랜잭션)을
  /// 상태에만 반영. [range]가 null이면 삭제.
  void applyExternallyPersisted(String shiftName, ShiftTimeRange? range) {
    final current = Map<String, ShiftTimeRange>.from(state.value ?? {});
    if (range == null) {
      current.remove(shiftName);
    } else {
      current[shiftName] = range;
    }
    state = AsyncValue.data(current);
  }

  Future<void> remove(String shiftName) async {
    await DatabaseService.instance.deleteConditionShiftTime(shiftName);
    final current = Map<String, ShiftTimeRange>.from(state.value ?? {});
    current.remove(shiftName);
    state = AsyncValue.data(current);
    _notifyChanged();
  }
}
