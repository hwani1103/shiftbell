import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  static const _platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  /// 모든 필수 권한 요청
  Future<bool> requestAllPermissions() async {
    print('🔐 권한 요청 시작...');

    // 1. 알림 권한
    final notification = await _requestNotification();

    // 2. Overlay 권한 (다른 앱 위에 표시)
    final overlay = await _requestSystemAlertWindow();

    // 3. 정확한 알람 권한 - 이미 허용되어 있으면(대부분의 경우) 설정 화면으로
    // 안 보내고 그냥 넘어감. 진짜 꺼져있을 때만 설정 화면으로 이동시킴.
    final exactAlarm = await _requestExactAlarm();

    final allGranted = notification && overlay && exactAlarm;

    if (allGranted) {
      print('✅ 모든 필수 권한 허용됨');
    } else {
      print('⚠️ 일부 권한 거부됨');
      print('   알림: $notification');
      print('   다른 앱 위에 표시: $overlay');
      print('   정확한 알람: $exactAlarm');
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

  /// 정확한 알람 권한 요청 (이미 허용돼 있으면 설정 화면 안 띄우고 바로 통과)
  Future<bool> _requestExactAlarm() async {
    final alreadyGranted = await checkExactAlarmPermission();
    if (alreadyGranted) {
      print('   ⏰ 정확한 알람 권한: 이미 허용됨');
      return true;
    }

    await requestExactAlarmPermission();
    // 설정 화면은 비동기로 열리고 사용자가 돌아올 때까지 알 수 없으므로,
    // 여기서는 "요청은 보냈다"는 의미로 현재 상태를 다시 확인해서 반환
    final result = await checkExactAlarmPermission();
    print('   ⏰ 정확한 알람 권한: ${result ? "허용" : "거부"}');
    return result;
  }

  /// 정확한 알람 권한 상태 확인
  Future<bool> checkExactAlarmPermission() async {
    try {
      final result = await _platform.invokeMethod('checkExactAlarmPermission');
      return result == true;
    } catch (e) {
      print('⚠️ 정확한 알람 권한 확인 실패: $e');
      return true; // 확인 자체가 실패하면 경고 배너로 사용자를 막지 않도록 보수적으로 true
    }
  }

  /// 정확한 알람 권한 설정 화면 열기
  Future<void> requestExactAlarmPermission() async {
    try {
      await _platform.invokeMethod('requestExactAlarmPermission');
    } catch (e) {
      print('⚠️ 정확한 알람 권한 요청 실패: $e');
    }
  }

  /// 권한 상태 확인
  Future<Map<String, bool>> checkPermissions() async {
    return {
      'notification': await Permission.notification.isGranted,
      'overlay': await Permission.systemAlertWindow.isGranted,
      'exactAlarm': await checkExactAlarmPermission(),
    };
  }

  /// 권한 설정 화면으로 이동
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
