// lib/providers/schedule_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm_template.dart';
import '../models/alarm.dart';
import 'package:flutter/services.dart';


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
    );
    
    state = AsyncValue.data(savedSchedule);
  } catch (e, stack) {
    state = AsyncValue.error(e, stack);
    rethrow;
  }
}

  Future<void> updateSchedule(ShiftSchedule schedule) async {
    try {
      await DatabaseService.instance.updateShiftSchedule(schedule);
      state = AsyncValue.data(schedule);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
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

      final adjustedStartDate = DateTime(
        currentSchedule.startDate!.year,
        currentSchedule.startDate!.month,
        currentSchedule.startDate!.day,
      );
      final targetDate = DateTime(date.year, date.month, date.day);
      final daysDiff = targetDate.difference(adjustedStartDate).inDays;
      final index = ((currentSchedule.todayIndex! + daysDiff) % 
                    currentSchedule.pattern!.length + 
                    currentSchedule.pattern!.length) % 
                    currentSchedule.pattern!.length;

      currentSchedule.pattern![index] = newShiftType;
    } else {
      currentSchedule.assignedDates ??= {};
      currentSchedule.assignedDates![dateStr] = newShiftType;
    }

    await updateSchedule(currentSchedule);
  }

  Future<void> bulkAssignShift(List<DateTime> dates, String shiftType) async {
    final currentSchedule = state.value;
    if (currentSchedule == null) return;

    for (var date in dates) {
      final dateStr = date.toIso8601String().split('T')[0];

      // ⭐ 규칙적/불규칙 관계없이 assignedDates에 예외로 저장
      // (패턴을 직접 수정하면 같은 인덱스의 모든 날짜가 바뀜)
      currentSchedule.assignedDates ??= {};
      currentSchedule.assignedDates![dateStr] = shiftType;
    }

    await updateSchedule(currentSchedule);
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
      const platform = MethodChannel('com.example.shiftbell/alarm');
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
      await DatabaseService.instance.deleteAllAlarms();  // ⭐ 전체 삭제는 이력 생성 없이 클린 스타트

      final db = await DatabaseService.instance.database;
      await db.delete('shift_schedule');
      await db.delete('shift_alarm_templates');

      state = const AsyncValue.data(null);
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
  
  List<int> cancelIds = [];
  List<Map<String, dynamic>> scheduleData = [];
  
  await db.transaction((txn) async {
    final dateStr = date.toIso8601String().split('T')[0];
    
    print('🔵 날짜: $dateStr, 새 근무: $newShiftType');

    // ⭐ 규칙적이든 불규칙이든 assignedDates에 예외로 저장
    currentSchedule.assignedDates ??= {};
    currentSchedule.assignedDates![dateStr] = newShiftType;

    await txn.update(
      'shift_schedule',
      currentSchedule.toMap(),
      where: 'id = ?',
      whereArgs: [currentSchedule.id],
    );

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

  state = AsyncValue.data(currentSchedule);
  
  print('✅ 스케줄 + 알람 변경 완료');
  try {
    await MethodChannel('com.example.shiftbell/alarm').invokeMethod('triggerGuardCheck');
    print('✅ Provider에서 AlarmGuardReceiver 트리거 완료');
  } catch (e) {
    print('⚠️ Provider에서 AlarmGuardReceiver 트리거 실패: $e');
  }
}
}