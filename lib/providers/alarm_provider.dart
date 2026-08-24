// lib/providers/alarm_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../services/alarm_generation_service.dart';
import 'package:flutter/services.dart';
import '../constants/alarm_limits.dart';
import '../constants/platform_channel.dart';


// ⭐ 알람 관리 Provider (StateNotifier)
class AlarmNotifier extends StateNotifier<AsyncValue<List<Alarm>>> {
  // ⭐ MethodChannel 재사용 (매번 생성 방지)
  static const _platform = kAlarmChannel;

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

  // ⭐ 고정 알람 재생성 - 근무가 배정된 날짜 하나가 바뀌면, "전날/당일/다음날"
  // 오프셋 알람이 있을 수 있어서 영향을 받는 실제 알람 날짜는 [date-1, date, date+1]
  // 세 개임(datesAffectedByShiftChange). 각 날짜는 alarm_generation_service.dart의
  // computeDesiredFixedAlarmsForDate()로 그 날짜 기준 세 근무(전날/당일/다음날 배정)의
  // 템플릿을 다시 계산해서 델타를 적용함 - 예전처럼 "이 날짜엔 이 근무 하나"가
  // 아니라 [schedule]에서 매번 다시 읽으므로 shiftType 파라미터는 더 이상 필요 없음
  // (calendar_tab.dart의 달력 일괄 배정에서 근무를 바꾼 "직후"의 schedule을 넘겨야 함).
  Future<void> regenerateAlarmsAroundDate(DateTime date, ShiftSchedule schedule) async {
    await regenerateAlarmsAroundDates([date], schedule);
  }

  // ⭐ 여러 날짜를 한꺼번에(일괄 배정) 바꿀 때 쓰는 버전 - 각 원본 날짜의 ±1일을
  // 전부 합집합으로 모아서 겹치는 날짜를 중복 계산하지 않고 트랜잭션 하나로 처리함.
  Future<void> regenerateAlarmsAroundDates(Iterable<DateTime> originDates, ShiftSchedule schedule) async {
    try {
      final db = await DatabaseService.instance.database;

      // ⭐ 10일 창을 벗어나는 날짜는 스킵 (DST 안전한 계산) - 날짜별로 개별 판단.
      final now = DateTime.now();
      final targetDates = originDates
          .expand((d) => datesAffectedByShiftChange(d))
          .where((d) {
            final daysDiff = julianDayNumber(d.year, d.month, d.day) -
                julianDayNumber(now.year, now.month, now.day);
            return daysDiff < kAlarmRefreshWindowDays;
          })
          .toSet();

      if (targetDates.isEmpty) {
        print('🔵 ${kAlarmRefreshWindowDays}일 창 밖 - 알람 재계산 스킵');
        return;
      }

      final result = await regenerateFixedAlarmsForDates(
        db: db,
        schedule: schedule,
        dates: targetDates,
      );

      int failCount = 0;
      for (var id in result.cancelIds) {
        try {
          await AlarmService().cancelAlarm(id);
        } catch (e) {
          print('⚠️ 네이티브 알람 취소 실패 (ID: $id): $e');
        }
      }
      for (var s in result.scheduled) {
        try {
          await AlarmService().scheduleAlarm(
            id: s.id,
            dateTime: s.dateTime,
            label: s.label,
            soundType: 'loud',
          );
        } catch (e) {
          print('⚠️ 네이티브 알람 등록 실패 (ID: ${s.id}): $e');
          failCount++;
        }
      }

      await _loadAlarms();
      print('✅ 고정 알람 재생성 완료: 대상 ${targetDates.length}일 (삭제: ${result.cancelIds.length}, 생성: ${result.scheduled.length}, 실패: $failCount)');

      try {
        await _platform.invokeMethod('triggerGuardCheck');
        print('✅ AlarmProvider에서 AlarmGuardReceiver 트리거 완료');
      } catch (e) {
        print('⚠️ AlarmProvider에서 AlarmGuardReceiver 트리거 실패: $e');
      }

      if (failCount > 0 && result.scheduled.isEmpty) {
        // ⭐ 영어 현지화: 이 메시지는 UI에 그대로 노출된 적 없음(호출부가 항상
        // catch해서 자체 에러 문구를 보여줌) - 그래도 로그/크래시 리포트에서 읽는
        // 사람 기준으로 개발자용 예외 메시지는 관례상 영어로 통일.
        throw Exception('Failed to regenerate fixed alarms: all $failCount attempt(s) failed');
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