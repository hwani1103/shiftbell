import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/screens/settings_tab.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/widgets/app_ui_theme_preview.dart';
import 'package:shiftbell/widgets/settings_menu_list.dart';

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
  for (final size in [const Size(400, 850), const Size(800, 850)]) {
    testWidgets('settings footer keeps theme choice at $size', (tester) async {
      SharedPreferences.setMockInitialValues({'welcome_popup_shown': true});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late ScheduleNotifier schedule;
      await tester.runAsync(() async {
        schedule = ScheduleNotifier();
        await schedule.refresh();
      });
      await tester.pumpWidget(ProviderScope(
          overrides: [
            scheduleProvider.overrideWith((ref) => schedule),
            appUiThemeClockProvider
                .overrideWithValue(() => DateTime(2026, 10, 13, 12)),
          ],
          child: ScreenUtilInit(
              designSize: const Size(360, 800),
              builder: (_, __) => const MaterialApp(
                  locale: Locale('ko'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: SettingsTab()))));
      await tester.pumpAndSettle();
      final menu =
          tester.widget<SettingsMenuList>(find.byType(SettingsMenuList));
      expect(menu.children.last, isA<Align>());
      await tester.scrollUntilVisible(find.byType(AppUiThemePreview), 450,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-ui-theme-night')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getString(AppUiThemePreviewController.preferenceKey), 'night');
      final palette = Theme.of(tester.element(find.byType(AppUiThemePreview)));
      expect(palette.brightness, Brightness.dark);
      final footerWidth = tester.getSize(find.byType(AppUiThemePreview)).width;
      expect(footerWidth, greaterThan(size.width * .8));
      await tester
          .tap(find.byKey(const ValueKey('app-ui-theme-originalWhite')));
      await tester.pumpAndSettle();
      expect(prefs.getString(AppUiThemePreviewController.preferenceKey),
          'originalWhite');
      expect(find.text('화이트'), findsOneWidget);
      await tester.tap(find.text('자동'));
      await tester.pumpAndSettle();
      expect(prefs.getString(AppUiThemePreviewController.preferenceKey),
          'automatic');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
