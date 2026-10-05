import 'dart:io';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/main.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/providers/alarm_provider.dart';
import 'package:shiftbell/providers/calendar_theme_provider.dart';
import 'package:shiftbell/screens/calendar_tab.dart';
import 'package:shiftbell/screens/calendar_theme_picker_screen.dart';
import 'package:shiftbell/screens/next_alarm_tab.dart';
import 'package:shiftbell/screens/settings_tab.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/screens/permission_intro_screen.dart';
import 'package:shiftbell/screens/work_hours_settings_screen.dart';
import 'package:shiftbell/screens/all_teams_setup_screen.dart';
import 'package:shiftbell/screens/team_schedule_edit_screen.dart';
import 'package:shiftbell/screens/all_shifts_view.dart';
import 'package:shiftbell/screens/all_alarms_history_view.dart';
import 'package:shiftbell/screens/memo_list_view.dart';
import 'package:shiftbell/screens/help_screen.dart';
import 'package:shiftbell/screens/privacy_policy_screen.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/theme/app_theme.dart';
import 'package:shiftbell/widgets/app_content_frame.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  late Directory databaseDirectory;
  const shifts = bool.fromEnvironment('AUDIT_LONG_SHIFT_NAMES')
      ? ['Afternoon Shift', 'WWWWWWWWWWWWWWWW', 'Sleepover Shift']
      : ['Day Shift', 'Night duty', 'Day Off'];
  const capture = bool.fromEnvironment('CAPTURE_ENGLISH');
  const newLocales = bool.fromEnvironment('AUDIT_NEW_LOCALES');
  const windows = [
    if (bool.fromEnvironment('AUDIT_COMPACT_LAYOUT')) ...[
      Size(320, 640), Size(500, 800), Size(501, 800), Size(600, 800),
    ] else ...[
    Size(411, 891), // Existing S26 Ultra DEV reference, not a new device claim.
    Size(360, 840), // Fold Ultra cover reference.
    Size(752, 834.67), Size(834.67, 752), // Fold Ultra inner / landscape.
    Size(475.43, 751.24), // Existing Fold8 cover reference.
    Size(704, 932.57), Size(932.57, 704), // Fold8 inner / landscape.
    ],
  ];
  const locales = newLocales
      ? [Locale('de', 'DE'), Locale('pt', 'BR')]
      : [Locale('en', 'US'), Locale('en', 'GB')];
  setUpAll(() async {
    await initializeDateFormatting();
    // Actual glyph metrics instead of the square test font. Screenshots remain
    // local previews, not Samsung screenshots.
    final body = await File(Platform.isWindows
            ? 'C:/Windows/Fonts/segoeui.ttf'
            : 'test/fixtures/layout_fonts/Quicksand-Bold.ttf')
        .readAsBytes();
    await (FontLoader('EnglishPreview')
          ..addFont(Future.value(ByteData.sublistView(body))))
        .load();
    // Explicit AppBar/monospace styles bypass ThemeData.textTheme. Replace
    // the test-only Ahem fallback there too, so titles use readable glyphs.
    for (final family in ['Ahem', 'Roboto', 'monospace', 'serif']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(body))))
          .load();
    }
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    final quicksand =
        await File('test/fixtures/layout_fonts/Quicksand-Bold.ttf')
            .readAsBytes();
    final jua =
        await File('test/fixtures/layout_fonts/Jua-Regular.ttf').readAsBytes();
    font_loader.httpClient = MockClient((request) async => http.Response.bytes(
        request.url.path.contains('a083a3') ? jua : quicksand, 200));
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory =
        await Directory.systemTemp.createTemp('english_release_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => databaseDirectory.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, (call) async =>
            call.method == 'checkExactAlarmPermission' ? true : null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'plugins.flutter.io/google_mobile_ads/ump',
            (_) async => const StandardMethodCodec().encodeSuccessEnvelope(false));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/google_mobile_ads'),
            (call) async => null);
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    DatabaseService.debugIsAndroidOverride = false;
    firebaseReady = false;
    await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
        isRegular: true,
        pattern: shifts,
        todayIndex: 0,
        shiftTypes: shifts,
        shiftDurations: {shifts[0]: 480, shifts[1]: 720, shifts[2]: 0},
        startDate: DateTime(2026, 9, 1)));
    final today = DateTime.now();
    for (var day = 1; day <= 28; day++) {
      final key =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      for (final note in ['Dentist at 10:30', 'School pickup', 'Bring ID']
          .take(day % 3 + 1)) {
        await DatabaseService.instance.createMemo(key, note);
      }
      if (day == 2) await DatabaseService.instance.adjustOvertime(key, 90);
    }
    await DatabaseService.instance.insertAlarm(Alarm(
        time: '09:30',
        date: today.add(const Duration(days: 1)),
        type: 'fixed',
        alarmTypeId: 1,
        shiftType: shifts.first));
    for (final type in [2, 3]) {
      await DatabaseService.instance.insertAlarm(Alarm(
          time: '10:0$type',
          date: today.add(Duration(days: 1, minutes: type)),
          type: 'custom',
          alarmTypeId: type));
    }
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await databaseDirectory.delete(recursive: true);
  });

  final screens = <String, Widget Function()>{
    for (final theme in kEnglishCalendarThemeIds)
      'calendar_${theme.name}': () => CalendarTab(),
    'next': () => const NextAlarmTab(),
    'alarm_list': () => const NextAlarmTab(),
    'date_alarm_popup': () => CalendarTab(),
    'snoozed_next': () => const NextAlarmTab(),
    'settings': () => SettingsTab(),
    'onboarding': () => const OnboardingScreen(),
    // Exercise the same settings/onboarding paths in English and new locales.
    ...{
      'settings_sounds': () => SettingsTab(),
      for (final key in ['settings_schedule_menu', 'settings_shift_names',
        'settings_fixed_alarms', 'settings_fixed_dialog', 'settings_reset_confirm'])
        key: () => SettingsTab(),
      for (final key in ['team_edit', 'team_switch', 'team_recreate_confirm'])
        key: () => TeamScheduleEditScreen(
            teams: const TeamScheduleConfig(names: ['A', 'B', 'C'],
                offsets: {'A': 0, 'B': 1, 'C': 2}, myTeam: 'A'),
            pattern: shifts, date: DateTime(2026, 10, 5)),
      'onboarding_pattern': () => const OnboardingScreen(),
      'onboarding_today': () => const OnboardingScreen(),
      'onboarding_alarms': () => const OnboardingScreen(),
      'onboarding_alarm_dialog': () => const OnboardingScreen(),
      'onboarding_irregular': () => const OnboardingScreen(),
    },
    'permission': () => const PermissionIntroScreen(),
    'work_hours': () => const WorkHoursSettingsScreen(),
    'work_hours_period': () => const WorkHoursSettingsScreen(),
    'overtime_summary': () => CalendarTab(),
    'weekly_hours': () => CalendarTab(),
    'help_team_change': () => HelpDetailScreen(topic: HelpTopic(
        titleKey: (l) => l.helpShiftTeamChangeTitle,
        bodyKey: (l) => l.helpShiftTeamChangeBody)),
    'themes': () => const CalendarThemePickerScreen(),
    'teams': () => const AllTeamsSetupScreen(pattern: shifts, myTodayIndex: 0),
    'all_shifts': () => const AllShiftsView(),
    'history': () => const AllAlarmsHistoryView(),
    'notes': () => const MemoListView(),
    'help': () => const HelpScreen(),
    'privacy': () => const PrivacyPolicyScreen(),
    'alarm_editor': () => Scaffold(
        body: AlarmTimePicker(
            shiftName: 'Night duty',
            initialTime: const TimeOfDay(hour: 23, minute: 55),
            onTimeSelected: (_, offset) {})),
    'navigation': () => const MainScreen(initialIndex: 1),
  };
  for (final locale in locales) {
    for (final entry in screens.entries) {
      testWidgets('$locale ${entry.key} release layout', (tester) async {
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          FlutterError.dumpErrorToConsole(details, forceReport: true);
          previousErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        SharedPreferences.setMockInitialValues({
          'welcome_popup_shown': true,
          'shift_assign_tutorial_shown': true,
          'all_teams_names': <String>['A', 'B', 'C'],
          'all_teams_offsets': '{"A":0,"B":1,"C":2}',
          'all_teams_my_team': 'A',
        });
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final selected = kEnglishCalendarThemeIds
                .where((t) => entry.key == 'calendar_${t.name}')
                .firstOrNull ??
            kDefaultCalendarThemeId;
        final container = ProviderContainer(overrides: [
          calendarThemeProvider.overrideWith(
              (ref) => CalendarThemeNotifier.withInitial(selected)),
          nextAlarmProvider.overrideWith((ref) => AsyncData(Alarm(
              id: 1,
              time: '09:30',
              date: entry.key == 'snoozed_next'
                  ? tz.TZDateTime.from(DateTime.parse('2026-11-01T01:04:00-04:00'), tz.getLocation('America/New_York'))
                  : DateTime.now().add(const Duration(hours: 8)),
              type: entry.key == 'snoozed_next' ? 'snoozed' : 'fixed',
              alarmTypeId: 1,
              shiftType: 'Night duty'))),
        ]);
        final boundaryKey = GlobalKey();
        try {
          for (final size in windows) {
            for (final scale in [1.0, 1.3]) {
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
                        final base = selected.isDark
                            ? AppTheme.darkTheme
                            : AppTheme.lightTheme;
                        return MaterialApp(
                            locale: locale,
                            supportedLocales: locales,
                            localizationsDelegates: const [
                              AppLocalizations.delegate,
                              GlobalMaterialLocalizations.delegate,
                              GlobalWidgetsLocalizations.delegate,
                              GlobalCupertinoLocalizations.delegate
                            ],
                            theme: base.copyWith(
                                dialogTheme: base.dialogTheme.copyWith(
                                    titleTextStyle: base.dialogTheme.titleTextStyle
                                        ?.copyWith(fontFamily: 'EnglishPreview'),
                                    contentTextStyle: base.dialogTheme.contentTextStyle
                                        ?.copyWith(fontFamily: 'EnglishPreview')),
                                elevatedButtonTheme: ElevatedButtonThemeData(
                                    style: base.elevatedButtonTheme.style?.copyWith(
                                        textStyle: WidgetStatePropertyAll(
                                            (base.elevatedButtonTheme.style?.textStyle?.resolve({}) ??
                                                    const TextStyle())
                                                .copyWith(fontFamily: 'EnglishPreview')))),
                                appBarTheme: base.appBarTheme.copyWith(
                                    titleTextStyle: base.appBarTheme.titleTextStyle
                                        ?.copyWith(fontFamily: 'EnglishPreview')),
                                textTheme: base.textTheme
                                    .apply(fontFamily: 'EnglishPreview')),
                            builder: (context, child) => RepaintBoundary(
                                key: boundaryKey,
                                child: MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                        textScaler: TextScaler.linear(scale)),
                                    child: AppContentFrame(child: child!))),
                            home: Scaffold(
                                body: Padding(
                                    padding: const EdgeInsets.only(top: 32),
                                    child: entry.value()),
                                bottomNavigationBar: SizedBox(
                                    height: entry.key.startsWith('calendar_')
                                        ? 140
                                        : 24)));
                      })));
              for (var i = 0; i < 4; i++) {
                await tester.runAsync(() =>
                    Future<void>.delayed(const Duration(milliseconds: 60)));
                await tester.pump(const Duration(milliseconds: 150));
              }
              expect(tester.takeException(), isNull,
                  reason: '$locale ${entry.key} $size scale=$scale');
              if (entry.key == 'work_hours_period') {
                final l = lookupAppLocalizations(locale);
                final target = find.text(l.settingsPaydayBasis);
                // Wide sections live inside a Wrap. Scroll by actual gestures
                // until the option is hittable, not merely built off-screen.
                for (var i = 0; i < 20 && target.hitTestable().evaluate().isEmpty; i++) {
                  await tester.drag(find.byType(Scrollable).first,
                      const Offset(0, -250));
                  await tester.pumpAndSettle();
                }
                expect(target.hitTestable(), findsOneWidget);
                await tester.tap(target.hitTestable());
                await tester.pumpAndSettle();
                expect(find.text(l.settingsPeriodStartBasis), findsOneWidget);
                expect(tester.takeException(), isNull,
                    reason: '$locale custom monthly period $size scale=$scale');
              }
              if (entry.key == 'overtime_summary' || entry.key == 'weekly_hours') {
                final l = lookupAppLocalizations(locale);
                final target = find.textContaining(entry.key == 'overtime_summary'
                    ? l.shiftThisMonthOt : l.shiftWeeklyWorkHours).first;
                await tester.ensureVisible(target);
                await tester.tap(target);
                for (var i = 0; i < 6; i++) {
                  await tester.runAsync(() => Future<void>.delayed(
                      const Duration(milliseconds: 60)));
                  await tester.pump(const Duration(milliseconds: 150));
                }
                expect(find.byType(DraggableScrollableSheet), findsOneWidget,
                    reason: 'The ${entry.key} sheet must actually be open');
                expect(tester.takeException(), isNull,
                    reason: '$locale ${entry.key} detail $size scale=$scale');
              }
              if (entry.key == 'settings_sounds') {
                final target = find.text(lookupAppLocalizations(locale).alarmSoundManage);
                await tester.ensureVisible(target);
                await tester.tap(target);
                for (var i = 0; i < 4; i++) {
                  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
                  await tester.pump(const Duration(milliseconds: 150));
                }
                expect(tester.takeException(), isNull,
                    reason: '$locale settings sounds $size scale=$scale');
              }
              if (entry.key.startsWith('settings_') && entry.key != 'settings_sounds') {
                final l = lookupAppLocalizations(locale);
                Future<void> tapLabel(String label) async {
                  final target = find.text(label).last;
                  await tester.ensureVisible(target);
                  await tester.tap(target);
                  for (var i = 0; i < 4; i++) {
                    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
                    await tester.pump(const Duration(milliseconds: 150));
                  }
                  expect(tester.takeException(), isNull,
                      reason: '$locale ${entry.key} $label $size scale=$scale');
                }
                if (entry.key == 'settings_reset_confirm') {
                  await tapLabel(l.shiftResetSchedule);
                } else {
                  await tapLabel(l.commonEdit);
                  if (entry.key == 'settings_shift_names') {
                    await tapLabel(l.settingsEditShiftNameTitle);
                  } else if (entry.key.startsWith('settings_fixed')) {
                    await tapLabel(l.settingsEditFixedAlarmTitle);
                    // A slow SQLite read must not let a loading spinner pass as
                    // a successful layout of the long-name alarm cards.
                    final fixedCard = find.descendant(
                        of: find.byType(GridView),
                        matching: find.text(shifts[1]));
                    for (var i = 0;
                        i < 60 && fixedCard.evaluate().isEmpty;
                        i++) {
                      await tester.runAsync(() => Future<void>.delayed(
                          const Duration(milliseconds: 50)));
                      await tester.pump(const Duration(milliseconds: 50));
                    }
                    expect(fixedCard, findsOneWidget);
                    expect(tester.takeException(), isNull,
                        reason: '$locale fixed cards $size scale=$scale');
                    if (entry.key == 'settings_fixed_dialog') await tapLabel(shifts[1]);
                  }
                }
              }
              if (entry.key == 'team_switch' || entry.key == 'team_recreate_confirm') {
                await tester.tap(find.byKey(ValueKey(entry.key == 'team_switch'
                    ? 'team-edit-switch' : 'team-edit-recreate')));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull,
                    reason: '$locale ${entry.key} $size scale=$scale');
              }
              if (entry.key.startsWith('onboarding_')) {
                final l = lookupAppLocalizations(locale);
                Future<void> tapLabel(String label) async {
                  final target = find.text(label).last;
                  await tester.ensureVisible(target);
                  await tester.tap(target);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull,
                      reason: '$locale ${entry.key} $label $size scale=$scale');
                }
                await tapLabel(l.commonNext);
                if (entry.key == 'onboarding_irregular') {
                  final target = find.byWidgetPredicate((widget) =>
                      widget is Semantics &&
                      widget.properties.label == l.onboardingIrregularChoiceTitle);
                  await tester.ensureVisible(target);
                  await tester.tap(target);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull,
                      reason: '$locale irregular $size scale=$scale');
                } else if (entry.key != 'onboarding_pattern') {
                  await tapLabel(l.shiftDay);
                  await tapLabel(l.shiftNight);
                  await tapLabel(l.shiftDayOff);
                  await tapLabel(l.commonNext);
                  if (entry.key != 'onboarding_today') {
                    await tapLabel(l.shiftDay);
                    await tapLabel(l.commonNext);
                    if (entry.key == 'onboarding_alarm_dialog') {
                      await tapLabel(l.shiftDay);
                    }
                  }
                }
              }
              if (entry.key == 'alarm_list') {
                await tester.tap(find.text(
                    lookupAppLocalizations(locale).alarmViewAllRegistered));
                for (var i = 0; i < 4; i++) {
                  await tester.runAsync(() => Future<void>.delayed(
                      const Duration(milliseconds: 60)));
                  await tester.pump(const Duration(milliseconds: 150));
                }
                expect(tester.takeException(), isNull,
                    reason: '$locale registered alarm list $size scale=$scale');
              }
              if (entry.key == 'date_alarm_popup') {
                final calendar = tester.widget<TableCalendar>(find.byType(TableCalendar));
                final tomorrow = DateTime.now().add(const Duration(days: 1));
                calendar.onDaySelected!(tomorrow, tomorrow);
                for (var i = 0; i < 4; i++) {
                  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
                  await tester.pump(const Duration(milliseconds: 150));
                }
                await tester.tap(find.text('09:30').last);
                await tester.pumpAndSettle();
                expect(find.text(lookupAppLocalizations(locale).calendarSelectAlarmType), findsOneWidget);
                expect(tester.takeException(), isNull,
                    reason: '$locale date alarm popup $size scale=$scale');
              }
              if (entry.key.startsWith('calendar_')) {
                expect(
                    find.byKey(const ValueKey('one-tap-open')), findsNothing);
                expect(find.byIcon(Icons.people_alt_outlined), findsNothing);
                final calendar =
                    tester.widget<TableCalendar>(find.byType(TableCalendar));
                expect(
                    calendar.startingDayOfWeek,
                    ['GB', 'DE'].contains(locale.countryCode)
                        ? StartingDayOfWeek.monday
                        : StartingDayOfWeek.sunday);
              }
              if (entry.key == 'snoozed_next') {
                expect(find.textContaining(lookupAppLocalizations(locale).alarmSnoozedLabel), findsWidgets);
                expect(find.textContaining(lookupAppLocalizations(locale).alarmClockFirstOccurrence), findsWidgets);
              }
              if (entry.key == 'help') {
                final strings = lookupAppLocalizations(locale);
                for (final title in [
                  strings.helpFriendSectionTitle,
                  strings.helpSleepSectionTitle,
                  strings.helpScheduleTabSectionTitle,
                  strings.helpConditionSectionTitle
                ]) {
                  expect(find.text(title), findsNothing);
                }
              }
              if (entry.key == 'navigation') {
                final navigation = tester.widget<BottomNavigationBar>(
                    find.byType(BottomNavigationBar));
                expect(navigation.items.map((item) => item.label).toList(),
                    [lookupAppLocalizations(locale).navNextAlarm,
                     lookupAppLocalizations(locale).navCalendar,
                     lookupAppLocalizations(locale).navSettings]);
                expect(
                    find.byKey(const ValueKey('one-tap-open')), findsNothing);
              }
              if (capture && (locale.countryCode == 'GB' || newLocales) &&
                  (!const bool.fromEnvironment('CAPTURE_COPY_REVIEW') ||
                      (size.width == 411 && scale == 1.3))) {
                final boundary = boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
                await tester.runAsync(() async {
                  final image = await boundary.toImage();
                  final bytes =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  final directory = Directory(const bool.fromEnvironment('CAPTURE_COPY_REVIEW')
                      ? 'build/localization_copy_2026-10-05/previews/$locale/$scale'
                      : newLocales
                      ? 'build/localized_release_previews/$locale/$scale' : 'build/english_release_previews');
                  await directory.create(recursive: true);
                  await File(
                          '${directory.path}/${entry.key}_${size.width.toInt()}x${size.height.toInt()}.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.runAsync(() =>
                  Future<void>.delayed(const Duration(milliseconds: 120)));
              await tester.pump(const Duration(seconds: 3));
            }
          }
        } finally {
          container.dispose();
        }
      });
    }
  }
  testWidgets('switching to English releases one-tap calendar gesture lock', (tester) async {
    SharedPreferences.setMockInitialValues({
      'welcome_popup_shown': true,
      'shift_assign_tutorial_shown': true,
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 891);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final container = ProviderContainer();
    Widget app(Locale locale) => UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(360, 780),
        builder: (context, _) => MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ko'), Locale('en', 'US')],
          localizationsDelegates: const [AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate],
          home: Scaffold(body: CalendarTab()),
        ),
      ),
    );
    try {
      await tester.pumpWidget(app(const Locale('ko')));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.tap(find.byKey(const ValueKey('one-tap-open')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<TableCalendar>(find.byType(TableCalendar)).availableGestures,
          AvailableGestures.none);
      await tester.pumpWidget(app(const Locale('en', 'US')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('one-tap-open')), findsNothing);
      expect(tester.widget<TableCalendar>(find.byType(TableCalendar)).availableGestures,
          isNot(AvailableGestures.none));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(seconds: 3));
    } finally {
      container.dispose();
    }
  });

  test('release regional defaults do not equate English with the US', () {
    for (final locale in [
      const Locale('en', 'US'),
      const Locale('en', 'GB'),
      const Locale('en', 'ZA'),
      const Locale('en', 'AE'),
      const Locale('en', 'PH'),
      const Locale('af', 'ZA'),
      const Locale('ar', 'AE'),
      const Locale('fil', 'PH'),
    ]) {
      expect(resolveReleaseLocale([locale], locales).languageCode, 'en');
    }
    for (final locale in [
      const Locale('en', 'GB'),
      const Locale('en', 'IE'),
      const Locale('fr', 'FR')
    ]) {
      expect(resolveReleaseLocale([locale], locales), const Locale('en', 'GB'));
    }
    expect(resolveReleaseLocale([const Locale('ko', 'KR')], locales),
        const Locale('ko'));
    expect(resolveReleaseLocale([const Locale('en', 'US')], locales),
        const Locale('en', 'US'));
  });
}
