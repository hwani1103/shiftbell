// lib/services/widget_refresh_service.dart
//
// ⭐ 홈 화면 캘린더 위젯 즉시 갱신 요청. 위젯은 항상 그 순간 DB를 직접 읽어서
// 그리기 때문에(별도 캐시 없음) 저장 자체는 이미 최신인데, "지금 화면에 붙어있는
// 위젯"을 다시 그리라고 깨워주는 역할만 함. 실패해도 스케줄 저장 자체를 막으면
// 안 되므로 항상 non-throwing - 위젯이 없거나 갱신이 실패해도 무시하고 넘어감
// (다음 자정 하트비트 때 어차피 다시 그려짐, AlarmGuardReceiver.kt 참고).
import 'package:flutter/services.dart';

class WidgetRefreshService {
  static const _platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  static Future<void> refresh() async {
    try {
      await _platform.invokeMethod('refreshCalendarWidget');
    } catch (e) {
      print('⚠️ 위젯 갱신 요청 실패 (무시): $e');
    }
  }

  // ⭐ 위젯은 앱의 Flutter SharedPreferences(theme_mode)를 직접 못 읽음 - 앱을
  // 껐다 켜지 않아도 위젯이 즉시 라이트/다크를 따라가려면, 테마가 바뀔 때마다
  // Native가 따로 보관하는 값을 명시적으로 갱신해줘야 함. (system Configuration의
  // 다크모드 여부와 앱의 "수동으로 고른 테마"는 다른 개념이라 위젯이 OS 설정만
  // 보면 앱에서 수동으로 바꾼 테마를 못 따라감 - 이게 실제로 겪은 버그였음)
  static Future<void> pushTheme(bool isDark) async {
    try {
      await _platform.invokeMethod('setWidgetTheme', {'isDark': isDark});
    } catch (e) {
      print('⚠️ 위젯 테마 전달 실패 (무시): $e');
    }
  }
}
