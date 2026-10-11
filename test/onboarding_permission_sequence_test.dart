import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/widgets/permission_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, dynamic> data;
  late List<String> opened;

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'notification_request_attempted': true});
    data = {
      'notification': 'granted',
      'overlay': 'denied',
      'exactAlarm': 'denied',
      'fullScreen': 'granted',
      'alarmChannel': 'granted',
      'sdk': 34,
    };
    opened = [];
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return Map.of(data);
      if (call.method == 'openPermissionSettings') {
        opened.add(call.arguments['kind'] as String);
        return true;
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  Future<void> pump(WidgetTester tester, {bool sequence = true}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: SingleChildScrollView(
                child: PermissionPanel(
                    actionRequiredOnly: true, continueAfterGrant: sequence)))));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String kind) async {
    final button = find.byKey(ValueKey('permission-$kind'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // Settings return now has a 350ms settle timer. pumpAndSettle alone
    // stops once frames settle, before this non-frame timer is due.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'clicked card goes first; verified grant opens the next denied card',
      (tester) async {
    await pump(tester);
    await tap(tester, 'exactAlarm');
    expect(opened, ['exactAlarm']);
    data['exactAlarm'] = 'granted';
    await resume(tester);
    expect(opened, ['exactAlarm', 'overlay']);
    expect(find.byKey(const ValueKey('permission-exactAlarm')), findsNothing);
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['exactAlarm', 'overlay']);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  for (final state in ['denied', 'unknown', 'notApplicable']) {
    testWidgets(
        '$state return stops the sequence and preserves manual settings',
        (tester) async {
      await pump(tester);
      await tap(tester, 'overlay');
      data['overlay'] = state;
      await resume(tester);
      expect(opened, ['overlay']);
      // A later external grant must not restart an abandoned request.
      data['overlay'] = 'granted';
      await resume(tester);
      expect(opened, ['overlay']);
      await tap(tester, 'exactAlarm');
      expect(opened, ['overlay', 'exactAlarm']);
    });
  }

  testWidgets('blocked alarm channel is a distinct remaining settings route',
      (tester) async {
    data['exactAlarm'] = 'notApplicable';
    data['alarmChannel'] = 'denied';
    await pump(tester);
    await tap(tester, 'overlay');
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay', 'alarmChannel']);
    await resume(tester); // Cancel channel settings.
    data['alarmChannel'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay', 'alarmChannel']);
  });

  testWidgets('unknown next permission is not automatically opened',
      (tester) async {
    data['exactAlarm'] = 'unknown';
    await pump(tester);
    await tap(tester, 'overlay');
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay']);
    expect(find.byKey(const ValueKey('permission-exactAlarm')), findsOneWidget);
  });

  testWidgets('granted state in the background waits for foreground return',
      (tester) async {
    final launch = Completer<bool>();
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return Map.of(data);
      if (call.method == 'openPermissionSettings') {
        opened.add(call.arguments['kind'] as String);
        return opened.length == 1 ? launch.future : true;
      }
      return null;
    });
    await pump(tester);
    await tap(tester, 'overlay');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    data['overlay'] = 'granted';
    launch.complete(true);
    await tester.pumpAndSettle();
    expect(opened, ['overlay']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(opened, ['overlay', 'exactAlarm']);
  });

  testWidgets('failed settings launch does not resume a sequence later',
      (tester) async {
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return Map.of(data);
      if (call.method == 'openPermissionSettings') {
        opened.add(call.arguments['kind'] as String);
        return false;
      }
      return null;
    });
    await pump(tester);
    await tap(tester, 'overlay');
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay']);
  });

  testWidgets('ordinary settings panel keeps independent manual actions',
      (tester) async {
    await pump(tester, sequence: false);
    await tap(tester, 'overlay');
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay']);
  });

  testWidgets('return while launch callback is pending never overlaps requests',
      (tester) async {
    final launch = Completer<bool>();
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return Map.of(data);
      if (call.method == 'openPermissionSettings') {
        opened.add(call.arguments['kind'] as String);
        return opened.length == 1 ? launch.future : true;
      }
      return null;
    });
    await pump(tester);
    await tap(tester, 'overlay');
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay']);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('permission-exactAlarm')))
            .onPressed,
        isNull);
    launch.complete(true);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(opened, ['overlay', 'exactAlarm']);
    await resume(tester); // Still denied: stop, even with repeated resumes.
    await resume(tester);
    expect(opened, ['overlay', 'exactAlarm']);
  });

  testWidgets(
      'hidden or disposed onboarding cannot launch another settings page',
      (tester) async {
    await pump(tester);
    await tap(tester, 'overlay');
    final context = tester.element(find.byType(PermissionPanel));
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered'))));
    await tester.pumpAndSettle();
    data['overlay'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay']);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await resume(tester);
    expect(opened, ['overlay']);
    await tap(tester, 'exactAlarm');
    await tester.pumpWidget(const SizedBox());
    data['exactAlarm'] = 'granted';
    await resume(tester);
    expect(opened, ['overlay', 'exactAlarm']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled first notification request does not open another card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    data['notification'] = 'denied';
    const plugin = MethodChannel('flutter.baseflow.com/permissions/methods');
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method == 'checkPermissionStatus') return 0;
      if (call.method == 'shouldShowRequestPermissionRationale') return false;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(plugin, null));
    final prompt = Completer<bool>();
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return Map.of(data);
      if (call.method == 'requestNotificationPermission') return prompt.future;
      if (call.method == 'openPermissionSettings') {
        opened.add(call.arguments['kind'] as String);
        return true;
      }
      return null;
    });
    await pump(tester);
    await tap(tester, 'notification');
    prompt
        .complete(true); // Native callback completed; actual permission denied.
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    // A cancelled runtime prompt must also end without a lifecycle transition.
    data['notification'] = 'granted';
    await resume(tester);
    expect(opened, isEmpty);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('permission-overlay')))
            .onPressed,
        isNotNull);
  });
}
