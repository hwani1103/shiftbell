import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:shiftbell/providers/tab_visibility_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as font_loader;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/providers/alarm_provider.dart';
import 'package:shiftbell/providers/memo_provider.dart';
import 'package:shiftbell/providers/calendar_theme_provider.dart';
import 'package:shiftbell/screens/calendar_tab.dart';
import 'package:shiftbell/screens/next_alarm_tab.dart';
import 'package:shiftbell/screens/settings_tab.dart';
import 'package:shiftbell/screens/condition_tab.dart';
import 'package:shiftbell/screens/english_condition_tab.dart';
import 'package:shiftbell/screens/schedule_management_tab.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';
import 'package:shiftbell/screens/work_hours_settings_screen.dart';
import 'package:shiftbell/screens/calendar_theme_picker_screen.dart';
import 'package:shiftbell/screens/all_teams_setup_screen.dart';
import 'package:shiftbell/screens/all_shifts_view.dart';
import 'package:shiftbell/screens/all_alarms_history_view.dart';
import 'package:shiftbell/screens/memo_list_view.dart';
import 'package:shiftbell/screens/help_screen.dart';
import 'package:shiftbell/screens/privacy_policy_screen.dart';
import 'package:shiftbell/screens/friend_list_screen.dart';
import 'package:shiftbell/screens/friend_calendar_view.dart';
import 'package:shiftbell/screens/my_share_code_screen.dart';
import 'package:shiftbell/screens/sleep_calendar_full_screen.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/theme/app_theme.dart';
import 'package:shiftbell/widgets/app_content_frame.dart';
import 'package:shiftbell/widgets/wide_calendar_cell.dart';
import 'package:shiftbell/widgets/sleep_edit_dialog.dart';
import 'package:shiftbell/utils/holiday_util.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dbDir;
  const capture = bool.fromEnvironment('CAPTURE_LAYOUTS');
  const scaleSweep = bool.fromEnvironment('LAYOUT_SCALE_SWEEP');
  const ultraOnly = bool.fromEnvironment('LAYOUT_ULTRA_ONLY');
  const flipAudit = bool.fromEnvironment('LAYOUT_FLIP_AUDIT');
  const reviewMonth = int.fromEnvironment('LAYOUT_REVIEW_MONTH');
  final auditMonth = reviewMonth == 0
      ? DateTime.now()
      : DateTime(int.fromEnvironment('LAYOUT_REVIEW_YEAR', defaultValue: 2027),
          reviewMonth, 13);
  final auditDays = <int, int>{};
  if (flipAudit) {
    final days = List.generate(28, (i) => i + 1);
    bool holiday(int day) =>
        getHolidayName(DateTime(auditMonth.year, auditMonth.month, day),
            isKorean: true) !=
        null;
    bool red(int day) =>
        holiday(day) ||
        DateTime(auditMonth.year, auditMonth.month, day).weekday ==
            DateTime.sunday;
    final redDays = days.where(red).toList()
      ..sort((a, b) => (holiday(b) ? 1 : 0).compareTo(holiday(a) ? 1 : 0));
    for (final group in [redDays.take(3), days.where((d) => !red(d)).take(3)]) {
      var count = 0;
      for (final day in group) {
        auditDays[day] = ++count;
      }
    }
  }
  if (reviewMonth == 5) auditDays[13] = 3;
  const longShiftNames = bool.fromEnvironment('LAYOUT_LONG_SHIFT_NAMES');
  const shifts = reviewMonth != 0
      ? ['주간', '야간근무', '휴무휴무휴무']
      : longShiftNames
          ? ['주간근무', '야간근무', '휴무']
          : ['주간', '야간', '휴무'];
  final requestedTextScale = double.parse(
      const String.fromEnvironment('LAYOUT_TEXT_SCALE', defaultValue: '1.0'));
  final captureKey = GlobalKey();
  final baselineCellHeights = <String, double>{};
  setUpAll(() async {
    if ((capture || const bool.fromEnvironment('LAYOUT_REAL_FONTS')) &&
        Platform.isWindows) {
      final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
      await (FontLoader('LayoutPreview')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
      final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
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
    dbDir = await Directory.systemTemp.createTemp('fold_layout_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dbDir.path);
    await databaseFactory.setDatabasesPath(dbDir.path);
    DatabaseService.debugIsAndroidOverride = false;
    firebaseReady = false;
    await DatabaseService.instance.database;
    await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
        isRegular: true,
        pattern: shifts,
        todayIndex: 0,
        shiftTypes: shifts,
        startDate: DateTime(2026, 9, 1)));
    final today = auditMonth;
    for (var hour = 7; hour < 12; hour++) {
      await DatabaseService.instance.insertAlarm(Alarm(
          time: '${hour.toString().padLeft(2, '0')}:30',
          date: DateTime(today.year, today.month, 15, hour, 30),
          type: 'fixed',
          alarmTypeId: hour % 3 + 1,
          shiftType: shifts.first));
    }
    if (reviewMonth != 0) {
      for (final day in auditDays.keys) {
        for (var i = 0; i < auditDays[day]!; i++) {
          await DatabaseService.instance.createMemo(
              '${auditMonth.year}-${auditMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
              ['첫째메모여섯', '둘째메모여섯', '셋째메모여섯'][i]);
        }
      }
    }
    if (!flipAudit) {
      await DatabaseService.instance.createMemo(
          '${today.year}-${today.month.toString().padLeft(2, '0')}-22',
          '첫째메모가길어져도글자크기는같아야합니다');
    }
    for (final day in reviewMonth != 0
        ? <int>[]
        : flipAudit
            ? auditDays.keys
            : {today.day, 23, 24, 25}) {
      final date =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      for (final memo in (reviewMonth == 0
              ? ['첫째', '둘째', '셋째']
              : ['첫째메모여섯', '둘째메모여섯', '셋째메모여섯'])
          .take(flipAudit
              ? auditDays[day]!
              : day == 23
                  ? 1
                  : day == 24
                      ? 2
                      : 3)) {
        await DatabaseService.instance.createMemo(date, memo);
      }
    }
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await dbDir.delete(recursive: true);
  });

  final screens = <String, Widget Function()>{
    'next': () => const NextAlarmTab(),
    'settings': () => SettingsTab(),
    'settings_features': () => const SettingsTab(additionalFeatures: true),
    'settings_backup': () => const SettingsTab(backupOnly: true),
    'condition': () =>
        ConditionTab(onDisabled: () {}, onConfirmed: () async {}),
    'english_sleep': () =>
        EnglishConditionTab(onDisabled: () {}, onConfirmed: () async {}),
    'schedule': () =>
        ScheduleManagementTab(onDisabled: () {}, onConfirmed: () async {}),
    'onboarding': () => const OnboardingScreen(),
    'permission': () => const PermissionIntroScreen(),
    'work_hours': () => const WorkHoursSettingsScreen(),
    'themes': () => const CalendarThemePickerScreen(),
    'teams': () =>
        const AllTeamsSetupScreen(pattern: ['주간', '야간', '휴무'], myTodayIndex: 0),
    'all_shifts': () => const AllShiftsView(),
    'alarm_history': () => const AllAlarmsHistoryView(),
    'memos': () => const MemoListView(),
    'help': () => const HelpScreen(),
    'privacy': () => const PrivacyPolicyScreen(),
    'friends': () => const FriendListScreen(),
    'friend_calendar': () => FriendCalendarView(
        friendName: '친구 근무표',
        data: FriendScheduleData(
            ownerName: '친구',
            isRegular: true,
            pattern: ['주간', '야간', '휴무'],
            todayIndex: 0,
            startDate: DateTime(2026, 9, 1),
            shiftColors: const {'주간': 0xFFB3E5FC, '야간': 0xFFFFCCBC},
            assignedDates: const {},
            updatedAt: DateTime(2026, 9, 1))),
    'share_code': () => const MyShareCodeScreen(),
    'sleep_calendar': () => const SleepCalendarFullScreen(),
    for (final theme in kAllCalendarThemeIds)
      'calendar_${theme.name}': () => CalendarTab(),
    'calendar_unassigned': () => CalendarTab(),
  };
  for (final textScale in scaleSweep
      ? const String.fromEnvironment('LAYOUT_SCALE_VALUES',
              defaultValue: '1.0,1.1,1.2,1.3,1.4,1.5,1.6')
          .split(',')
          .map(double.parse)
      : [requestedTextScale]) {
    for (final entry in screens.entries) {
      testWidgets(
          '${entry.key}: scale $textScale fold windows and phone regression',
          (tester) async {
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            FlutterError.dumpErrorToConsole(details, forceReport: true);
          }
          previousErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        SharedPreferences.setMockInitialValues({
          'welcome_popup_shown': true,
          'shift_assign_tutorial_shown': true,
          'condition_tab_tutorial_shown': true,
          'schedule_tab_tutorial_shown': true,
          'one_touch_alarm_tutorial_shown': true,
          'all_teams_names': <String>['A', 'B', 'C', 'D'],
          'all_teams_offsets': '{"A":0,"B":1,"C":2,"D":0}',
          'all_teams_my_team': 'A',
          'schedule_tab_enabled': !entry.key.startsWith('settings'),
          'condition_tab_enabled': !entry.key.startsWith('settings'),
        });
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        if (entry.key == 'calendar_unassigned') {
          await tester.runAsync(() => DatabaseService.instance
              .saveShiftSchedule(ShiftSchedule(
                  isRegular: false, shiftTypes: ['주간', '야간', '휴무'])));
        } else {
          await tester.runAsync(() => DatabaseService.instance
              .saveShiftSchedule(ShiftSchedule(
                  isRegular: true,
                  pattern: shifts,
                  todayIndex: 0,
                  shiftTypes: shifts,
                  startDate: DateTime(2026, 9, 1))));
        }
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(kAlarmChannel, (call) async => null);
        if (entry.key == 'settings') {
          await tester.runAsync(
              () => DatabaseService.instance.replaceAllAlarmTemplates([
                    for (var i = 0; i < 5; i++)
                      {
                        'shift_type': shifts.first,
                        'time': '23:4$i',
                        'alarm_type_id': 3,
                        'day_offset': 0
                      },
                  ]));
        }
        final theme = kAllCalendarThemeIds
                .where((t) => entry.key == 'calendar_${t.name}')
                .firstOrNull ??
            kDefaultCalendarThemeId;
        final container = ProviderContainer(overrides: [
          calendarThemeProvider
              .overrideWith((ref) => CalendarThemeNotifier.withInitial(theme)),
          nextAlarmProvider.overrideWith((ref) => AsyncData(Alarm(
              id: 1,
              time: '09:30',
              date: DateTime.now().add(const Duration(hours: 4)),
              type: 'fixed',
              alarmTypeId: 1,
              shiftType: '주간'))),
        ]);
        addTearDown(container.dispose);
        for (final size in const bool.fromEnvironment('AUDIT_COMPACT_LAYOUT')
            ? const [
                Size(320, 640),
                Size(500, 800),
                Size(501, 800),
                Size(600, 800)
              ]
            : flipAudit && !const bool.fromEnvironment('LAYOUT_MEMO_GAP_MATRIX')
                ? [
                    Size(
                        double.parse(const String.fromEnvironment(
                            'LAYOUT_FLIP_WIDTH',
                            defaultValue: '360')),
                        double.parse(const String.fromEnvironment(
                            'LAYOUT_FLIP_HEIGHT',
                            defaultValue: '880'))),
                  ]
                : const [
                    Size(393, 852),
                    Size(411, 891), // S26 Ultra, 420 dpi display override
                    Size(400, 632),
                    Size(662, 876),
                    Size(360, 840),
                    Size(806, 895),
                    Size(895, 806),
                    Size(475.43, 751.24),
                    Size(932.57, 704),
                    Size(704, 932.57),
                    Size(752, 834.67),
                    Size(834.67, 752)
                  ]) {
          final ultraWindow = size == const Size(411, 891) ||
              size == const Size(752, 834.67) ||
              size == const Size(834.67, 752) ||
              size == const Size(360, 840);
          if (ultraOnly && !ultraWindow) continue;
          final srtlWindow = flipAudit ||
              (ultraOnly && ultraWindow) ||
              size.width == 475.43 ||
              size.width == 932.57 ||
              size.width == 704;
          if ((scaleSweep || const bool.fromEnvironment('LAYOUT_SRTL_ONLY')) &&
              (!srtlWindow || size.width == 704)) continue;
          final l = lookupAppLocalizations(const Locale(
              bool.fromEnvironment('LAYOUT_ENGLISH') ? 'en' : 'ko'));
          final adHeight = srtlWindow
              ? (size.width == 360
                  ? 56.0
                  : size.width < 500
                      ? 68.0
                      : 90.0)
              : 50.0;
          tester.view.physicalSize = size;
          await tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: ScreenUtilInit(
                  designSize: const Size(360, 780),
                  minTextAdapt: true,
                  splitScreenMode: true,
                  builder: (context, _) {
                    ScreenUtil.configure(
                        data: appContentMediaQuery(
                            MediaQueryData.fromView(View.of(context))),
                        designSize: const Size(360, 780),
                        minTextAdapt: true,
                        splitScreenMode: true);
                    final baseTheme =
                        theme.isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
                    return MaterialApp(
                        theme: capture
                            ? baseTheme.copyWith(
                                appBarTheme: baseTheme.appBarTheme.copyWith(
                                    titleTextStyle: baseTheme
                                        .appBarTheme.titleTextStyle
                                        ?.copyWith(
                                            fontFamily: 'LayoutPreview')),
                                dialogTheme: baseTheme.dialogTheme.copyWith(
                                  titleTextStyle: baseTheme
                                      .dialogTheme.titleTextStyle
                                      ?.copyWith(fontFamily: 'LayoutPreview'),
                                  contentTextStyle: baseTheme
                                      .dialogTheme.contentTextStyle
                                      ?.copyWith(fontFamily: 'LayoutPreview'),
                                ),
                                textTheme: baseTheme.textTheme
                                    .apply(fontFamily: 'LayoutPreview'),
                                primaryTextTheme: baseTheme.primaryTextTheme
                                    .apply(fontFamily: 'LayoutPreview'))
                            : baseTheme,
                        locale: entry.key == 'english_sleep' ||
                                const bool.fromEnvironment('LAYOUT_ENGLISH')
                            ? const Locale('en')
                            : const Locale('ko'),
                        localizationsDelegates: const [
                          AppLocalizations.delegate,
                          GlobalMaterialLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          GlobalCupertinoLocalizations.delegate
                        ],
                        supportedLocales: AppLocalizations.supportedLocales,
                        builder: (context, child) => RepaintBoundary(
                            key: captureKey,
                            child: MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                    textScaler:
                                        TextScaler.linear(srtlWindow ? textScale : 1)),
                                child: AppContentFrame(child: child!))),
                        home: ['next', 'settings', 'condition', 'english_sleep', 'schedule'].contains(entry.key) || entry.key.startsWith('calendar_') ? Scaffold(resizeToAvoidBottomInset: false, body: Padding(padding: EdgeInsets.only(top: srtlWindow ? 40 : 0), child: entry.value()), bottomNavigationBar: SizedBox(height: ((entry.key == 'next' || entry.key == 'settings') ? 56 : 56 + adHeight) + (srtlWindow ? 48 : 0))) : entry.value());
                  })));
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 80)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (reviewMonth != 0 && entry.key.startsWith('calendar_')) {
            tester
                .widget<TableCalendar>(find.byType(TableCalendar).first)
                .onPageChanged!(auditMonth);
            await tester.runAsync(() => container
                .read(memoProvider.notifier)
                .loadMemosForDateRange(
                    DateTime(auditMonth.year, auditMonth.month),
                    DateTime(auditMonth.year, auditMonth.month + 1, 0)));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull, reason: '${entry.key} $size');
          if (ultraOnly && entry.key == 'next') {
            for (final scroll
                in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
              expect(scroll.position.maxScrollExtent, 0,
                  reason:
                      'Next alarm must fit without scrolling at $size / $textScale');
            }
          }
          Future<void> captureScreen([String suffix = '']) async {
            if (!capture) return;
            final boundary = captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final dir = Directory('build/fold_layout_previews');
              await dir.create(recursive: true);
              await File(
                      '${dir.path}/${entry.key}${suffix}_${size.width.toInt()}x${size.height.toInt()}_scale$textScale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await captureScreen();
          if (entry.key == 'settings_features') {
            for (final title in ['일정관리 기능', '수면회복 컨디션 기능', '진단 로그 이메일로 보내기']) {
              await tester.ensureVisible(find.text(title));
              await tester.tap(find.text(title));
              await tester.pumpAndSettle();
              expect(find.byType(AlertDialog), findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.tap(find.text('취소').last);
              await tester.pumpAndSettle();
              expect(container.read(optionalTabActivationProvider), isNull);
            }
          }
          if (srtlWindow &&
              entry.key.startsWith('calendar_') &&
              entry.key != 'calendar_unassigned') {
            final now = auditMonth;
            Rect paintedRect(Finder finder) {
              final box = tester.renderObject<RenderBox>(finder);
              return MatrixUtils.transformRect(
                  box.getTransformTo(null), Offset.zero & box.size);
            }

            for (final day
                in flipAudit ? auditDays.keys : {now.day, 23, 24, 25}) {
              final date =
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final cell = find.byKey(ValueKey('calendar-cell-$date')).first;
              final dateText =
                  find.descendant(of: cell, matching: find.text('$day')).first;
              final dateRect = paintedRect(dateText);
              final cellRect = paintedRect(cell);
              if (scaleSweep && !flipAudit) {
                final key = '${entry.key}:$size:$day';
                if (textScale == 1.0)
                  baselineCellHeights[key] = cellRect.height;
                final baseline = baselineCellHeights[key];
                if (baseline != null)
                  expect(cellRect.height,
                      closeTo(baseline, size.width <= 500 ? 2.0 : 0.2),
                      reason:
                          'Auxiliary text must not steal calendar height as text grows');
              }
              final badge = find.descendant(
                  of: cell,
                  matching: find.byKey(const ValueKey('shift-badge-content')));
              final badgeText = find.descendant(
                  of: cell,
                  matching: find.byKey(const ValueKey('shift-badge-text')));
              if (badge.evaluate().isNotEmpty) {
                expect(paintedRect(badgeText).center.dx,
                    closeTo(paintedRect(badge).center.dx, 0.1),
                    reason:
                        '$theme shift label must remain horizontally centered');
                expect(paintedRect(badgeText).center.dy,
                    closeTo(paintedRect(badge).center.dy, 0.1),
                    reason:
                        '$theme shift label must remain vertically centered');
              }
              if (longShiftNames &&
                  ![
                    CalendarThemeId.initialBadge,
                    CalendarThemeId.underline,
                    CalendarThemeId.editorial,
                  ].contains(theme)) {
                final shift = ShiftSchedule(
                        isRegular: true,
                        pattern: shifts,
                        todayIndex: 0,
                        shiftTypes: shifts,
                        startDate: DateTime(2026, 9, 1))
                    .getShiftForDate(DateTime(now.year, now.month, day));
                final shiftText =
                    find.descendant(of: cell, matching: find.text(shift));
                expect(shiftText, findsOneWidget,
                    reason: 'Complete shift name must be retained');
                expect(
                    paintedRect(shiftText)
                        .deflate(0.05)
                        .overlaps(dateRect.deflate(0.05)),
                    isFalse,
                    reason: '$theme date/shift text overlap');
              }
              final holidayLabel = getHolidayName(
                  DateTime(now.year, now.month, day),
                  isKorean: true);
              final annotation = find.descendant(
                  of: cell, matching: find.text(holidayLabel ?? '추석'));
              if (annotation.evaluate().isNotEmpty) {
                expect(
                    paintedRect(annotation.first)
                        .deflate(0.05)
                        .overlaps(dateRect.deflate(0.05)),
                    isFalse,
                    reason: '$theme $size holiday overlaps date');
              }
              if (reviewMonth != 0) {
                Rect? badgeRect = badge.evaluate().isNotEmpty
                    ? paintedRect(badge.first)
                    : null;
                final renderedShift = badgeText.evaluate().isNotEmpty
                    ? tester.widget<Text>(badgeText.first)
                    : null;
                print('REVIEW_METRICS ${jsonEncode({
                      'theme': theme.name,
                      'windowWidth': size.width,
                      'windowHeight': size.height,
                      'day': day,
                      'cellWidth': cellRect.width,
                      'cellHeight': cellRect.height,
                      'dateWidth': dateRect.width,
                      'dateHeight': dateRect.height,
                      'dateTop': dateRect.top - cellRect.top,
                      'dateLeft': dateRect.left - cellRect.left,
                      'badgeWidth': badgeRect?.width,
                      'badgeHeight': badgeRect?.height,
                      'shift': renderedShift?.data,
                      'shiftFont': renderedShift?.style?.fontSize,
                    })}');
                if (day == 13 &&
                    theme != CalendarThemeId.boldGrid &&
                    ![CalendarThemeId.underline, CalendarThemeId.editorial]
                        .contains(theme)) {
                  expect(
                      find.descendant(of: cell, matching: find.text('부처님오신날')),
                      findsOneWidget,
                      reason: 'Six-character holiday must remain complete');
                }
              }
              if (reviewMonth == 5 &&
                  day == 13 &&
                  theme == CalendarThemeId.boldGrid) {
                expect(
                    find.descendant(
                        of: cell,
                        matching: find.byWidgetPredicate((w) =>
                            w is Text &&
                            (w.data?.startsWith('부처님오신') ?? false))),
                    findsOneWidget);
              }
              Rect? previous;
              for (final memo in (reviewMonth == 0
                      ? ['첫째', '둘째', '셋째']
                      : ['첫째메모여섯', '둘째메모여섯', '셋째메모여섯'])
                  .take(flipAudit
                      ? auditDays[day]!
                      : day == 23
                          ? 1
                          : day == 24
                              ? 2
                              : 3)) {
                final label = memo;
                final text = find.descendant(
                    of: cell,
                    matching: find.byWidgetPredicate((widget) =>
                        widget is Text &&
                        widget.data != null &&
                        label.startsWith(widget.data!) &&
                        widget.data!.contains(memo.characters.first)));
                expect(text, findsOneWidget, reason: '$theme $size $label');
                if (AppLayout(size).isBalancedInner &&
                    badgeText.evaluate().isNotEmpty) {
                  expect(
                      tester.widget<Text>(text).style!.fontSize!,
                      lessThanOrEqualTo(tester
                              .widget<Text>(badgeText.first)
                              .style!
                              .fontSize! +
                          0.01),
                      reason:
                          'Expanded memo must not exceed the nominal shift font');
                }
                if (day == 23 && !flipAudit) {
                  final longCell = find
                      .byKey(ValueKey(
                          'calendar-cell-${now.year}-${now.month.toString().padLeft(2, '0')}-22'))
                      .first;
                  final longMemo = find.descendant(
                      of: longCell,
                      matching: find.byWidgetPredicate((widget) =>
                          widget is Text &&
                          (widget.data?.startsWith(
                                  tester.widget<Text>(text).data!) ??
                              false)));
                  expect(longMemo, findsOneWidget);
                  expect(tester.widget<Text>(longMemo).style!.fontSize,
                      tester.widget<Text>(text).style!.fontSize,
                      reason: 'Memo length must never reduce font size');
                }
                if (reviewMonth != 0 &&
                    size.width <= 500 &&
                    ![CalendarThemeId.underline, CalendarThemeId.editorial]
                        .contains(theme)) {
                  expect(tester.widget<Text>(text).data, memo,
                      reason: 'All six Korean memo characters must fit');
                }
                final rect = paintedRect(text);
                if (reviewMonth != 0) {
                  print('REVIEW_MEMO_METRICS ${jsonEncode({
                        'theme': theme.name,
                        'windowWidth': size.width,
                        'windowHeight': size.height,
                        'day': day,
                        'memoIndex': previous == null ? 0 : 1,
                        'cellWidth': cellRect.width,
                        'cellHeight': cellRect.height,
                        'memoHeight': rect.height,
                        'memoWidth': rect.width,
                        'memoFontCode':
                            tester.widget<Text>(text).style!.fontSize,
                        'gapFromDate': rect.top - dateRect.bottom,
                        'gapFromPrevious': previous == null
                            ? null
                            : rect.top - previous.bottom,
                        'gapToCellBottom': cellRect.bottom - rect.bottom,
                      })}');
                }
                if (scaleSweep && day == now.day && memo == '첫째') {
                  print(
                      'CELL_METRICS ${theme.name} scale=$textScale width=${size.width} '
                      'cell=${cellRect.height.toStringAsFixed(2)} '
                      'date=${dateRect.height.toStringAsFixed(2)} '
                      'memo=${rect.height.toStringAsFixed(2)}');
                }
                if (WideCalendarCell.appliesTo(size)) {
                  final split = cellRect.left + cellRect.width * .4;
                  expect(rect.left, greaterThanOrEqualTo(split),
                      reason: 'Wide memos belong in the right 60 percent');
                  expect(dateRect.right, lessThanOrEqualTo(split),
                      reason: 'Wide date belongs in the left 40 percent');
                  expect(rect.overlaps(dateRect), isFalse);
                } else {
                  expect(rect.top, greaterThanOrEqualTo(dateRect.bottom - 0.1),
                      reason: '$theme $size date covered by memo');
                }
                expect(rect.bottom, lessThanOrEqualTo(cellRect.bottom + 0.1));
                if (annotation.evaluate().isNotEmpty) {
                  expect(
                      rect.deflate(0.05).overlaps(
                          paintedRect(annotation.first).deflate(0.05)),
                      isFalse,
                      reason: '$theme $size holiday overlaps memo');
                }
                if (previous != null)
                  expect(rect.top, greaterThanOrEqualTo(previous.bottom - 0.1));
                previous = rect;
              }
              if (theme == CalendarThemeId.editorial) {
                expect(
                    find.descendant(of: cell, matching: find.byType(ClipPath)),
                    findsOneWidget,
                    reason: 'Magazine must retain its shift-color triangle');
              }
              if (theme == CalendarThemeId.diary &&
                  !WideCalendarCell.appliesTo(size)) {
                expect(
                    find.descendant(
                        of: cell, matching: find.byType(VerticalDivider)),
                    findsOneWidget,
                    reason: 'Diary must retain its split date/shift header');
              }
            }
          }
          if (scaleSweep || const bool.fromEnvironment('LAYOUT_GEOMETRY_ONLY'))
            continue;
          Future<void> settlePopup() async {
            for (var i = 0; i < 6; i++) {
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 80)));
              await tester.pump(const Duration(milliseconds: 200));
            }
            expect(tester.takeException(), isNull,
                reason: '${entry.key} popup $size');
          }

          if (entry.key.startsWith('calendar_') &&
              entry.key != 'calendar_unassigned') {
            expect(find.byKey(const ValueKey('one-tap-open')), findsNothing);
            expect(
                tester
                    .widget<TableCalendar>(find.byType(TableCalendar))
                    .availableGestures,
                AvailableGestures.all);
          }

          if (entry.key == 'calendar_mainWhite') {
            final navigator =
                tester.state<NavigatorState>(find.byType(Navigator).first);
            final now = auditMonth;
            await tester.tap(find.text('${now.year}년 ${now.month}월'));
            await settlePopup();
            expect(find.text('12월').hitTestable(), findsOneWidget);
            await captureScreen('_month');
            navigator.pop();
            await settlePopup();
            final calendar =
                tester.widget<TableCalendar>(find.byType(TableCalendar));
            calendar.onDaySelected!(DateTime(now.year, now.month, 15), now);
            await settlePopup();
            await captureScreen('_date');
            final memoField = find.byType(TextField).last;
            await tester.ensureVisible(memoField);
            await tester.showKeyboard(memoField);
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            await settlePopup();
            expect(tester.getRect(memoField).bottom,
                lessThanOrEqualTo(size.height - 280),
                reason: 'memo input must remain above the keyboard on $size');
            if (size == const Size(411, 891)) {
              final gap = size.height - 280 - tester.getRect(memoField).bottom;
              expect(gap, inInclusiveRange(8.0, 110.0),
                  reason: 'S26 memo input should stay near the keyboard');
              expect(
                  tester.getRect(find.byType(BottomSheet)).top, greaterThan(80),
                  reason: 'S26 memo sheet should leave calendar visible');
            }
            await captureScreen('_keyboard');
            FocusManager.instance.primaryFocus?.unfocus();
            tester.view.resetViewInsets();
            await settlePopup();
            navigator.pop();
            await settlePopup();
          }
          if (entry.key == 'calendar_mainWhite') {
            final now = auditMonth;
            await tester.runAsync(() => DatabaseService.instance.insertAlarm(
                Alarm(
                    time: '12:34',
                    date: DateTime(now.year, now.month, now.day, 12, 34),
                    type: 'custom',
                    alarmTypeId: 3)));
            tester.view.viewPadding = const FakeViewPadding(bottom: 24);
            tester.view.padding = const FakeViewPadding(bottom: 24);
            final calendar =
                tester.widget<TableCalendar>(find.byType(TableCalendar));
            calendar.onDaySelected!(now, now);
            await settlePopup();
            final sheet = find.byType(BottomSheet);
            final scroll = tester.state<ScrollableState>(find
                .descendant(
                    of: find.byKey(const ValueKey('calendar-detail-scroll')),
                    matching: find.byType(Scrollable))
                .first);
            scroll.position.jumpTo(scroll.position.maxScrollExtent);
            await tester.pump();
            final lastMemo =
                find.descendant(of: sheet, matching: find.text('셋째'));
            expect(lastMemo, findsOneWidget);
            expect(tester.getRect(lastMemo).bottom,
                lessThanOrEqualTo(size.height - 24 - 12),
                reason:
                    'Third memo must fully clear the navigation area at maximum scroll');
            Navigator.of(tester.element(lastMemo)).pop();
            await settlePopup();
            tester.view.resetViewPadding();
            tester.view.resetPadding();
          }
          if (entry.key == 'sleep_calendar') {
            final navigator =
                tester.state<NavigatorState>(find.byType(Navigator).first);
            final now = auditMonth;
            showSleepSlotEditDialog(
                tester.element(find.byType(SleepCalendarFullScreen)),
                initialStart: now.subtract(const Duration(hours: 8)),
                initialEnd: now.subtract(const Duration(hours: 1)));
            await settlePopup();
            await captureScreen('_editor');
            navigator.pop();
            await settlePopup();
          }
          if (entry.key == 'settings') {
            final navigator =
                tester.state<NavigatorState>(find.byType(Navigator).first);
            Future<void> settlePanel() async {
              for (var i = 0; i < 6; i++) {
                await tester.runAsync(() =>
                    Future<void>.delayed(const Duration(milliseconds: 80)));
                await tester.pump(const Duration(milliseconds: 200));
              }
              expect(tester.takeException(), isNull,
                  reason: 'settings panel $size');
            }

            for (final title in [
              l.settingsEditShiftNameTitle,
              l.settingsEditShiftColorTitle,
              l.shiftChangeSchedule,
              l.settingsEditFixedAlarmTitle
            ]) {
              await tester.ensureVisible(
                  find.text(l.settingsShiftManagementEditButton));
              await tester.tap(find.text(l.settingsShiftManagementEditButton));
              await settlePanel();
              await tester.ensureVisible(find.text(title));
              await settlePanel();
              await tester.tap(find.text(title));
              await settlePanel();
              await captureScreen('_${title == l.shiftChangeSchedule ? 'schedule' : title == l.settingsEditShiftNameTitle ? 'names' : title == l.settingsEditShiftColorTitle ? 'colors' : 'fixed'}');
              if (title == l.settingsEditShiftColorTitle) {
                await tester.tap(find.widgetWithText(ListTile, '주간').first);
                await settlePanel();
                navigator.pop();
                await settlePanel();
              }
              if (title == l.settingsEditFixedAlarmTitle) {
                await tester.tap(find.text(shifts.first).hitTestable().first);
                await settlePanel();
                expect(find.text('23:40').hitTestable(), findsOneWidget);
                expect(tester.takeException(), isNull,
                    reason: 'Five-alarm editor must fit $size / $textScale');
                navigator.pop();
                await settlePanel();
              }
              navigator.pop();
              await settlePanel();
            }
            for (final title in [
              l.alarmSoundManage,
              l.alarmDeleteAllPermanently,
              l.settingsAdditionalFeaturesTitle
            ]) {
              await tester.scrollUntilVisible(find.text(title), 250,
                  scrollable: find.byType(Scrollable).first, maxScrolls: 30);
              await Scrollable.ensureVisible(tester.element(find.text(title)),
                  alignment: 0.5);
              await settlePanel();
              expect(find.text(title).hitTestable(), findsOneWidget);
              await tester.tap(find.text(title));
              await settlePanel();
              await captureScreen('_${title == l.alarmSoundManage ? 'alarm_settings' : title == l.settingsAdditionalFeaturesTitle ? 'features' : 'delete'}');
              if (title == l.settingsAdditionalFeaturesTitle) {
                await tester.tap(find.text(l.settingsDataBackupTitle));
                await settlePanel();
                await captureScreen('_backup');
                await tester.tap(find.text(l.settingsRestoreFromBackupTitle));
                await settlePanel();
                navigator.pop();
                await settlePanel();
                navigator.pop();
                await settlePanel();
              }
              navigator.pop();
              await settlePanel();
            }
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pump();
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
