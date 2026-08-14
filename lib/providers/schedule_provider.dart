// lib/providers/schedule_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm_template.dart';
import '../models/alarm.dart';
import 'package:flutter/services.dart';
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
      const platform = MethodChannel('com.hwani1103.shiftbell/alarm');
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

  List<int> cancelIds = [];
  List<Map<String, dynamic>> scheduleData = [];

  await db.transaction((txn) async {
    print('🔵 날짜: $dateStr, 새 근무: $newShiftType');

    await txn.update(
      'shift_schedule',
      updatedSchedule.toMap(),
      where: 'id = ?',
      whereArgs: [updatedSchedule.id],
    );

    // ⭐ 10일 이후 체크 (DST 안전한 계산)
    final now = DateTime.now();
    final daysDiff = julianDayNumber(date.year, date.month, date.day) -
        julianDayNumber(now.year, now.month, now.day);

    if (daysDiff >= kAlarmRefreshWindowDays) {
      print('🔵 ${kAlarmRefreshWindowDays}일 이후 날짜라서 알람은 생성하지 않음 (자정 갱신 시 자동 생성됨)');
      return;  // assignedDates에만 저장하고 종료
    }

    final existingAlarms = await txn.query(
      'alarms',
      where: 'date LIKE ? AND type = ?',
      whereArgs: ['${dateStr}%', 'fixed'],
    );

    print('🔵 삭제할 알람: ${existingAlarms.length}개');

    for (var alarmMap in existingAlarms) {
      final alarm = Alarm.fromMap(alarmMap);
      print('  - 삭제: ${alarm.time}');
      cancelIds.add(alarm.id!);

      // ⭐ 근무 변경으로 알람이 무효화됐다는 이력을 남김 (삭제만 하고 끝내지 않음)
      if (alarm.date != null) {
        await txn.insert('alarm_history', {
          'alarm_id': alarm.id,
          'scheduled_time': alarm.time,
          'scheduled_date': alarm.date!.toIso8601String(),
          'actual_ring_time': DateTime.now().toIso8601String(),
          'dismiss_type': 'superseded',
          'snooze_count': 0,
          'shift_type': alarm.shiftType,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await txn.delete('alarms', where: 'id = ?', whereArgs: [alarm.id]);
    }

    final templates = await txn.query(
      'shift_alarm_templates',
      where: 'shift_type = ?',
      whereArgs: [newShiftType],
    );

    print('🔵 템플릿 조회: ${templates.length}개 (근무: $newShiftType)');

    for (var templateMap in templates) {
      final template = AlarmTemplate.fromMap(templateMap);
      print('  + 템플릿: ${template.time}');

      final timeParts = template.time.split(':');
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );

      print('    알람 시간: $alarmTime, 현재: ${DateTime.now()}');

      if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) {
        print('    ❌ 과거 시간이라 스킵');
        continue;
      }

      final alarm = Alarm(
        time: template.time,
        date: alarmTime,
        type: 'fixed',
        alarmTypeId: template.alarmTypeId,
        shiftType: newShiftType,
      );

      final dbId = await txn.insert('alarms', alarm.toMap());
      await DatabaseService.instance.logAlarmCreation(txn, dbId, alarm, 'auto');
      print('    ✅ 알람 생성: ID $dbId');

      scheduleData.add({
        'id': dbId,
        'dateTime': alarmTime,
        'label': newShiftType,
      });
    }

    print('🔵 생성 예정 알람: ${scheduleData.length}개');
  });

  for (var id in cancelIds) {
    await AlarmService().cancelAlarm(id);
  }
  
  for (var data in scheduleData) {
    await AlarmService().scheduleAlarm(
      id: data['id'],
      dateTime: data['dateTime'],
      label: data['label'],
      soundType: 'loud',
    );
  }

  state = AsyncValue.data(updatedSchedule);
  WidgetRefreshService.refresh();  // ⭐ 홈 화면 위젯도 즉시 갱신
  FriendSyncService.instance.syncIfEnabled(updatedSchedule);  // ⭐ 친구공유 중이면 Firestore도 갱신

  print('✅ 스케줄 + 알람 변경 완료');
  try {
    await MethodChannel('com.hwani1103.shiftbell/alarm').invokeMethod('triggerGuardCheck');
    print('✅ Provider에서 AlarmGuardReceiver 트리거 완료');
  } catch (e) {
    print('⚠️ Provider에서 AlarmGuardReceiver 트리거 실패: $e');
  }
}
}