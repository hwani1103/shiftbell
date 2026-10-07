import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/services/permission_service.dart';
import 'package:shiftbell/widgets/permission_panel.dart';
import 'package:shiftbell/widgets/permission_warning_banner.dart';

Map<String, dynamic> states(
        {String fullScreen = 'denied', bool xiaomi = false, int sdk = 34}) =>
    {
      'notification': 'granted',
      'overlay': 'granted',
      'exactAlarm': 'granted',
      'fullScreen': fullScreen,
      'alarmChannel': 'granted',
      'xiaomi': xiaomi,
      'sdk': sdk,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  test('missing and malformed observations never satisfy permissions', () {
    expect(PermissionSnapshot.parse({}).allSatisfied, isFalse);
    expect(PermissionSnapshot.parse(states(fullScreen: 'unknown')).allSatisfied,
        isFalse);
    expect(
        PermissionSnapshot.parse(states(fullScreen: 'notApplicable', sdk: 33))
            .allSatisfied,
        isTrue);
    final blocked = states(fullScreen: 'granted')..['alarmChannel'] = 'denied';
    expect(PermissionSnapshot.parse(blocked).allSatisfied, isFalse);
    expect(PermissionSnapshot.parse(blocked)[AppPermission.notification],
        AppPermissionState.granted);
  });

  test(
      'a resume overlapping an older read commits only the trailing observation',
      () async {
    final reads = <Completer<PermissionSnapshot>>[];
    final controller = PermissionController(read: () {
      final read = Completer<PermissionSnapshot>();
      reads.add(read);
      return read.future;
    });
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final first = controller.refresh();
    final second = controller.refresh();
    reads[0].complete(PermissionSnapshot.parse(states(fullScreen: 'granted')));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
    expect(reads, hasLength(2));
    reads[1].complete(PermissionSnapshot.parse(states(fullScreen: 'denied')));
    await Future.wait([first, second]);
    expect(
        controller.value[AppPermission.fullScreen], AppPermissionState.denied);
    expect(notifications, 1);
  });

  test('opening settings and duplicate taps do not grant or chain permissions',
      () async {
    final launch = Completer<bool>();
    final opened = <String>[];
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return states();
      if (call.method == 'openPermissionSettings') {
        opened.add((call.arguments as Map)['kind'] as String);
        return launch.future;
      }
      return null;
    });
    final first = PermissionService().openPermission('fullScreen');
    await Future<void>.delayed(Duration.zero);
    expect(await PermissionService().openPermission('overlay'), isFalse);
    launch.complete(true);
    expect(await first, isTrue);
    expect(opened, ['fullScreen']);
    expect((await PermissionService().snapshot()).allSatisfied, isFalse);
    await PermissionService().openPermission('exactAlarm');
    expect(opened, ['fullScreen']); // Already allowed: no settings launch.
  });

  test('native read failure is unknown and route failure remains a failure',
      () async {
    messenger.setMockMethodCallHandler(kAlarmChannel,
        (_) async => throw PlatformException(code: 'unavailable'));
    expect((await PermissionService().snapshot())[AppPermission.fullScreen],
        AppPermissionState.unknown);
    expect(await PermissionService().openPermission('fullScreen'), isFalse);
  });

  for (final locale in [
    const Locale('ko'),
    const Locale('pt', 'BR'),
    const Locale('de'),
    const Locale('en'),
    const Locale('hi')
  ]) {
    testWidgets(
        '$locale permission row refreshes after settings without navigation',
        (tester) async {
      var data = states();
      final opened = <String>[];
      messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
        if (call.method == 'permissionSnapshot') return data;
        if (call.method == 'openPermissionSettings') {
          opened.add(call.arguments['kind'] as String);
          return true;
        }
        return null;
      });
      await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
              body: SingleChildScrollView(child: PermissionPanel()))));
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      expect(find.text(l.permissionFullScreen), findsOneWidget);
      final button = find.byKey(const ValueKey('permission-fullScreen'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(opened, ['fullScreen']);
      expect(button, findsOneWidget); // Opening settings alone does not grant.
      data = states(fullScreen: 'granted');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      expect(find.byType(PermissionPanel), findsOneWidget);
      expect(opened, ['fullScreen']);
    });
  }

  testWidgets(
      'Xiaomi sheet refreshes but never completes by reading instructions',
      (tester) async {
    var data = states(xiaomi: true);
    final opened = <String>[];
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') return data;
      if (call.method == 'openPermissionSettings') {
        opened.add(call.arguments['kind']);
        return true;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
            body: SingleChildScrollView(child: PermissionPanel()))));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('permission-fullScreen'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.permissionXiaomiBody), findsOneWidget);
    expect(opened, isEmpty);
    await tester.ensureVisible(find.text(l.permissionOpenOemSettings));
    await tester.tap(find.text(l.permissionOpenOemSettings));
    await tester.pumpAndSettle();
    expect(opened, ['xiaomi']);
    expect(find.text(l.permissionStillDenied), findsOneWidget);
    data = states(xiaomi: true, fullScreen: 'granted');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(l.permissionStillDenied), findsNothing);
    expect(opened, ['xiaomi']);
  });

  testWidgets(
      'unknown banner changes language and a blocked channel stays separate',
      (tester) async {
    var data = states(fullScreen: 'unknown');
    messenger.setMockMethodCallHandler(kAlarmChannel,
        (call) async => call.method == 'permissionSnapshot' ? data : null);
    final language = ValueNotifier(const Locale('ko'));
    addTearDown(language.dispose);
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (_, locale, __) => ScreenUtilInit(
            designSize: const Size(360, 800),
            builder: (_, __) => MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const Scaffold(body: PermissionWarningBanner())))));
    await tester.pumpAndSettle();
    final ko = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(ko.permissionRequiredNotGranted), findsOneWidget);
    language.value = const Locale('en');
    await tester.pumpAndSettle();
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(ko.permissionRequiredNotGranted), findsNothing);
    expect(find.text(en.permissionStatusUnknown(en.permissionFullScreen)),
        findsOneWidget);
    data = states(fullScreen: 'granted')..['alarmChannel'] = 'denied';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(en.permissionAlarmChannelBlocked), findsOneWidget);
    expect(find.text(en.permissionStatusUnknown(en.permissionFullScreen)),
        findsNothing);
    data = states(fullScreen: 'granted');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(en.permissionRequiredNotGranted), findsNothing);
  });
}
