// lib/providers/schedule_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../services/alarm_generation_service.dart';
import 'package:flutter/services.dart';
import '../constants/platform_channel.dart';
import '../services/widget_refresh_service.dart';
import '../services/friend_sync_service.dart';
import '../constants/alarm_limits.dart';


final scheduleProvider = StateNotifierProvider<ScheduleNotifier, AsyncValue<ShiftSchedule?>>((ref) {
  return ScheduleNotifier();
});

class ScheduleNotifier extends StateNotifier<AsyncValue<ShiftSchedule?>> {
  ScheduleNotifier() : super(const AsyncValue.loading()) {
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    state = const AsyncValue.loading();
    try {
      final schedule = await DatabaseService.instance.getShiftSchedule();
      state = AsyncValue.data(schedule);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> saveSchedule(ShiftSchedule schedule) async {
  try {
    final id = await DatabaseService.instance.saveShiftSchedule(schedule);
    
    // ⭐ ID를 포함한 새 스케줄 객체 생성
    final savedSchedule = ShiftSchedule(
      id: id,
      isRegular: schedule.isRegular,
      pattern: schedule.pattern,
      todayIndex: schedule.todayIndex,
      shiftTypes: schedule.shiftTypes,
      activeShiftTypes: schedule.activeShiftTypes,
      startDate: schedule.startDate,
      shiftColors: schedule.shiftColors,
      customShiftColors: schedule.customShiftColors,
      assignedDates: schedule.assignedDates,
      shiftDurations: schedule.shiftDurations,
    );

    state = AsyncValue.data(savedSchedule);
    WidgetRefreshService.refresh();  // ⭐ 홈 화면 위젯도 즉시 갱신
    FriendSyncService.instance.syncIfEnabled(savedSchedule);  // ⭐ 친구공유 중이면 Firestore도 갱신
  } catch (e, stack) {
    state = AsyncValue.error(e, stack);
    rethrow;
  }
}

  // ⭐ DB에는 이미 다른 곳(예: DatabaseService.renameShiftAtomic - 근무명 변경을 여러
  // 테이블과 함께 하나의 트랜잭션으로 묶어야 해서 saveSchedule/updateSchedule을 못
  // 씀)에서 저장이 끝난 스케줄을 Riverpod 상태에만 반영함 - DB에 다시 쓰지 않음(중복
  // 쓰기 방지). 위젯 갱신/친구공유 동기화는 saveSchedule/updateSchedule과 동일하게 함.
  void applyExternallyPersisted(ShiftSchedule schedule) {
    state = AsyncValue.data(schedule);
    WidgetRefreshService.refresh();
    FriendSyncService.instance.syncIfEnabled(schedule);
  }

  Future<void> updateSchedule(ShiftSchedule schedule) async {
    try {
      await DatabaseService.instance.updateShiftSchedule(schedule);
      state = AsyncValue.data(schedule);
      WidgetRefreshService.refresh();  // ⭐ 홈 화면 위젯도 즉시 갱신
      FriendSyncService.instance.syncIfEnabled(schedule);  // ⭐ 친구공유 중이면 Firestore도 갱신
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  // ⭐ 필드 대부분을 그대로 복사하면서 pattern/assignedDates만 새 값으로 바꾼
  // "새" ShiftSchedule 인스턴스를 만듦. changeShift/bulkAssignShift/
  // changeShiftWithAlarms가 전부 이걸 거쳐가도록 함 - 예전엔 이 세 함수가
  // currentSchedule의 필드(assignedDates 맵 등)를 직접 mutate한 다음 그 "같은
  // 객체 참조"를 그대로 state에 다시 넣었는데, ShiftSchedule에 operator==가
  // 없어서 Riverpod이 "이전 state와 동일한 객체"로 보고 리스너 통지를 건너뛸 수
  // 있었음 (근무 변경 직후 이번 달 OT 카드가 즉시 안 갱신되는 버그의 원인 중 하나).
  // 매번 새 인스턴스를 만들면 이 문제가 원천적으로 사라짐.
  ShiftSchedule _withPattern(ShiftSchedule s, List<String> pattern) {
    return ShiftSchedule(
      id: s.id,
      isRegular: s.isRegular,
      pattern: pattern,
      todayIndex: s.todayIndex,
      shiftTypes: s.shiftTypes,
      activeShiftTypes: s.activeShiftTypes,
      startDate: s.startDate,
      shiftColors: s.shiftColors,
      customShiftColors: s.customShiftColors,
      assignedDates: s.assignedDates,
      shiftDurations: s.shiftDurations,
    );
  }

  ShiftSchedule _withAssignedDates(ShiftSchedule s, Map<String, String> assignedDates) {
    return ShiftSchedule(
      id: s.id,
      isRegular: s.isRegular,
      pattern: s.pattern,
      todayIndex: s.todayIndex,
      shiftTypes: s.shiftTypes,
      activeShiftTypes: s.activeShiftTypes,
      startDate: s.startDate,
      shiftColors: s.shiftColors,
      customShiftColors: s.customShiftColors,
      assignedDates: assignedDates,
      shiftDurations: s.shiftDurations,
    );
  }

  Future<void> changeShift(DateTime date, String newShiftType) async {
    final currentSchedule = state.value;
    if (currentSchedule == null) return;

    final dateStr = date.toIso8601String().split('T')[0];

    if (currentSchedule.isRegular) {
      if (currentSchedule.pattern == null ||
          currentSchedule.todayIndex == null ||
          currentSchedule.startDate == null) {
        return;
      }

      // ⭐ DST 안전한 일수 계산 (shift_schedule.dart의 julianDayNumber 참고)
      final daysDiff = julianDayNumber(date.year, date.month, date.day) -
          julianDayNumber(
            currentSchedule.startDate!.year,
            currentSchedule.startDate!.month,
            currentSchedule.startDate!.day,
          );
      final index = ((currentSchedule.todayIndex! + daysDiff) %
                    currentSchedule.pattern!.length +
                    currentSchedule.pattern!.length) %
                    currentSchedule.pattern!.length;

      final newPattern = List<String>.from(currentSchedule.pattern!);
      newPattern[index] = newShiftType;
      await updateSchedule(_withPattern(currentSchedule, newPattern));
    } else {
      final newAssignedDates = Map<String, String>.from(currentSchedule.assignedDates ?? {});
      newAssignedDates[dateStr] = newShiftType;
      await updateSchedule(_withAssignedDates(currentSchedule, newAssignedDates));
    }
  }

  Future<void> bulkAssignShift(List<DateTime> dates, String shiftType) async {
    final currentSchedule = state.value;
    if (currentSchedule == null) return;

    // ⭐ 규칙적/불규칙 관계없이 assignedDates에 예외로 저장
    // (패턴을 직접 수정하면 같은 인덱스의 모든 날짜가 바뀜)
    final newAssignedDates = Map<String, String>.from(currentSchedule.assignedDates ?? {});
    for (var date in dates) {
      final dateStr = date.toIso8601String().split('T')[0];
      newAssignedDates[dateStr] = shiftType;
    }

    await updateSchedule(_withAssignedDates(currentSchedule, newAssignedDates));
  }

  Future<void> resetSchedule() async {
    try {
      // 1. 모든 알람 가져오기
      final alarms = await DatabaseService.instance.getAllAlarms();

      // 2. Native 알람 모두 취소
      for (var alarm in alarms) {
        if (alarm.id != null) {
          await AlarmService().cancelAlarm(alarm.id!);
          print('✅ Native 알람 취소: DB ID ${alarm.id}');
        }
      }

      // 3. 모든 Notification 삭제
      const platform = kAlarmChannel;
      try {
        await platform.invokeMethod('cancelAllNotifications');
        print('✅ 모든 Notification 삭제 완료');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      // 3-1. ⭐ CRITICAL FIX: shownNotifications 정리 (유령 Notification 방지)
      try {
        await platform.invokeMethod('clearShownNotifications');
        print('✅ shownNotifications 정리 완료');
      } catch (e) {
        print('⚠️ shownNotifications 정리 실패: $e');
      }

      // 4. AlarmGuardReceiver 취소
      try {
        await platform.invokeMethod('cancelAlarmGuard');
        print('✅ AlarmGuardReceiver 취소 완료');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 취소 실패: $e');
      }

      // 5. DB 삭제 (알람은 이력 기록 후 삭제)
      await DatabaseService.instance.deleteAllAlarms();

      // 5-1. ⭐ "초기화" 버튼을 누른 경우에 한해서만 이력/생성로그도 함께 삭제.
      // (다른 모든 삭제 경로는 이력을 영구 보존하지만, 스케줄 자체를 완전히
      // 새로 시작하는 이 경우는 예외 - 이전 근무 패턴의 이력이 남아있으면 혼란스러움)
      await DatabaseService.instance.resetAllAlarmHistoryAndLog();

      final db = await DatabaseService.instance.database;
      await db.delete('shift_schedule');
      await db.delete('shift_alarm_templates');

      state = const AsyncValue.data(null);
      WidgetRefreshService.refresh();  // ⭐ 홈 화면 위젯도 초기화 반영
      print('🗑️ 교대근무 초기화 완료');
    } catch (e) {
      print('❌ 교대근무 초기화 실패: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    await _loadSchedule();
  }

  // ⭐ 근무 변경 - 이 날짜만 바뀌어도 "전날/다음날" 오프셋 알람이 있을 수 있어서
  // 실제로 재계산해야 하는 알람 날짜는 [date-1, date, date+1] 세 개임
  // (alarm_generation_service.dart의 datesAffectedByShiftChange/
  // regenerateFixedAlarmsForDates 공용 로직 - onboarding/달력 일괄배정과 동일한
  // 계산식을 공유해야 Kotlin AlarmRefreshEngine.kt의 diff 갱신과도 어긋나지 않음).
  Future<void> changeShiftWithAlarms(DateTime date, String newShiftType) async {
  final currentSchedule = state.value;
  if (currentSchedule == null || currentSchedule.id == null) {
    print('❌ 스케줄 없음 또는 ID 없음');
    return;
  }

  final db = await DatabaseService.instance.database;

  // ⭐ currentSchedule을 직접 mutate하지 않고 새 assignedDates 맵을 만듦 - 아래
  // state 갱신 시 "새 객체"를 넣어야 Riverpod이 변경을 확실히 통지함 (_withPattern
  // 근처 주석 참고). DB에 쓰는 toMap()도 이 새 맵 기준으로 만들어야 일치함.
  final newAssignedDates = Map<String, String>.from(currentSchedule.assignedDates ?? {});
  final dateStr = date.toIso8601String().split('T')[0];
  newAssignedDates[dateStr] = newShiftType;
  final updatedSchedule = _withAssignedDates(currentSchedule, newAssignedDates);

  // ⭐ 영향받는 최대 3개 날짜([date-1, date, date+1])의 고정 알람 재계산 대상을
  // 미리 계산(순수 계산, DB 불필요) - 10일 창을 벗어나는 날짜는 알아서 빠짐
  // (자정 갱신 때 자동 생성).
  final now = DateTime.now();
  final targetDates = datesAffectedByShiftChange(date).where((d) {
    final daysDiff = julianDayNumber(d.year, d.month, d.day) -
        julianDayNumber(now.year, now.month, now.day);
    return daysDiff < kAlarmRefreshWindowDays;
  }).toSet();

  // ⭐ 스케줄 저장 + 알람 재계산을 하나의 트랜잭션으로 묶음 - 둘 사이에 "스케줄은
  // 이미 바뀌었는데 알람은 아직 옛 근무 기준"인 순간이 절대 노출되지 않게 함.
  RegenerateAlarmsResult? result;
  await db.transaction((txn) async {
    print('🔵 날짜: $dateStr, 새 근무: $newShiftType');
    await txn.update(
      'shift_schedule',
      updatedSchedule.toMap(),
      where: 'id = ?',
      whereArgs: [updatedSchedule.id],
    );

    if (targetDates.isNotEmpty) {
      result = await regenerateFixedAlarmsForDatesTxn(
        txn: txn,
        schedule: updatedSchedule,
        dates: targetDates,
      );
    }
  });

  if (result != null) {
    for (var id in result!.cancelIds) {
      await AlarmService().cancelAlarm(id);
    }
    for (var s in result!.scheduled) {
      await AlarmService().scheduleAlarm(
        id: s.id,
        dateTime: s.dateTime,
        label: s.label,
        soundType: 'loud',
      );
    }
    print('🔵 알람 재계산: 대상 ${targetDates.length}일 (삭제: ${result!.cancelIds.length}, 생성: ${result!.scheduled.length})');
  } else {
    print('🔵 ${kAlarmRefreshWindowDays}일 이후 날짜라서 알람은 생성하지 않음 (자정 갱신 시 자동 생성됨)');
  }

  state = AsyncValue.data(updatedSchedule);
  WidgetRefreshService.refresh();  // ⭐ 홈 화면 위젯도 즉시 갱신
  FriendSyncService.instance.syncIfEnabled(updatedSchedule);  // ⭐ 친구공유 중이면 Firestore도 갱신

  print('✅ 스케줄 + 알람 변경 완료');
  try {
    await kAlarmChannel.invokeMethod('triggerGuardCheck');
    print('✅ Provider에서 AlarmGuardReceiver 트리거 완료');
  } catch (e) {
    print('⚠️ Provider에서 AlarmGuardReceiver 트리거 실패: $e');
  }
}
}