import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';
import 'package:shiftbell/services/database_service.dart';

void main() {
  testWidgets(
      'resume advances only after every permission and channel is verified',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('permission_intro_');
      await databaseFactory.setDatabasesPath(dir.path);
      DatabaseService.debugIsAndroidOverride = false;
      await DatabaseService.instance.database;
    });
    addTearDown(() async {
      await (await DatabaseService.instance.database).close();
      DatabaseService.debugIsAndroidOverride = null;
      await dir.delete(recursive: true);
    });
    var overlay = 'denied';
    var channel = 'granted';
    var settingsOpened = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'permissionSnapshot') {
        return {
          'notification': 'granted',
          'overlay': overlay,
          'exactAlarm': 'notApplicable',
          'fullScreen': 'granted',
          'alarmChannel': channel,
          'sdk': 34
        };
      }
      if (call.method == 'openPermissionSettings') {
        settingsOpened++;
        return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));
    var nextBuilds = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/onboarding': (_) {
          nextBuilds++;
          return const Scaffold(body: Text('next-onboarding'));
        }
      },
      home: const PermissionIntroScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('permission-overlay')));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(nextBuilds, 0); // Opening settings is not permission approval.
    overlay = 'granted';
    for (final remaining in ['denied', 'unknown']) {
      channel = remaining;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(nextBuilds, 0);
    }
    channel = 'granted';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // Let the real SQLite lookup finish outside the widget fake clock.
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('next-onboarding'), findsOneWidget);
    expect(nextBuilds, 1);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('permissions_requested'),
        isTrue);
    expect(tester.takeException(), isNull);
  });
}
