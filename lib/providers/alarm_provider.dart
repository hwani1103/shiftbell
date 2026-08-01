// lib/providers/alarm_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm.dart';
import '../models/alarm_template.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import 'package:flutter/services.dart';


// ⭐ 알람 관리 Provider (StateNotifier)
class AlarmNotifier extends StateNotifier<AsyncValue<List<Alarm>>> {
  // ⭐ MethodChannel 재사용 (매번 생성 방지)
  static const _platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  AlarmNotifier() : super(const AsyncValue.loading()) {
    _loadAlarms();
  }

  // ⭐ 겹쳐서 들어오는 refresh() 호출을 하나로 합침 (database getter와 동일한
  // Completer 패턴). "등록된 모든 알람 보기" 시트를 빠르게 열고 닫기를 반복하면
  // 열 때마다 _loadAlarms()가 새로 트리거되는데, 예전엔 각 호출이 독립적으로
  // state=loading → state=data를 순서 보장 없이 덮어써서 화면이 순간적으로
  // 빈 목록으로 보이는 경우가 있었음. 이미 로드 중이면 새로 또 시작하지 않고
  // 진행 중인 걸 같이 기다리게 해서 이 경쟁을 없앰.
  Completer<void>? _loadCompleter;

  Future<void> _loadAlarms() async {
    if (_loadCompleter != null) {
      return _loadCompleter!.future;
    }
    final completer = Completer<void>();
    _loadCompleter = completer;

    // ⭐ 이미 데이터가 있으면 loading으로 안 바꿈 - next_alarm_tab이 몇 초마다
    // 자동으로 refresh()를 호출하는데, 매번 loading 상태를 거치면 화면이
    // SizedBox(빈 화면)로 깜빡였다가 돌아오는 것처럼 보임. 최초 로드일 때만
    // loading을 보여주고, 이후 재조회는 기존 데이터를 유지한 채 조용히 갱신.
    if (state is! AsyncData) {
      state = const AsyncValue.loading();
    }
    try {
      final alarms = await DatabaseService.instance.getAllAlarms();
      state = AsyncValue.data(alarms);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    } finally {
      _loadCompleter = null;
      completer.complete();
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

      // ⭐ 이력 생성 정책: 삭제 사유와 무관하게 항상 이력을 남김 (절대 삭제되지 않아야 함)
      // - 알람 울림 중 삭제 → 'swiped' (알람 확인)
      // - 알람 울리기 전 삭제 (UI에서) → 'cancelled_before_ring' (알람 제거)
      if (isRinging) {
        await DatabaseService.instance.deleteAlarm(id, dismissType: 'swiped', createHistory: true);
      } else {
        await DatabaseService.instance.deleteAlarm(id, dismissType: 'cancelled_before_ring', createHistory: true);
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
      // ⭐ 10일 이후 체크 (DST 안전한 계산)
      final now = DateTime.now();
      final daysDiff = julianDayNumber(date.year, date.month, date.day) -
          julianDayNumber(now.year, now.month, now.day);

      if (daysDiff >= 10) {
        print('🔵 10일 이후 날짜라서 알람은 생성하지 않음 (날짜: ${date.toString().split(' ')[0]}, 근무: $shiftType)');
        return;
      }

      // ⭐ CRITICAL FIX: 삭제+재생성을 하나의 DB 트랜잭션으로 묶음. 예전엔 삭제와
      // 생성이 각각 독립된 DB 호출이라, 그 사이에 이 날짜에 대해 "삭제됐지만 아직
      // 새로 안 만들어진" 순간이 실제로 노출됐음 - 그 틈에 Native 갱신 엔진이나
      // 다른 트리거가 끼어들면 이 날짜를 잘못 재계산할 수 있었음
      // (settings_tab.dart의 템플릿 일괄 저장에서 고친 것과 동일한 원인/패턴).
      // 네이티브 알람 취소/재등록은 OS 호출이라 트랜잭션 밖에서 순서대로 처리함.
      final db = await DatabaseService.instance.database;
      final dateStr = date.toIso8601String().split('T')[0];
      List<int> cancelIds = [];
      List<Map<String, dynamic>> scheduleData = [];

      await db.transaction((txn) async {
        // 1단계: 기존 고정 알람 삭제 + 이력 기록
        final existingAlarms = await txn.query(
          'alarms',
          where: 'date LIKE ? AND type = ?',
          whereArgs: ['$dateStr%', 'fixed'],
        );

        for (var alarmMap in existingAlarms) {
          final alarm = Alarm.fromMap(alarmMap);
          cancelIds.add(alarm.id!);

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
          deleteCount++;
        }

        // 2단계: 새 알람 생성 (+ 생성 이력 기록)
        final templateMaps = await txn.query(
          'shift_alarm_templates',
          where: 'shift_type = ?',
          whereArgs: [shiftType],
        );
        final createdTimes = <String>{};  // ⭐ 중복 시간 추적

        for (var templateMap in templateMaps) {
          final template = AlarmTemplate.fromMap(templateMap);

          // ⭐ 중복 시간 체크
          if (createdTimes.contains(template.time)) {
            print('⚠️ 중복 시간 스킵: ${template.time} (근무: $shiftType, 날짜: $dateStr)');
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

          final dbId = await txn.insert('alarms', alarm.toMap());
          await DatabaseService.instance.logAlarmCreation(txn, dbId, alarm, 'auto');

          scheduleData.add({'id': dbId, 'dateTime': alarmTime, 'label': shiftType});
          createdTimes.add(template.time);
          createCount++;
        }
      });

      // 트랜잭션 커밋 후 네이티브 취소/재등록
      for (var id in cancelIds) {
        try {
          await AlarmService().cancelAlarm(id);
        } catch (e) {
          print('⚠️ 네이티브 알람 취소 실패 (ID: $id): $e');
        }
      }
      for (var data in scheduleData) {
        try {
          await AlarmService().scheduleAlarm(
            id: data['id'],
            dateTime: data['dateTime'],
            label: data['label'],
            soundType: 'loud',
          );
        } catch (e) {
          print('⚠️ 네이티브 알람 등록 실패 (ID: ${data['id']}): $e');
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