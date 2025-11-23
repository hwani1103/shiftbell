// lib/services/alarm_refresh_helper.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class AlarmRefreshHelper {
  static final AlarmRefreshHelper instance = AlarmRefreshHelper._internal();
  AlarmRefreshHelper._internal();
  
  static const String KEY_LAST_REFRESH = 'last_alarm_refresh';
  
  /// 갱신이 필요한지 체크
  Future<bool> needsRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. 재부팅 감지 (무조건 갱신)
      if (await _isRebootDetected(prefs)) {
        print('🔄 갱신 필요: 재부팅 감지됨');
        return true;
      }
      
      // 2. ⭐ 날짜 변경 감지 (하루 1회 갱신)
      if (await _isDateChanged(prefs)) {
        print('🔄 갱신 필요: 날짜 변경됨');
        return true;
      }
      
      // 3. 알람 비어있음
      if (await _isAlarmEmpty()) {
        print('🔄 갱신 필요: 알람 없음');
        return true;
      }
      
      print('✅ 갱신 불필요 (오늘 이미 갱신됨)');
      return false;
    } catch (e) {
      print('❌ 갱신 체크 실패: $e');
      return true;
    }
  }
  
  /// 재부팅 감지
  Future<bool> _isRebootDetected(SharedPreferences prefs) async {
    final savedBootTime = prefs.getInt('system_boot_time') ?? 0;
    final lastBootTime = prefs.getInt('last_boot_time') ?? 0;
    
    if (savedBootTime > lastBootTime) {
      print('  - 재부팅 감지');
      return true;
    }
    
    return false;
  }
  
  /// ⭐ 날짜 변경 감지
  Future<bool> _isDateChanged(SharedPreferences prefs) async {
  final lastRefresh = prefs.getInt(KEY_LAST_REFRESH) ?? 0;
  
  if (lastRefresh == 0) {
    print('  - 첫 실행');
    
    // ⭐ 첫 실행이면 현재 시각을 저장하고 갱신 스킵
    await markRefreshed();
    return false;  // ⭐ false로 변경!
  }
  
  final lastDate = DateTime.fromMillisecondsSinceEpoch(lastRefresh);
  final today = DateTime.now();
  
  final dateChanged = lastDate.year != today.year ||
                     lastDate.month != today.month ||
                     lastDate.day != today.day;
  
  if (dateChanged) {
    print('  - 마지막 갱신: ${lastDate.year}-${lastDate.month}-${lastDate.day}');
    print('  - 현재 날짜: ${today.year}-${today.month}-${today.day}');
  }
  
  return dateChanged;
}
  
  /// 알람 비어있는지
  Future<bool> _isAlarmEmpty() async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    final futureAlarms = alarms.where((a) => 
      a.date != null && a.date!.isAfter(DateTime.now())
    ).toList();
    
    print('  - 미래 알람 개수: ${futureAlarms.length}');
    
    return futureAlarms.isEmpty;
  }
  
  /// 갱신 완료 후 호출
  Future<void> markRefreshed() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await prefs.setInt(KEY_LAST_REFRESH, now);
    
    // 현재 부팅 시각도 저장
    final bootTime = prefs.getInt('system_boot_time') ?? now;
    await prefs.setInt('last_boot_time', bootTime);
    
    final date = DateTime.fromMillisecondsSinceEpoch(now);
    print('✅ 갱신 완료 기록: ${date.year}-${date.month}-${date.day}');
  }
  
  /// 시스템 부팅 시각 저장
  Future<void> saveBootTime(int bootTimeMillis) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('system_boot_time', bootTimeMillis);
  }
}