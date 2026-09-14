// 출시전 감사 G1 #5 - 앱 시작 시 "일정관리 탭 사용" 설정을 Native로 동기화(Native는 잠금 해제 전 재부팅·알림 수신에서 확인).
// Native 쪽 동작(값이 바뀔 때만 예약 회수/복원)은 Kotlin G1ScheduleNotifyTest.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/providers/tab_visibility_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  Future<List<MethodCall>> loadWith(Map<String, Object> prefs, String key) async {
    SharedPreferences.setMockInitialValues(prefs);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      calls.add(call);
      return null;
    });
    TabEnabledNotifier(key);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return calls;
  }

  test('저장된 일정관리 탭 설정(false)을 Native로 보낸다', () async {
    final calls = await loadWith({'schedule_tab_enabled': false}, 'schedule_tab_enabled');
    expect(calls.map((c) => c.method), ['syncScheduleTabEnabled']);
    expect(calls.single.arguments, {'enabled': false});
  });

  test('설정이 없으면 기본값 true를 보낸다', () async {
    final calls = await loadWith({}, 'schedule_tab_enabled');
    expect(calls.single.arguments, {'enabled': true});
  });

  test('컨디션 탭 설정은 Native로 보내지 않는다', () async {
    final calls = await loadWith({'condition_tab_enabled': false}, 'condition_tab_enabled');
    expect(calls, isEmpty);
  });
}
