import 'package:shiftbell/widgets/calendar_overtime_label.dart';
import 'package:shiftbell/utils/lunar_calendar_util.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shiftbell/providers/overtime_provider.dart';
import 'package:shiftbell/models/date_overtime.dart';
import 'package:shiftbell/screens/calendar_theme_picker_screen.dart';
import 'package:shiftbell/widgets/detail_calendar_cell.dart';
import 'package:shiftbell/theme/calendar_date_grid.dart';
import 'dart:convert';
import 'package:shiftbell/theme/calendar_reading_palette.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/app_ui_theme_scope.dart';
import 'package:shiftbell/widgets/calendar_app_frame.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';

class _PersistentAdProbe extends StatefulWidget {
  const _PersistentAdProbe();
  @override
  State<_PersistentAdProbe> createState() => _PersistentAdProbeState();
}

class _PersistentAdProbeState extends State<_PersistentAdProbe> {
  static int created = 0;
  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 64);
}

Future<String> _pixels(
    WidgetTester tester, GlobalKey boundaryKey, Rect rectangle, String? name,
    {Rect? extra}) async {
  return (await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    if (name != null &&
        const bool.fromEnvironment('CAPTURE_CALENDAR_APP_FRAME')) {
      final png = await picture.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(const String.fromEnvironment(
          'CALENDAR_FRAME_CAPTURE_DIR',
          defaultValue: 'artifacts/calendar_app_frame/host'));
      await folder.create(recursive: true);
      await File('${folder.path}/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      final textGeometry = <Map<String, Object?>>[];
      for (final element in find.byType(Text).evaluate()) {
        final label = element.widget as Text;
        final render = element.findRenderObject();
        if (render is! RenderBox || !render.hasSize) continue;
        final rect = render.localToGlobal(Offset.zero) & render.size;
        final style = DefaultTextStyle.of(element).style.merge(label.style);
        final chip = element.findAncestorWidgetOfExactType<ShiftChipLabel>();
        textGeometry.add({
          'text': label.data,
          'fontSize': style.fontSize,
          'height': style.height,
          'fontFamily': style.fontFamily,
          'chip': chip != null,
          'rect': [rect.left, rect.top, rect.width, rect.height],
        });
      }
      await File('${folder.path}/$name.json')
          .writeAsString(jsonEncode(textGeometry));
    }
    final rgba =
        (await picture.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final bytes = BytesBuilder(copy: false);
    final width = picture.width;
    final data = rgba.buffer.asUint8List();
    for (final area in [rectangle, if (extra != null) extra]) {
      for (var y = area.top.ceil(); y < area.bottom.floor(); y++) {
        bytes.add(Uint8List.sublistView(
            data,
            (y * width + area.left.ceil()) * 4,
            (y * width + area.right.floor()) * 4));
      }
    }
    picture.dispose();
    return sha256.convert(bytes.takeBytes()).toString();
  }))!;
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
    final now = DateTime.now();
    for (final offset in [-1, 0, 1]) {
      final day = DateTime(now.year, now.month + offset, 15);
      await DatabaseService.instance.adjustOvertime(
          DateFormat('yyyy-MM-dd').format(day), (offset + 2) * 30);
    }
    await DatabaseService.instance.adjustOvertime('2026-10-09', 90);
    await DatabaseService.instance.adjustOvertime('2026-10-14', 90);
    for (final day in ['2026-10-09', '2026-10-13']) {
      for (final memo in ['Meeting', 'Appointment', 'Training']) {
        await DatabaseService.instance.createMemo(day, memo);
      }
    }
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });

  final cases = <(String, CalendarThemeId)>[
    for (final theme in kAllCalendarThemeIds) ('ko', theme),
    for (final theme in kEnglishCalendarThemeIds) ('en', theme),
    ('de', CalendarThemeId.mainWhite),
    ('pt', CalendarThemeId.periwinkle),
    ('hi', CalendarThemeId.softMosaic),
  ];
  const sizeList = String.fromEnvironment('CALENDAR_FRAME_SIZES');
  final viewports = sizeList.isEmpty
      ? [
          Size(
              double.parse(const String.fromEnvironment('CALENDAR_FRAME_WIDTH',
                  defaultValue: '400')),
              double.parse(const String.fromEnvironment('CALENDAR_FRAME_HEIGHT',
                  defaultValue: '850')))
        ]
      : sizeList.split(',').map((value) {
          final parts = value.split('x');
          return Size(double.parse(parts[0]), double.parse(parts[1]));
        }).toList();
  for (final size in viewports) {
    for (final item in cases) {
      testWidgets(
          '${item.$1}/${item.$2.name} keeps date cells across app palettes${sizeList.isEmpty ? '' : ' ${size.width}x${size.height}'}',
          (tester) async {
        final locale = Locale(item.$1);
        final theme = item.$2;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = double.parse(
            const String.fromEnvironment('CALENDAR_FRAME_TEXT_SCALE',
                defaultValue: '1'));
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'welcome_popup_shown': true,
          'calendar_main_merge_v1': true,
          'shift_assign_tutorial_shown': true,
          AppUiThemePreviewController.preferenceKey: 'daytime',
        });
        late ScheduleNotifier schedule;
        await tester.runAsync(() async {
          schedule = ScheduleNotifier();
          await schedule.refresh();
        });
        final container = ProviderContainer(overrides: [
          scheduleProvider.overrideWith((ref) => schedule),
          calendarThemeProvider
              .overrideWith((ref) => CalendarThemeNotifier.withInitial(theme)),
        ]);
        addTearDown(container.dispose);
        final boundary = GlobalKey();
        final allowed =
            calendarUsesAppFrame(theme, includeLegend: item.$1 == 'ko');
        final reading = CalendarThemeRollout.usesReading(theme);
        _PersistentAdProbeState.created = 0;
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: ScreenUtilInit(
                designSize: const Size(360, 780),
                builder: (_, __) => MaterialApp(
                    locale: locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: AppTheme.lightTheme,
                    home: AppUiThemeScope(
                        enabled: allowed,
                        builder: (frameContext) => RepaintBoundary(
                            key: boundary,
                            child: Scaffold(
                                body: Column(children: [
                                  Expanded(
                                      child: CalendarDesignTheme(
                                          theme: theme, child: CalendarTab())),
                                  const _PersistentAdProbe(),
                                ]),
                                bottomNavigationBar:
                                    BottomNavigationBar(items: const [
                                  BottomNavigationBarItem(
                                      icon: Icon(Icons.alarm), label: 'Alarm'),
                                  BottomNavigationBarItem(
                                      icon: Icon(Icons.calendar_month),
                                      label: 'Calendar'),
                                  BottomNavigationBarItem(
                                      icon: Icon(Icons.settings),
                                      label: 'Settings'),
                                ]))))))));
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final calendar =
            tester.widget<TableCalendar>(find.byType(TableCalendar));
        if (calendar.focusedDay.year == 2026 &&
            calendar.focusedDay.month == 10) {
          if (item.$1 == 'ko') {
            for (final day in ['2026-10-09', '2026-10-14']) {
              final cell = find.byKey(ValueKey('calendar-cell-$day')).first;
              expect(
                  find.descendant(
                      of: cell, matching: find.byType(CalendarOvertimeLabel)),
                  findsOneWidget);
            }
            final tuesday =
                find.byKey(const ValueKey('calendar-cell-2026-10-13')).first;
            final lunar =
                formatLunarDateCompact(solarToLunar(DateTime(2026, 10, 13))!);
            expect(find.descendant(of: tuesday, matching: find.text(lunar)),
                findsOneWidget);
          } else {
            expect(find.byType(CalendarOvertimeLabel), findsNothing);
          }
        }
        final tableRect = tester.getRect(find.byType(TableCalendar));
        final dateRect = Rect.fromLTWH(
            tableRect.left,
            tableRect.top,
            tableRect.width,
            calendar.daysOfWeekHeight + calendar.rowHeight * 5);
        final region = allowed ? dateRect : Offset.zero & size;
        final leftColumns = theme == CalendarThemeId.mainWhite ||
                theme == CalendarThemeId.mainDark
            ? 2
            : item.$1 == 'ko'
                ? 4
                : 5;
        final leftSixthRow = allowed
            ? Rect.fromLTWH(tableRect.left, dateRect.bottom,
                tableRect.width * leftColumns / 7, calendar.rowHeight)
            : null;
        final before = await _pixels(tester, boundary, region,
            '${item.$1}_${theme.name}_${size.width.toInt()}x${size.height.toInt()}_daytime',
            extra: leftSixthRow);
        List<Object?> shiftAppearance() => [
              for (final element in find.byType(ShiftChipLabel).evaluate()) ...[
                (element.widget as ShiftChipLabel).label,
                // Legend labels have no solid fill and follow the backdrop ink.
                (theme.hasLegend || theme == CalendarThemeId.softMosaic)
                    ? null
                    : (element.widget as ShiftChipLabel).color,
                tester.getRect(find.byWidget(element.widget)),
              ]
            ];
        final originalShiftAppearance = shiftAppearance();
        for (final palette in AppUiTimeTheme.values
            .where((p) => p != AppUiTimeTheme.daytime)) {
          await container
              .read(appUiThemePreviewProvider.notifier)
              .select(palette);
          await tester.pumpAndSettle();
          expect(shiftAppearance(), originalShiftAppearance,
              reason:
                  'Background selection must preserve shift text color and chip geometry');
          expect(
              await _pixels(tester, boundary, region,
                  '${item.$1}_${theme.name}_${size.width.toInt()}x${size.height.toInt()}_${palette.name}',
                  extra: leftSixthRow),
              reading ? isNot(before) : before,
              reason: reading
                  ? 'Reading cells must follow the palette'
                  : 'Protected calendar pixels must stay unchanged');
          expect(find.byKey(const ValueKey('calendar-app-header')),
              allowed ? findsOneWidget : findsNothing);
          expect(_PersistentAdProbeState.created, 1,
              reason: 'Palette changes must keep the mounted ad slot');
          if (allowed) {
            expect(
                Theme.of(tester.element(find.byType(CalendarTab))).colorScheme,
                AppTheme.forCalendar(theme).colorScheme);
            expect(
                Theme.of(tester.element(find.byType(CalendarTab)))
                    .extension<AppUiPalette>()
                    ?.background,
                palette.palette.background);
            expect(
                Theme.of(tester.element(find.byType(BottomNavigationBar)))
                    .bottomNavigationBarTheme
                    .backgroundColor,
                palette.palette.background);
          }
        }
        // Regress the actual gesture, not only onPageChanged callbacks.
        final beforeMonth =
            tester.widget<TableCalendar>(find.byType(TableCalendar)).focusedDay;
        final tableFinder = find.descendant(
            of: find.byType(TableCalendar), matching: find.byType(Table));
        final firstTable = tableFinder.first;
        final originalTableX = tester.getTopLeft(firstTable).dx;
        if ([
          CalendarThemeId.minimal,
          CalendarThemeId.boldGrid,
          CalendarThemeId.editorial
        ].contains(theme)) {
          expect(tester.widget<Table>(firstTable).border,
              isA<CalendarDateGridBorder>(),
              reason: 'Date strokes must be inside the scrolling month');
        }
        if (item.$1 == 'ko' &&
            theme == CalendarThemeId.minimal &&
            beforeMonth.year == 2026 &&
            beforeMonth.month == 10) {
          await tester.runAsync(() => container
              .read(overtimeProvider.notifier)
              .adjust('2026-10-14', -90));
          await tester.pumpAndSettle();
          final wed =
              find.byKey(const ValueKey('calendar-cell-2026-10-14')).first;
          expect(
              find.descendant(
                  of: wed, matching: find.byType(CalendarOvertimeLabel)),
              findsNothing);
          expect(
              find.descendant(
                  of: wed,
                  matching: find.text(formatLunarDateCompact(
                      solarToLunar(DateTime(2026, 10, 14))!))),
              findsOneWidget);
          await tester.runAsync(() => container
              .read(overtimeProvider.notifier)
              .adjust('2026-10-14', 90));
          await tester.pumpAndSettle();
          expect(
              find.descendant(
                  of: wed, matching: find.byType(CalendarOvertimeLabel)),
              findsOneWidget);
        }
        final calendarBeforeDrag =
            tester.widget<TableCalendar>(find.byType(TableCalendar));
        final gesture = await tester.startGesture(Offset(
            tableRect.right - 30,
            tableRect.top +
                calendar.daysOfWeekHeight +
                calendar.rowHeight * 2));
        await gesture.moveBy(const Offset(-24, 0));
        await tester.pump();
        await gesture.moveBy(Offset(-tableRect.width * .28, 0));
        await tester.pump();
        expect(tester.getTopLeft(firstTable).dx, lessThan(originalTableX - 10));
        if (const bool.fromEnvironment('CAPTURE_CALENDAR_APP_FRAME')) {
          await _pixels(tester, boundary, dateRect,
              item.$1 + '_' + theme.name + '_swipe');
        }
        await gesture.moveBy(Offset(-tableRect.width * .4, 0));
        await tester.pump(const Duration(milliseconds: 16));
        if (allowed) {
          final nextMonth = DateTime(beforeMonth.year, beforeMonth.month + 1);
          final title = item.$1 == 'ko'
              ? DateFormat('y년 M월').format(nextMonth)
              : DateFormat.yMMMM(locale.toString()).format(nextMonth);
          expect(
              find.descendant(
                  of: find.byKey(const ValueKey('calendar-app-header')),
                  matching: find.text(title)),
              findsOneWidget,
              reason:
                  'The month title must change while the finger is still down');
          expect(
              identical(
                  tester.widget<TableCalendar>(find.byType(TableCalendar)),
                  calendarBeforeDrag),
              isTrue,
              reason:
                  'Month feedback must not rebuild the calendar during its gesture');
          final nextOtKey = DateFormat('yyyy-MM-dd')
              .format(DateTime(nextMonth.year, nextMonth.month, 15));
          expect(container.read(overtimeProvider)[nextOtKey], 90,
              reason:
                  'Adjacent-month OT must already be cached before settling');
          final otText = formatOvertimeMinutes(
              tester.element(find.byType(CalendarTab)), 90);
          expect(
              find.byWidgetPredicate(
                  (w) => w is Text && (w.data?.contains(otText) ?? false)),
              findsWidgets,
              reason:
                  'Cached month OT must change with the title before scroll end');
        }
        await gesture.up();
        await tester.pumpAndSettle();
        final afterMonth =
            tester.widget<TableCalendar>(find.byType(TableCalendar)).focusedDay;
        expect(afterMonth.year * 12 + afterMonth.month,
            beforeMonth.year * 12 + beforeMonth.month + 1);
        await tester.dragFrom(
            Offset(
                tableRect.left + 30,
                tableRect.top +
                    calendar.daysOfWeekHeight +
                    calendar.rowHeight * 2),
            Offset(tableRect.width * .75, 0));
        await tester.pumpAndSettle();
        final returnedMonth =
            tester.widget<TableCalendar>(find.byType(TableCalendar)).focusedDay;
        expect(returnedMonth.year * 12 + returnedMonth.month,
            beforeMonth.year * 12 + beforeMonth.month);
        if (allowed) {
          final l =
              AppLocalizations.of(tester.element(find.byType(CalendarTab)));
          tester
              .widget<TableCalendar>(find.byType(TableCalendar))
              .onPageChanged!(DateTime(2026, 8, 1));
          await tester.pumpAndSettle();
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pumpAndSettle();
          await tester.tap(theme.hasLegend
              ? find.byKey(const ValueKey('calendar-header-today'))
              : find.byTooltip(l.commonToday));
          await tester.pumpAndSettle();
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pumpAndSettle();
          expect(
              tester
                  .widget<TableCalendar>(find.byType(TableCalendar))
                  .focusedDay
                  .month,
              DateTime.now().month);
          // Today/picker updates must reset the same immediate month signal.
          final again = await tester.startGesture(Offset(
              tableRect.right - 30,
              tableRect.top +
                  calendar.daysOfWeekHeight +
                  calendar.rowHeight * 2));
          await again.moveBy(const Offset(-24, 0));
          await tester.pump();
          await again.moveBy(Offset(-tableRect.width * .7, 0));
          await tester.pump(const Duration(milliseconds: 16));
          final next = DateTime(DateTime.now().year, DateTime.now().month + 1);
          final title = item.$1 == 'ko'
              ? DateFormat('y년 M월').format(next)
              : DateFormat.yMMMM(locale.toString()).format(next);
          expect(
              find.descendant(
                  of: find.byKey(const ValueKey('calendar-app-header')),
                  matching: find.text(title)),
              findsOneWidget);
          await again.up();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets(
      'picker uses reordered current previews without changing saved selection',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'calendar_main_merge_v1': true,
      'calendar_theme_id': 'boldGrid',
      'app_ui_preview_theme': 'originalDark'
    });
    final container = ProviderContainer(overrides: [
      calendarThemeProvider.overrideWith(
          (ref) => CalendarThemeNotifier.withInitial(CalendarThemeId.boldGrid))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
            designSize: const Size(360, 780),
            builder: (_, __) => const MaterialApp(
                locale: Locale('ko'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: CalendarThemePickerScreen()))));
    await tester.pumpAndSettle();
    final pages = tester.widget<PageView>(find.byType(PageView).first);
    expect(pages.controller!.page,
        kAllCalendarThemeIds.indexOf(CalendarThemeId.boldGrid));
    expect(find.byType(DetailCalendarCell), findsWidgets);
    for (final index in [5, 7, 8, 0]) {
      pages.controller!.jumpToPage(index);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('calendar_theme_id'), 'boldGrid');
    expect(prefs.getString('app_ui_preview_theme'), 'night');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
