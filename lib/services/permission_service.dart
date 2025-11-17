import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 모든 필수 권한 요청
  Future<bool> requestAllPermissions() async {
    print('🔐 권한 요청 시작...');

    // 1. 알림 권한 (Android 13+)
    final notification = await _requestNotification();
    
    // 2. 정확한 알람 권한 (Android 12+)
    final alarm = await _requestExactAlarm();
    
    // 3. Overlay 권한 (화면 위 표시)
    final overlay = await _requestSystemAlertWindow();
    
    // 4. 배터리 최적화 제외 (선택)
    final battery = await _requestBatteryOptimization();

    final allGranted = notification && alarm && overlay;
    
    if (allGranted) {
      print('✅ 모든 필수 권한 허용됨');
    } else {
      print('⚠️ 일부 권한 거부됨');
      print('   알림: $notification');
      print('   정확한 알람: $alarm');
      print('   화면 위 표시: $overlay');
      print('   배터리 최적화: $battery');
    }

    return allGranted;
  }

  /// 알림 권한 요청
  Future<bool> _requestNotification() async {
    final status = await Permission.notification.request();
    print('   📢 알림 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 정확한 알람 권한 요청
  Future<bool> _requestExactAlarm() async {
    final status = await Permission.scheduleExactAlarm.request();
    print('   ⏰ 정확한 알람 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 화면 위 표시 권한 요청 (Overlay)
  Future<bool> _requestSystemAlertWindow() async {
    final status = await Permission.systemAlertWindow.request();
    print('   📱 화면 위 표시 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 배터리 최적화 제외 요청
  Future<bool> _requestBatteryOptimization() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    print('   🔋 배터리 최적화 제외: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 권한 상태 확인
  Future<Map<String, bool>> checkPermissions() async {
    return {
      'notification': await Permission.notification.isGranted,
      'exactAlarm': await Permission.scheduleExactAlarm.isGranted,
      'overlay': await Permission.systemAlertWindow.isGranted,
      'battery': await Permission.ignoreBatteryOptimizations.isGranted,
    };
  }

  /// 권한 설정 화면으로 이동
  Future<void> openSettings() async {
    await openAppSettings();
  }
}