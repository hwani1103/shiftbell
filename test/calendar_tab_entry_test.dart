import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as font_loader;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/calendar_theme_provider.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/screens/calendar_tab.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/theme/app_theme.dart';
import 'package:shiftbell/widgets/app_ui_theme_scope.dart';
import 'package:shiftbell/widgets/calendar_app_frame.dart';
import 'package:shiftbell/widgets/complete_cell_memo_text.dart';
import 'package:shiftbell/providers/memo_provider.dart';
import 'package:shiftbell/providers/overtime_provider.dart';
import 'package:shiftbell/models/date_memo.dart';

class _CachedMemos extends MemoNotifier {
  _CachedMemos(Map<String, List<DateMemo>> memos) {
    state = memos;
  }
  @override
  Future<void> loadMemosForDateRange(DateTime start, DateTime end) async {}
}

class _CachedOvertime extends OvertimeNotifier {
  @override
  Future<void> loadForRange(DateTime start, DateTime end) async {}
}

class _PersistentAdProbe extends StatefulWidget {
  const _PersistentAdProbe();
  @override
  State<_PersistentAdProbe> createState() => _PersistentAdProbeState();
}

class _PersistentAdProbeState extends State<_PersistentAdProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox(height: 64);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    if (Platform.isWindows) {
      final font = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(font))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                await rootBundle.load('fonts/MaterialIcons-Regular.otf'))))
          .load();
    }
    final quicksand =
        await File('test/fixtures/layout_fonts/Quicksand-Bold.ttf')
            .readAsBytes();
    final jua =
        await File('test/fixtures/layout_fonts/Jua-Regular.ttf').readAsBytes();
    font_loader.httpClient = MockClient((request) async => http.Response.bytes(
        request.url.path.contains('a083a3') ? jua : quicksand, 200));
    await initializeDateFormatting();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('calendar_app_frame_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
    firebaseReady = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, (_) async => null);
    await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
        isRegular: true,
        pattern: const ['주간', '야간', '휴무'],
        todayIndex: 0,
        shiftTypes: const ['주간', '야간', '휴무'],
        startDate: DateTime(2026, 10, 1),
        customShiftColors: const {'주간': 0xFFDFEDFC, '야간': 0xFF172434}));
    for (final offset in [0, 4]) {
      final day = DateTime.now()
          .add(Duration(days: offset))
          .toIso8601String()
          .substring(0, 10);
      for (final memo in ['가나다라마바사아자차', 'Appointment', 'Training']) {
        await DatabaseService.instance.createMemo(day, memo);
      }
    }
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });

  for (final size in [const Size(400, 850), const Size(800, 850)]) {
    for (final palette in ['daytime', 'night']) {
      for (final theme in kAllCalendarThemeIds) {
        testWidgets(
            '${theme.name} $palette $size tab entry geometry remains stable',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'welcome_popup_shown': true,
            'shift_assign_tutorial_shown': true,
            AppUiThemePreviewController.preferenceKey: palette,
          });
          late ScheduleNotifier schedule;
          late Map<String, List<DateMemo>> cachedMemos;
          await tester.runAsync(() async {
            schedule = ScheduleNotifier();
            await schedule.refresh();
            cachedMemos = await DatabaseService.instance.getMemosForDateRange(
                DateTime.now().subtract(const Duration(days: 40)),
                DateTime.now().add(const Duration(days: 40)));
          });
          final container = ProviderContainer(overrides: [
            scheduleProvider.overrideWith((ref) => schedule),
            memoProvider.overrideWith((ref) => _CachedMemos(cachedMemos)),
            overtimeProvider.overrideWith((ref) => _CachedOvertime()),
            calendarThemeProvider.overrideWith(
                (ref) => CalendarThemeNotifier.withInitial(theme)),
          ]);
          addTearDown(container.dispose);
          var active = false;
          late StateSetter change;
          await tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: ScreenUtilInit(
                  designSize: const Size(360, 780),
                  builder: (_, __) => MaterialApp(
                      locale: const Locale('ko'),
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      theme: AppTheme.lightTheme,
                      home: StatefulBuilder(builder: (_, setState) {
                        change = setState;
                        return AppUiThemeScope(
                            enabled: active,
                            preserveTextGeometry: true,
                            builder: (_) => Scaffold(
                                body: Column(children: [
                                  Expanded(
                                      child: active
                                          ? CalendarDesignTheme(
                                              theme: theme,
                                              child: const CalendarTab())
                                          : const SizedBox()),
                                  const _PersistentAdProbe(),
                                ]),
                                bottomNavigationBar:
                                    BottomNavigationBar(items: const [
                                  BottomNavigationBarItem(
                                      icon: Icon(Icons.alarm), label: 'Alarm'),
                                  BottomNavigationBarItem(
                                      icon: Icon(Icons.calendar_month),
                                      label: 'Calendar'),
                                ])));
                      })))));
          await tester.pumpAndSettle();
          // Cache fonts before entry, so network/font loading cannot explain motion.
          change(() => active = true);
          await tester.pumpAndSettle();
          await tester.runAsync(() => GoogleFonts.pendingFonts());
          change(() => active = false);
          await tester.pumpAndSettle();
          change(() => active = true);
          await tester.pump();
          List<Object?> geometry() => [
                tester.getRect(find.byType(TableCalendar)),
                tester
                    .widget<TableCalendar>(find.byType(TableCalendar))
                    .rowHeight,
                for (final e
                    in find.byType(CompleteCellMemoText).evaluate()) ...[
                  tester.getRect(find.byWidget(e.widget)),
                  for (final text in find
                      .descendant(
                          of: find.byWidget(e.widget),
                          matching: find.byType(Text))
                      .evaluate())
                    [
                      (text.widget as Text).data,
                      (text.widget as Text).style?.fontSize,
                      (text.widget as Text).style?.height,
                      (text.widget as Text).style?.letterSpacing
                    ],
                ],
              ];
          final first = geometry();
          expect(find.byType(CompleteCellMemoText), findsWidgets);
          final snapshots = <List<Object?>>[];
          for (final milliseconds in [16, 64, 120, 200]) {
            await tester.pump(Duration(milliseconds: milliseconds));
            snapshots.add(geometry());
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          for (final snapshot in snapshots) {
            expect(snapshot, first, reason: theme.name);
          }
        });
      }
    }
  }
}
