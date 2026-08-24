// lib/services/widget_refresh_service.dart
//
// ⭐ 홈 화면 캘린더 위젯 즉시 갱신 요청. 위젯은 항상 그 순간 DB를 직접 읽어서
// 그리기 때문에(별도 캐시 없음) 저장 자체는 이미 최신인데, "지금 화면에 붙어있는
// 위젯"을 다시 그리라고 깨워주는 역할만 함. 실패해도 스케줄 저장 자체를 막으면
// 안 되므로 항상 non-throwing - 위젯이 없거나 갱신이 실패해도 무시하고 넘어감
// (다음 자정 하트비트 때 어차피 다시 그려짐, AlarmGuardReceiver.kt 참고).
import '../constants/platform_channel.dart';

class WidgetRefreshService {
  static const _platform = kAlarmChannel;

  static Future<void> refresh() async {
    try {
      await _platform.invokeMethod('refreshCalendarWidget');
    } catch (e) {
      print('⚠️ 위젯 갱신 요청 실패 (무시): $e');
    }
  }
}

// ⭐ pushTheme()(위젯을 앱의 다크모드/9개 달력 테마에 맞춰 따라가게 하던 기능)는
// 2026-08-13에 철회됨 - 위젯은 이제 항상 라이트(메인·화이트) 톤으로 고정.
// CalendarWidgetProvider.kt 참고.
