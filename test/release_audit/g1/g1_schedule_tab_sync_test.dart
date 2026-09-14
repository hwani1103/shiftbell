// 출시전 감사 G1 #5 - 앱 시작 시 "일정관리 탭 사용" 설정을 Native로 동기화(Native는 잠금 해제 전 재부팅·알림 수신에서 확인).
// Native 쪽 동작(값이 바뀔 때만 예약 회수/복원)은 Kotlin G1ScheduleNotifyTest.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/providers/tab_visibility_provider.dart';
import 'package:shiftbell/widgets/disable_tab_button.dart';

class _FailingTabEnabledNotifier extends TabEnabledNotifier {
  _FailingTabEnabledNotifier() : super('condition_tab_enabled');

  @override
  Future<void> setEnabled(bool enabled) async {
    throw StateError('injected tab sync failure');
  }
}

final _failingTabProvider = StateNotifierProvider<TabEnabledNotifier, bool>(
  (ref) => _FailingTabEnabledNotifier(),
);

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

  test('T11-07 Native 동기화 실패 시 일정 탭 로컬 상태와 prefs를 바꾸지 않는다', () async {
    SharedPreferences.setMockInitialValues({'schedule_tab_enabled': true});
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      calls.add(call);
      final enabled = (call.arguments as Map?)?['enabled'];
      if (call.method == 'syncScheduleTabEnabled' && enabled == false) {
        throw PlatformException(code: 'injected');
      }
      return null;
    });
    final notifier = TabEnabledNotifier('schedule_tab_enabled');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await expectLater(notifier.setEnabled(false), throwsA(anything));

    expect(notifier.state, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('schedule_tab_enabled'), isTrue);
    expect(calls.where((c) => c.method == 'syncScheduleTabEnabled').length, 2);
  });

  testWidgets('C-03 탭 전환 StateError를 SnackBar로 안내하고 후속 동작을 막는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var disabled = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DisableTabButton(
              tabLabel: '일정관리',
              provider: _failingTabProvider,
              onDisabled: () => disabled = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('일정관리 화면 사용하지 않기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 수정 전 기대 결과: FAIL - StateError가 처리되지 않아 SnackBar가 없고 테스트 예외가 발생한다.
    // 수정 후 기대 결과: PASS - 사용자 안내를 표시하고 onDisabled를 호출하지 않는다.
    expect(find.text('화면 설정을 바꾸지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(disabled, isFalse);
  });
}
