import 'package:permission_handler/permission_handler.dart';
import '../constants/platform_channel.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  static const _platform = kAlarmChannel;

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

  /// ⭐ 2026-09-14 (출시전 감사 #13) - 허용/거부/확인 불가를 구분. 예전엔 채널 호출이 실패하면 true를
  /// 돌려서 실제 상태를 모르는데도 허용된 것처럼 보였음(경고 배너도 안 뜸).
  Future<ExactAlarmPermissionState> checkExactAlarmPermissionState() async {
    try {
      final result = await _platform.invokeMethod('checkExactAlarmPermission');
      if (result == true) return ExactAlarmPermissionState.granted;
      if (result == false) return ExactAlarmPermissionState.denied;
      print('⚠️ 정확한 알람 권한 확인 결과 형식 이상: $result');
      return ExactAlarmPermissionState.unknown;
    } catch (e) {
      print('⚠️ 정확한 알람 권한 확인 실패: $e');
      return ExactAlarmPermissionState.unknown;
    }
  }

  /// 정확한 알람 권한 통과 여부 - 확인 불가(unknown)는 첫 실행 권한 화면 등에서 사용자를 막지 않도록
  /// 통과로 취급(기존 동작 유지). 실제 상태를 보여줘야 하는 곳은 [checkExactAlarmPermissionState]를 쓸 것.
  Future<bool> checkExactAlarmPermission() async =>
      await checkExactAlarmPermissionState() != ExactAlarmPermissionState.denied;

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

/// 정확한 알람 권한 상태 (#13). unknown = Native 확인 호출 실패·형식 이상.
enum ExactAlarmPermissionState { granted, denied, unknown }
