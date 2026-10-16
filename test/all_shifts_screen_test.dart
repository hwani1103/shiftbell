import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/providers/all_shifts_layout_provider.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/screens/all_shifts_view.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/all_shifts_overview.dart';

void main() {
  late Directory temp;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('roster_screen_');
    await databaseFactory.setDatabasesPath(temp.path);
    DatabaseService.debugIsAndroidOverride = false;
    await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
        isRegular: true,
        pattern: ['주간', '야간', '휴무', '특별근무'],
        todayIndex: 2,
        startDate: DateTime(2024, 1, 1),
        shiftTypes: ['주간', '야간', '휴무', '특별근무']));
    await DatabaseService.instance.saveTeamScheduleConfig(
        const TeamScheduleConfig(
                names: ['A', 'B', 'C', 'D'],
                offsets: {'A': 0, 'B': 1, 'C': 2, 'D': 3},
                myTeam: 'C')
            .materialize(['주간', '야간', '휴무', '특별근무']));
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    await temp.delete(recursive: true);
  });
  for (final theme in AppUiTimeTheme.values) {
    testWidgets(
        'Full screen ${theme.name}: fixed buttons, saved choice and edge fill',
        (t) async {
      SharedPreferences.setMockInitialValues({
        AppUiThemePreviewController.preferenceKey: theme.name,
        AllShiftsLayoutController.preferenceKey: 'overview'
      });
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<void> open() async {
        await t.pumpWidget(ProviderScope(
            child: ScreenUtilInit(
                designSize: const Size(360, 780),
                builder: (_, __) => MaterialApp(
                    locale: const Locale('ko'),
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    home: AllShiftsView(initialMonth: DateTime(2026, 10))))));
        await t.pump();
        await t.runAsync(() async {
          final context = t.element(find.byType(AllShiftsView));
          await ProviderScope.containerOf(context)
              .read(scheduleProvider.notifier)
              .refresh();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        for (var attempt = 0;
            attempt < 50 && find.byType(MonthShiftTable).evaluate().isEmpty;
            attempt++) {
          await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pumpAndSettle();
        }
      }

      await open();
      expect(find.byType(AllShiftsOverview), findsOneWidget);
      final overview = t.getRect(find.byType(AllShiftsOverview));
      expect(overview.left, 0);
      expect(overview.right, 320);
      expect(t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          theme.palette.background);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      final pageBeforeDrag = t.widget<PageView>(find.byType(PageView));
      final octoberBeforeDrag =
          t.widget<MonthShiftTable>(find.byKey(const ValueKey('2026-10')));
      final gesture =
          await t.startGesture(t.getCenter(find.byType(AllShiftsOverview)));
      await gesture.moveBy(const Offset(-20, 0));
      await t.pump();
      await gesture.moveBy(const Offset(-210, 0));
      await t.pump();
      expect(find.text('2026년 11월'), findsOneWidget);
      expect(
          identical(t.widget<PageView>(find.byType(PageView)), pageBeforeDrag),
          isTrue,
          reason:
              'Month title must update without rebuilding the moving pages');
      expect(
          identical(
              t.widget<MonthShiftTable>(find.byKey(const ValueKey('2026-10'))),
              octoberBeforeDrag),
          isTrue);
      for (final table
          in t.widgetList<MonthShiftTable>(find.byType(MonthShiftTable))) {
        final now = DateTime.now();
        expect(table.isViewingCurrentRealMonth,
            table.year == now.year && table.month == now.month);
      }
      await gesture.up();
      await t.pumpAndSettle();
      expect(t.widget<MonthShiftTable>(find.byType(MonthShiftTable)).month, 11);
      await t.drag(find.byType(AllShiftsOverview), const Offset(250, 0));
      await t.pumpAndSettle();
      expect(t.widget<MonthShiftTable>(find.byType(MonthShiftTable)).month, 10);
      final timeline = find.byKey(const ValueKey('roster-layout-timeline'));
      await t.tap(timeline);
      await t.pumpAndSettle();
      expect(t.widget<IconButton>(timeline).isSelected, true);
      expect(find.byType(AllShiftsOverview), findsNothing);
      final band =
          t.getRect(find.byKey(const ValueKey('roster-timeline-block-1')));
      expect(band.left, closeTo(8.w, .001));
      expect(band.right, closeTo(320 - 8.w, .001));
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      final days = find.byKey(const ValueKey('roster-timeline-days-1'));
      final controller = t.widget<SingleChildScrollView>(days).controller!;
      await t.drag(days, const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(t.widget<MonthShiftTable>(find.byType(MonthShiftTable)).month, 10);
      await t.tap(find.byIcon(Icons.chevron_right));
      await t.pumpAndSettle();
      expect(t.widget<MonthShiftTable>(find.byType(MonthShiftTable)).month, 11);
      await t.tap(find.byKey(const ValueKey('roster-layout-overview')));
      await t.pumpAndSettle();
      expect(t.widget<MonthShiftTable>(find.byType(MonthShiftTable)).month, 11);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await t.tap(timeline);
      await t.pumpAndSettle();
      expect(
          (await SharedPreferences.getInstance())
              .getString(AllShiftsLayoutController.preferenceKey),
          'timeline');
      await t.pumpWidget(const SizedBox());
      await open();
      expect(t.widget<IconButton>(timeline).isSelected, true);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
