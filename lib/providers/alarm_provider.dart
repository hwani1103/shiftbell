// lib/providers/alarm_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import 'package:flutter/services.dart';


// ⭐ 알람 관리 Provider (StateNotifier)
class AlarmNotifier extends StateNotifier<AsyncValue<List<Alarm>>> {
  // ⭐ MethodChannel 재사용 (매번 생성 방지)
  static const _platform = MethodChannel('com.example.shiftbell/alarm');

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
        await _platform.invokeMethod('triggerGuardCheck');
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
      // ⭐ 알람이 울리는 중인지 확인
      bool isRinging = false;
      try {
        isRinging = await _platform.invokeMethod('isAlarmRinging') ?? false;
        print('📊 알람 상태: ${isRinging ? "울림 중" : "울리기 전"}');
      } catch (e) {
        print('⚠️ 알람 상태 확인 실패: $e');
      }

      // ⭐ 이력 생성 정책:
      // - 알람 울림 중 삭제 → 'swiped' (알람 확인) 이력 생성
      // - 알람 울리기 전 삭제 (UI에서) → 이력 생성 안 함
      //   (20분 전 notification "끄기"는 Native에서 별도 처리)
      if (isRinging) {
        await DatabaseService.instance.deleteAlarm(id, dismissType: 'swiped', createHistory: true);
      } else {
        await DatabaseService.instance.deleteAlarm(id, createHistory: false);
      }
      await AlarmService().cancelAlarm(id);

      // ⭐ 알람 울리는 중이면 소리 중지
      if (isRinging) {
        try {
          await _platform.invokeMethod('stopAlarm');
          print('✅ 알람 소리 중지');
        } catch (e) {
          print('⚠️ 알람 소리 중지 실패: $e');
        }
      }

      // ⭐ Notification 삭제 (7777, 8888, 8889)
      try {
        await _platform.invokeMethod('cancelNotification');
        print('✅ Notification 삭제 완료 (8888, 8889)');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      // ⭐ CRITICAL FIX: shownNotifications 정리 (유령 Notification 방지)
      try {
        await _platform.invokeMethod('clearShownNotifications');
        print('✅ shownNotifications 정리 완료');
      } catch (e) {
        print('⚠️ shownNotifications 정리 실패: $e');
      }

      await _loadAlarms();
      print('✅ 알람 삭제 완료 (ID: $id, 울림 중: $isRinging)');
    } catch (e) {
      print('❌ 알람 삭제 실패: $e');
      rethrow;
    }
  }

  // 고정 알람 재생성 메서드
  Future<void> regenerateFixedAlarms(DateTime date, String shiftType) async {
    int deleteCount = 0;
    int createCount = 0;
    int failCount = 0;

    try {
      // 1단계: 기존 고정 알람 삭제 (개별 try-catch로 부분 실패 허용)
      // ⭐ 재생성 삭제는 이력 생성 안 함
      final existingAlarms = await DatabaseService.instance.getAlarmsByDate(date);
      for (var alarm in existingAlarms) {
        if (alarm.type == 'fixed') {
          try {
            await DatabaseService.instance.deleteAlarm(alarm.id!, createHistory: false);
            await AlarmService().cancelAlarm(alarm.id!);
            deleteCount++;
          } catch (e) {
            print('⚠️ 알람 삭제 실패 (ID: ${alarm.id}): $e');
            failCount++;
          }
        }
      }

      // 2단계: 새 알람 생성 (개별 try-catch로 부분 실패 허용)
      final templates = await DatabaseService.instance.getAlarmTemplates(shiftType);
      final createdTimes = <String>{};  // ⭐ 중복 시간 추적

      for (var template in templates) {
        try {
          // ⭐ 중복 시간 체크
          if (createdTimes.contains(template.time)) {
            print('⚠️ 중복 시간 스킵: ${template.time} (근무: $shiftType, 날짜: ${date.toString().split(' ')[0]})');
            continue;
          }

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

          createdTimes.add(template.time);  // ⭐ 생성된 시간 기록
          createCount++;
        } catch (e) {
          print('⚠️ 알람 생성 실패 (time: ${template.time}): $e');
          failCount++;
        }
      }

      await _loadAlarms();
      print('✅ 고정 알람 재생성 완료: $shiftType (삭제: $deleteCount, 생성: $createCount, 실패: $failCount)');

      try {
        await _platform.invokeMethod('triggerGuardCheck');
        print('✅ AlarmProvider에서 AlarmGuardReceiver 트리거 완료');
      } catch (e) {
        print('⚠️ AlarmProvider에서 AlarmGuardReceiver 트리거 실패: $e');
      }

      // ⭐ HIGH FIX: 실패가 있으면 에러 발생
      if (failCount > 0 && createCount == 0) {
        throw Exception('알람 재생성 실패: 모든 알람 생성 실패 (실패: $failCount)');
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

      // ⭐ 모든 Notification 삭제
      try {
        await _platform.invokeMethod('cancelAllNotifications');
        print('✅ 모든 Notification 삭제 완료');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      // ⭐ CRITICAL FIX: shownNotifications 정리 (유령 Notification 방지)
      try {
        await _platform.invokeMethod('clearShownNotifications');
        print('✅ shownNotifications 정리 완료');
      } catch (e) {
        print('⚠️ shownNotifications 정리 실패: $e');
      }

      // ⭐ HIGH FIX: AlarmGuardReceiver 트리거 (다음 웨이크업 스케줄링)
      try {
        await _platform.invokeMethod('triggerGuardCheck');
        print('✅ AlarmGuardReceiver 트리거 완료');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }

      await _loadAlarms();
      print('🗑️ 모든 알람 삭제 완료');
    } catch (e) {
      print('❌ 알람 삭제 실패: $e');
      rethrow;
    }
  }

  // ⭐ Production용: 모든 알람 완전 삭제 (템플릿 포함)
  Future<void> deleteAllAlarmsCompletely() async {
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

      // 3. DB에서 모든 알람 삭제
      await DatabaseService.instance.deleteAllAlarms();

      // 4. ⭐ 모든 알람 템플릿 삭제 (갱신 방지)
      await DatabaseService.instance.deleteAllAlarmTemplates();

      // 5. Notification 모두 삭제
      try {
        await _platform.invokeMethod('cancelAllNotifications');
        print('✅ 모든 Notification 삭제 완료');
      } catch (e) {
        print('⚠️ Notification 삭제 실패: $e');
      }

      // 5-1. ⭐ CRITICAL FIX: shownNotifications 정리 (유령 Notification 방지)
      try {
        await _platform.invokeMethod('clearShownNotifications');
        print('✅ shownNotifications 정리 완료');
      } catch (e) {
        print('⚠️ shownNotifications 정리 실패: $e');
      }

      // 6. AlarmGuardReceiver 취소
      try {
        await _platform.invokeMethod('cancelAlarmGuard');
        print('✅ AlarmGuardReceiver 취소 완료');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 취소 실패: $e');
      }

      await _loadAlarms();
      print('🗑️🔥 모든 알람 완전 삭제 완료 (템플릿 포함)');
    } catch (e) {
      print('❌ 알람 완전 삭제 실패: $e');
      rethrow;
    }
  }

  // 알람 타입 업데이트
  Future<void> updateAlarmType(int alarmId, int newTypeId) async {
    try {
      final db = await DatabaseService.instance.database;
      await db.update(
        'alarms',
        {'alarm_type_id': newTypeId},
        where: 'id = ?',
        whereArgs: [alarmId],
      );

      await _loadAlarms();
      print('✅ 알람 타입 변경 완료 (ID: $alarmId → 타입: $newTypeId)');
    } catch (e) {
      print('❌ 알람 타입 변경 실패: $e');
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