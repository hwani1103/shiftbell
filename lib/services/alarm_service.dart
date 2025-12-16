import 'package:flutter/services.dart';

@pragma('vm:entry-point')
class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  static const platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  /// 알람 초기화
  Future<void> initialize() async {
    print('✅ AlarmService 초기화 완료');
  }

  /// 알람 등록
  Future<void> scheduleAlarm({
    required int id,
    required DateTime dateTime,
    required String label,
    String soundType = 'loud',
  }) async {
    try {
      // Native 방식으로 등록
      await platform.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'timestamp': dateTime.millisecondsSinceEpoch,
        'label': label,
        'soundType': soundType,
      });

      print('✅ 알람 등록 완료: $label - ${dateTime.toString()}');
      print('   ID: $id, 사운드: $soundType');
    } catch (e) {
      print('❌ 알람 등록 실패: $e');
      rethrow;
    }
  }

  /// 알람 취소
  Future<void> cancelAlarm(int id) async {
    try {
      await platform.invokeMethod('cancelNativeAlarm', {'id': id});
      print('✅ 알람 취소: ID $id');
    } catch (e) {
      print('❌ 알람 취소 실패: $e');
      rethrow;
    }
  }

  /// 알람 중지
  Future<void> stopAlarm() async {
    try {
      await platform.invokeMethod('stopAlarm');
      print('✅ 알람 중지');
    } catch (e) {
      print('❌ 알람 중지 실패: $e');
    }
  }

  /// 테스트용: 5초 후 알람
  Future<void> scheduleTestAlarm({
    String label = '테스트 알람',
    String soundType = 'loud',
  }) async {
    final testTime = DateTime.now().add(Duration(seconds: 5));
    await scheduleAlarm(
      id: 99999,
      dateTime: testTime,
      label: label,
      soundType: soundType,
    );
    print('🧪 테스트 알람: 5초 후 울림');
  }
  /// Overlay 권한 요청
  Future<void> requestOverlayPermission() async {
    try {
      await platform.invokeMethod('requestOverlayPermission');
      print('✅ Overlay 권한 요청');
    } catch (e) {
      print('❌ Overlay 권한 요청 실패: $e');
    }
  }
  
  /// Overlay 권한 체크
  Future<bool> checkOverlayPermission() async {
    try {
      final hasPermission = await platform.invokeMethod('checkOverlayPermission');
      print('🔍 Overlay 권한: ${hasPermission ? "있음" : "없음"}');
      return hasPermission ?? false;
    } catch (e) {
      print('❌ Overlay 권한 체크 실패: $e');
      return false;
    }
  }
}
