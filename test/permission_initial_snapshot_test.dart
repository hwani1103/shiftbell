import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';
import 'package:shiftbell/services/permission_service.dart';

Map<String, Object> snapshot({String overlay = 'denied'}) => {
      'notification': 'granted',
      'overlay': overlay,
      'exactAlarm': 'granted',
      'fullScreen': 'notApplicable',
      'alarmChannel': 'granted',
      'sdk': 34,
    };

Future<AppLocalizations> pumpIntro(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ProviderScope(child: PermissionIntroScreen())));
  return AppLocalizations.of(
      tester.element(find.byType(PermissionIntroScreen)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  test('initial read failure finishes loading but never implies approval',
      () async {
    final controller =
        PermissionController(read: () async => throw StateError('offline'));
    expect(controller.hasLoaded, isFalse);
    await controller.refresh();
    expect(controller.hasLoaded, isTrue);
    expect(controller.value.allSatisfied, isFalse);
    expect(controller.value[AppPermission.notification],
        AppPermissionState.unknown);
    expect(controller.value.alarmChannel, AppPermissionState.unknown);
    controller.dispose();
  });

  testWidgets('slow first read exposes no temporary controls or skip action',
      (tester) async {
    final read = Completer<Map<String, Object>>();
    messenger.setMockMethodCallHandler(
        kAlarmChannel, (call) async => read.future);
    final l = await pumpIntro(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(l.permissionGetStarted), findsNothing);
    expect(find.text(l.commonNotNow), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    read.complete(snapshot());
    await tester.pumpAndSettle();
    expect(find.text(l.permissionGetStarted), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-notification')), findsNothing);
    expect(find.byKey(const ValueKey('permission-exactAlarm')), findsNothing);
    expect(find.byKey(const ValueKey('permission-fullScreen')), findsNothing);
    expect(find.text(l.commonNotNow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed initial read exposes unknown and resume can recover',
      (tester) async {
    var fail = true;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (fail) throw PlatformException(code: 'snapshot-unavailable');
      return snapshot();
    });
    final l = await pumpIntro(tester);
    await tester.pumpAndSettle();
    expect(find.text(l.permissionGetStarted), findsOneWidget);
    for (final permission in AppPermission.values) {
      expect(find.byKey(ValueKey('permission-${permission.name}')),
          findsOneWidget);
    }
    expect(find.text(l.permissionAlarmChannelUnknown), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('permissions_requested'),
        isNull);
    fail = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('permission-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-exactAlarm')), findsNothing);
    expect(find.text(l.permissionAlarmChannelUnknown), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'already satisfied initial read keeps intro hidden during verified continuation',
      (tester) async {
    final first = Completer<Map<String, Object>>();
    final verification = Completer<Map<String, Object>>();
    var reads = 0;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      return ++reads == 1 ? first.future : verification.future;
    });
    final l = await pumpIntro(tester);
    first.complete(snapshot(overlay: 'granted'));
    await tester.pump();
    await tester.pump();
    expect(reads, 2);
    expect(find.text(l.permissionGetStarted), findsNothing);
    expect(find.text(l.commonNotNow), findsNothing);
    // Dispose before allowing the async verification to finish: no stale navigation.
    await tester.pumpWidget(const SizedBox.shrink());
    verification.complete(snapshot());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume read keeps last UI visible instead of blanking again',
      (tester) async {
    final resume = Completer<Map<String, Object>>();
    var reads = 0;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getPlatformSdkInt') return 34;
      expect(call.method, 'permissionSnapshot');
      return ++reads == 1 ? snapshot() : resume.future;
    });
    final l = await pumpIntro(tester);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.permissionGetStarted), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-overlay')), findsOneWidget);
    resume.complete(snapshot());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
