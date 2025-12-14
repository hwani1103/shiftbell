// lib/services/alarm_refresh_service.dart

import 'package:flutter/services.dart';
import 'database_service.dart';
import 'alarm_service.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import 'alarm_refresh_helper.dart';

class AlarmRefreshService {
  static final AlarmRefreshService instance = AlarmRefreshService._internal();
  AlarmRefreshService._internal();

  static const _platform = MethodChannel('com.example.shiftbell/alarm');
  bool _isRefreshing = false;
  
  /// 조건 체크 후 필요하면 갱신
  Future<void> refreshIfNeeded() async {
    if (_isRefreshing) {
      print('⏭️ 이미 갱신 중...');
      return;
    }
    
    try {
      _isRefreshing = true;
      
      // 갱신 필요 여부 체크
      final needsRefresh = await AlarmRefreshHelper.instance.needsRefresh();
      
      if (!needsRefresh) {
        print('⏭️ 갱신 스킵');
        return;
      }
      
      print('🔄 알람 갱신 시작...');
      
      await _refresh10DaysAlarms();
      
      // 갱신 완료 표시
      await AlarmRefreshHelper.instance.markRefreshed();
      
      print('✅ 알람 갱신 완료');
    } catch (e) {
      print('❌ 알람 갱신 실패: $e');
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// 강제 갱신 (조건 체크 없이)
  Future<void> forceRefresh() async {
    if (_isRefreshing) {
      print('⏭️ 이미 갱신 중...');
      return;
    }
    
    try {
      _isRefreshing = true;
      print('🔄 강제 갱신 시작...');
      
      await _refresh10DaysAlarms();
      await AlarmRefreshHelper.instance.markRefreshed();
      
      print('✅ 강제 갱신 완료');
    } catch (e) {
      print('❌ 강제 갱신 실패: $e');
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// 30일치 알람 재생성
  Future<void> _refresh10DaysAlarms() async {  // 30 → 10
  print('🔄 10일치 알람 갱신 시작...');  // 로그 수정

  // 0. 20분 전 Notification 삭제 (유령 Notification 방지)
  try {
    await _platform.invokeMethod('cancelNotification');
  } catch (e) {
    print('⚠️ Notification 삭제 실패: $e');
  }

  // 1. 기존 Native 알람 전부 취소
  final existingAlarms = await DatabaseService.instance.getAllAlarms();
  for (var alarm in existingAlarms) {
    if (alarm.id != null) {
      await AlarmService().cancelAlarm(alarm.id!);
    }
  }
  
  // 2. DB 알람 전부 삭제 (이력은 유지!)
  await DatabaseService.instance.deleteAllAlarmsOnly();
  
  print('🗑️ 기존 알람 전부 삭제');
  
  // 3. 스케줄 조회
  final schedule = await DatabaseService.instance.getShiftSchedule();
  if (schedule == null) {
    print('⚠️ 스케줄 없음 - 갱신 중단');
    return;
  }
  
  if (!schedule.isRegular) {
    print('⚠️ 불규칙 근무 - 자동 갱신 안 함');
    return;
  }
  
  // 4. 템플릿 조회
  final templates = await DatabaseService.instance.getAllAlarmTemplates();
  if (templates.isEmpty) {
    print('⚠️ 템플릿 없음 - 갱신 중단');
    return;
  }
  
  // 5. ⭐ 10일치 생성
  final List<Alarm> newAlarms = [];
  final today = DateTime.now();
  
  for (var i = 0; i < 2; i++) {  // ⭐ 테스트용: 10 → 2
    final date = today.add(Duration(days: i));
    final shiftType = schedule.getShiftForDate(date);
    
    if (shiftType == '미설정') continue;
    
    final shiftTemplates = templates.where((t) => t.shiftType == shiftType).toList();
    
    for (var template in shiftTemplates) {
      final timeParts = template.time.split(':');
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      
      // 과거 알람 스킵
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
      
      newAlarms.add(alarm);
    }
  }
  
  print('📝 생성할 알람: ${newAlarms.length}개');
  
  if (newAlarms.isEmpty) {
    print('⚠️ 생성할 알람 없음');
    return;
  }
  
  // 6. DB 저장
  await DatabaseService.instance.insertAlarmsInBatch(newAlarms);
  
  // 7. 저장된 알람 다시 읽어서 Native 등록
  final savedAlarms = await DatabaseService.instance.getAllAlarms();
  int registeredCount = 0;
  
  for (var alarm in savedAlarms) {
    if (alarm.date != null && alarm.date!.isAfter(DateTime.now())) {
      await AlarmService().scheduleAlarm(
        id: alarm.id!,
        dateTime: alarm.date!,
        label: alarm.shiftType ?? '알람',
        soundType: 'loud',
      );
      registeredCount++;
    }
  }
  
  print('✅ ${registeredCount}개 알람 Native 등록 완료');
}
}