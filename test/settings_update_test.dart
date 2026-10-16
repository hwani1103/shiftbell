import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/screens/settings_tab.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('settings_theme_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
    await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
        isRegular: true,
        pattern: const ['주간', '휴무'],
        todayIndex: 0,
        shiftTypes: const ['주간', '휴무'],
        startDate: DateTime(2026, 10, 13)));
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });

  for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
    testWidgets(
        '$language settings manual update handles pending and unavailable',
        (tester) async {
      SharedPreferences.setMockInitialValues({'welcome_popup_shown': true});
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('de.ffuf.in_app_update/methods');
      final response = Completer<Map<String, Object?>>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) {
        calls++;
        return response.future;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      late ScheduleNotifier schedule;
      await tester.runAsync(() async {
        schedule = ScheduleNotifier();
        await schedule.refresh();
      });
      await tester.pumpWidget(ProviderScope(
          overrides: [scheduleProvider.overrideWith((ref) => schedule)],
          child: ScreenUtilInit(
              designSize: const Size(360, 800),
              builder: (_, __) => MaterialApp(
                  theme: AppTheme.lightTheme,
                  locale: Locale(language),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: const SettingsTab()))));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settings-check-update'));
      await tester.scrollUntilVisible(row, 450,
          scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(row),alignment:0.5);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(row));
      await tester.tap(row);
      await tester.pump();
      expect(tester.widget<ListTile>(row).enabled, false);
      expect(
          find.descendant(
              of: row, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(calls, 1);
      response.completeError(PlatformException(code: 'offline'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.updateCheckUnavailable), findsOneWidget);
      expect(find.text(l10n.updateAlreadyLatest), findsNothing);
      expect(find.text(l10n.updateOpenPlayStore), findsOneWidget);
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(row).enabled, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
