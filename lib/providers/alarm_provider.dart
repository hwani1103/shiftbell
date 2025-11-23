// lib/providers/alarm_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import 'package:flutter/services.dart';


// ⭐ 알람 관리 Provider (StateNotifier)
class AlarmNotifier extends StateNotifier<AsyncValue<List<Alarm>>> {
  AlarmNotifier() : super(const AsyncValue.loading()) {
    _loadAlarms();
  }

  Future<void> _loadAlarms() async {
    state = const AsyncValue.loading();
    try {
      final alarms = await DatabaseService.instance.getAllAlarms();
      state = AsyncValue.data(alarms);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  // 알람 추가 메서드
  Future<void> addAlarm(Alarm alarm) async {
    try {
      final dbId = await DatabaseService.instance.insertAlarm(alarm);
      
      if (alarm.date != null) {
        await AlarmService().scheduleAlarm(
          id: dbId,
          dateTime: alarm.date!,
          label: alarm.shiftType ?? '알람',
          soundType: 'loud',
        );
      }
      
      try {
        await MethodChannel('com.example.shiftbell/alarm')
            .invokeMethod('triggerGuardCheck');
        print('✅ AlarmGuardReceiver 트리거 완료');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }
      
      await _loadAlarms();
      print('✅ 알람 추가 완료 (ID: $dbId)');
    } catch (e) {
      print('❌ 알람 추가 실패: $e');
      rethrow;
    }
  }

  Future<void> deleteAlarm(int id, DateTime? date) async {
    try {
      await DatabaseService.instance.deleteAlarm(id);
      await AlarmService().cancelAlarm(id);
      
      await _loadAlarms();
      print('✅ 알람 삭제 완료 (ID: $id)');
    } catch (e) {
      print('❌ 알람 삭제 실패: $e');
      rethrow;
    }
  }

  // 고정 알람 재생성 메서드
  Future<void> regenerateFixedAlarms(DateTime date, String shiftType) async {
    try {
      final existingAlarms = await DatabaseService.instance.getAlarmsByDate(date);
      for (var alarm in existingAlarms) {
        if (alarm.type == 'fixed') {
          await DatabaseService.instance.deleteAlarm(alarm.id!);
          await AlarmService().cancelAlarm(alarm.id!);
        }
      }
      
      final templates = await DatabaseService.instance.getAlarmTemplates(shiftType);
      for (var template in templates) {
        final timeParts = template.time.split(':');
        final alarmTime = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        
        if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) {
          continue;
        }
        
        final alarm = Alarm(
          time: template.time,
          date: alarmTime,
          type: 'fixed',
          alarmTypeId: template.alarmTypeId,
          shiftType: shiftType,
        );
        
        final dbId = await DatabaseService.instance.insertAlarm(alarm);
        
        await AlarmService().scheduleAlarm(
          id: dbId,
          dateTime: alarmTime,
          label: shiftType,
          soundType: 'loud',
        );
      }
      
      await _loadAlarms();
      print('✅ 고정 알람 재생성 완료: $shiftType');
      try {
      await MethodChannel('com.example.shiftbell/alarm').invokeMethod('triggerGuardCheck');
      print('✅ AlarmProvider에서 AlarmGuardReceiver 트리거 완료');
    } catch (e) {
      print('⚠️ AlarmProvider에서 AlarmGuardReceiver 트리거 실패: $e');
    }
    } catch (e) {
      print('❌ 고정 알람 재생성 실패: $e');
      rethrow;
    }
  }

  Future<void> deleteAllAlarms() async {
    try {
      final alarms = await DatabaseService.instance.getAllAlarms();
      
      for (var alarm in alarms) {
        await AlarmService().cancelAlarm(alarm.id!);
        print('✅ Native 알람 취소: DB ID ${alarm.id}');
      }
      
      await DatabaseService.instance.deleteAllAlarms();
      
      await _loadAlarms();
      print('🗑️ 모든 알람 삭제 완료');
    } catch (e) {
      print('❌ 알람 삭제 실패: $e');
      rethrow;
    }
  }

  // 수동 새로고침
  Future<void> refresh() async {
    await _loadAlarms();
  }
}

// AlarmNotifier Provider
final alarmNotifierProvider = StateNotifierProvider<AlarmNotifier, AsyncValue<List<Alarm>>>((ref) {
  return AlarmNotifier();
});

// ⭐ 다음 알람 Provider (alarmNotifierProvider 변경 자동 감지)
final nextAlarmProvider = Provider<AsyncValue<Alarm?>>((ref) {
  final alarmsAsync = ref.watch(alarmNotifierProvider);
  
  return alarmsAsync.whenData((alarms) {
    if (alarms.isEmpty) return null;
    
    // 미래 시간 알람만 필터링
    final now = DateTime.now();
    final futureAlarms = alarms
        .where((a) => a.date != null && a.date!.isAfter(now))
        .toList();
    
    if (futureAlarms.isEmpty) return null;
    
    // 가장 빠른 알람 반환
    futureAlarms.sort((a, b) => a.date!.compareTo(b.date!));
    return futureAlarms.first;
  });
});

// 특정 날짜의 알람 목록 Provider
final alarmsForDateProvider = FutureProvider.family<List<Alarm>, DateTime>((ref, date) async {
  return await DatabaseService.instance.getAlarmsByDate(date);
});