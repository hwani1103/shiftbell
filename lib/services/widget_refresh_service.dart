// lib/services/widget_refresh_service.dart
//
// ⭐ 홈 화면 캘린더 위젯 즉시 갱신 요청. 위젯은 항상 그 순간 DB를 직접 읽어서
// 그리기 때문에(별도 캐시 없음) 저장 자체는 이미 최신인데, "지금 화면에 붙어있는
// 위젯"을 다시 그리라고 깨워주는 역할만 함. 실패해도 스케줄 저장 자체를 막으면
// 안 되므로 항상 non-throwing - 위젯이 없거나 갱신이 실패해도 무시하고 넘어감
// (다음 자정 하트비트 때 어차피 다시 그려짐, AlarmGuardReceiver.kt 참고).
//
// ⭐ 2026-09-07 - "달력에서 오늘 근무를 바꿨는데 수면 위젯의 '오늘 근무' 칩이
// 한동안 예전 값(예: 야간으로 바꿨는데 주간으로 표시)으로 남아있다"는 신고로
// 원인 확인 - SleepWidgetProvider.kt는 refreshCalendarWidget과 별개 채널
// (refreshSleepWidget)로만 다시 그려지는데, 이 refresh()가 그동안 캘린더
// 위젯만 깨우고 수면 위젯은 안 깨웠음(스케줄이 바뀌어도 수면 위젯은 30분
// 주기 시스템 자동 갱신 - sleep_widget_info.xml의 updatePeriodMillis - 이나
// 수면/기상 버튼을 누르기 전까지 예전 근무명을 계속 보여줌). 두 위젯 다
// "지금 화면에 붙어있는 걸 다시 그려라"는 같은 성격의 신호를 받는 거라,
// 이 함수를 부르는 모든 곳(스케줄/메모/테마 변경 등)에서 항상 같이
// 갱신하도록 통합함 - 위젯이 없으면 Kotlin 쪽에서 각자 조용히 아무 것도 안
// 하므로 이렇게 합쳐도 부작용 없음.
import '../constants/platform_channel.dart';

class WidgetRefreshService {
  static const _platform = kAlarmChannel;

  static Future<void> refresh() async {
    try {
      await _platform.invokeMethod('refreshCalendarWidget');
    } catch (e) {
      print('⚠️ 캘린더 위젯 갱신 요청 실패 (무시): $e');
    }
    try {
      await _platform.invokeMethod('refreshSleepWidget');
    } catch (e) {
      print('⚠️ 수면 위젯 갱신 요청 실패 (무시): $e');
    }
  }
}

// ⭐ pushTheme()(위젯을 앱의 다크모드/9개 달력 테마에 맞춰 따라가게 하던 기능)는
// 2026-08-13에 철회됨 - 위젯은 이제 항상 라이트(메인·화이트) 톤으로 고정.
// CalendarWidgetProvider.kt 참고.
