import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 모든 필수 권한 요청
  Future<bool> requestAllPermissions() async {
    print('🔐 권한 요청 시작...');

    // 1. 알림 권한
    final notification = await _requestNotification();

    // 2. Overlay 권한 (다른 앱 위에 표시)
    final overlay = await _requestSystemAlertWindow();

    final allGranted = notification && overlay;

    if (allGranted) {
      print('✅ 모든 필수 권한 허용됨');
    } else {
      print('⚠️ 일부 권한 거부됨');
      print('   알림: $notification');
      print('   다른 앱 위에 표시: $overlay');
    }

    return allGranted;
  }

  /// 알림 권한 요청
  Future<bool> _requestNotification() async {
    final status = await Permission.notification.request();
    print('   📢 알림 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 화면 위 표시 권한 요청 (Overlay)
  Future<bool> _requestSystemAlertWindow() async {
    final status = await Permission.systemAlertWindow.request();
    print('   📱 다른 앱 위에 표시 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 권한 상태 확인
  Future<Map<String, bool>> checkPermissions() async {
    return {
      'notification': await Permission.notification.isGranted,
      'overlay': await Permission.systemAlertWindow.isGranted,
    };
  }

  /// 권한 설정 화면으로 이동
  Future<void> openSettings() async {
    await openAppSettings();
  }
}