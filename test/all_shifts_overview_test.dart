import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/providers/all_shifts_layout_provider.dart';
import 'package:shiftbell/screens/all_shifts_view.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/all_shifts_overview.dart';
import 'package:shiftbell/widgets/app_shift_chip.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';

const evidence = 'artifacts/roster_swipe_2026_10_16/renders';
const names = ['주간', '야간근무', '특별연장근무', '휴무'];
const colors = [
  Color(0xFFA8D4EE),
  Color(0xFF3A5089),
  Color(0xFFFFCC80),
  Color(0xFFD7ECC9)
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Directory(evidence).create(recursive: true);
    for (final (family, path) in [
      ('RosterTest', 'C:/Windows/Fonts/malgun.ttf'),
      (
        'MaterialIcons',
        'C:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
      ),
    ]) {
      await (FontLoader(family)
            ..addFont(Future.value(
                ByteData.sublistView(File(path).readAsBytesSync()))))
          .load();
    }
  });

  test(
      'Layout choice survives a new provider container and latest rapid tap wins',
      () async {
    SharedPreferences.setMockInitialValues({});
    var c = ProviderContainer();
    expect(
        await c.read(allShiftsLayoutProvider.future), AllShiftsLayout.overview);
    final controller = c.read(allShiftsLayoutProvider.notifier);
    await Future.wait([
      controller.select(AllShiftsLayout.overview),
      controller.select(AllShiftsLayout.timeline)
    ]);
    c.dispose();
    c = ProviderContainer();
    expect(
        await c.read(allShiftsLayoutProvider.future), AllShiftsLayout.timeline);
    c.dispose();
  });

  for (final theme in AppUiTimeTheme.values) {
    test('Readable non-shift roles for ${theme.name}', () {
      final p = theme.palette;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
      }

      for (final pair in [
        (p.text, p.background),
        (p.text, p.soft),
        (p.secondaryText, p.soft),
        (p.primary, p.background),
        (p.onPrimary, p.primary)
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });
    for (final layout in AllShiftsLayout.values) {
      testWidgets(
          '${theme.name} ${layout.name} preserves names/colors and fits 360px',
          (t) async {
        t.view.physicalSize = const Size(360, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await t.pumpWidget(ScreenUtilInit(
            designSize: const Size(360, 780),
            builder: (_, __) => MaterialApp(
                  theme: AppUiTheme.withPalette(
                      ThemeData(fontFamily: 'RosterTest'), theme.palette),
                  locale: const Locale('ko'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: RepaintBoundary(
                      key: key,
                      child: Scaffold(
                        appBar: AppBar(
                            title: const Text('전체 조 근무표',
                                style: TextStyle(fontFamily: 'RosterTest'))),
                        body: MonthShiftTable(
                            layout: layout,
                            year: 2026,
                            month: 10,
                            lastDay: 31,
                            teams: const ['A', 'B', 'C', 'D'],
                            myTeam: 'C',
                            teamOffsets: const {'A': 0, 'B': 1, 'C': 2, 'D': 3},
                            baseDate: DateTime(2026, 10, 1),
                            pattern: names,
                            shiftColorMap: Map.fromIterables(names, colors),
                            isViewingCurrentRealMonth: true,
                            onPrevMonth: () {},
                            onNextMonth: () {}),
                      )),
                )));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (layout == AllShiftsLayout.timeline) {
          final date = find.text('1').first;
          final header =
              find.ancestor(of: date, matching: find.byType(Container)).first;
          expect(
              (t.widget<Container>(header).decoration as BoxDecoration).color,
              theme.palette.soft);
        }
        for (final element in find.byType(AllShiftsShiftChip).evaluate()) {
          final chip = element.widget as AllShiftsShiftChip;
          expect(chip.color, colors[names.indexOf(chip.label)]);
        }
        if (layout == AllShiftsLayout.overview) {
          expect(
              find.byKey(const ValueKey('roster-shift-A-31')), findsOneWidget);
          final a = t.getRect(find.byKey(const ValueKey('roster-shift-A-1')));
          final b = t.getRect(find.byKey(const ValueKey('roster-shift-A-11')));
          final c = t.getRect(find.byKey(const ValueKey('roster-shift-A-21')));
          expect(a.width, b.width);
          expect(c.width, closeTo(a.width * 10 / 11, .001));
          expect(c.height, lessThan(a.height));
          expect(
              t.getRect(find.byKey(const ValueKey('roster-team-1-A'))).left, 0);
          expect(
              t.getRect(find.byKey(const ValueKey('roster-shift-A-10'))).right,
              closeTo(360 - AllShiftsMetrics.trailingInset, .001));
          expect(
              t.getRect(find.byKey(const ValueKey('roster-shift-A-31'))).right,
              closeTo(360 - AllShiftsMetrics.trailingInset, .001));
        }
        for (final element in find.byType(ShiftChipLabel).evaluate()) {
          final label = element.widget as ShiftChipLabel;
          final box = element.renderObject as RenderBox;
          final text = find.descendant(
              of: find.byWidget(label), matching: find.byType(Text));
          final rect = t.getRect(text);
          if (layout == AllShiftsLayout.overview) {
            const proportions = AllShiftsMetrics.overviewLabel;
            expect(label.proportions, proportions);
            expect(
                rect.width,
                lessThanOrEqualTo(box.size.width *
                        (1 - 2 * proportions.horizontalInsetFraction) +
                    .1));
            expect(
                rect.height,
                lessThanOrEqualTo(
                    box.size.height * proportions.heightFraction + .1));
          } else {
            expect(label.proportions, isNull);
            expect(rect.width, lessThanOrEqualTo(box.size.width + .1));
            expect(rect.height, lessThanOrEqualTo(box.size.height + .1));
          }
        }
        if (layout == AllShiftsLayout.timeline) {
          expect(find.byType(AppShiftChip), findsNWidgets(31 * 4));
          for (final chip
              in t.widgetList<AppShiftChip>(find.byType(AppShiftChip))) {
            expect(chip.cellColor, colors[names.indexOf(chip.label)]);
            expect(chip.dense, isTrue);
            final body = t.widget<Container>(find
                .descendant(
                    of: find.byWidget(chip), matching: find.byType(Container))
                .first);
            final decoration = body.decoration! as BoxDecoration;
            expect(decoration.borderRadius, BorderRadius.circular(10.r));
            expect((decoration.border! as Border).top.width, 1.6);
          }
        }
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/${theme.name}-${layout.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  for (final month in [
    DateTime(2026, 2),
    DateTime(2028, 2),
    DateTime(2026, 4)
  ]) {
    for (final width in [320.0, 800.0]) {
      testWidgets('$month at $width has exactly real days and no overflow',
          (t) async {
        t.view.physicalSize = Size(width, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final last = DateTime(month.year, month.month + 1, 0).day;
        await t.pumpWidget(MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: AllShiftsOverview(
                  year: month.year,
                  month: month.month,
                  lastDay: last,
                  teams: const ['A', 'B', 'C', 'D', 'E', 'F'],
                  myTeam: 'F',
                  shiftFor: (_, date) => date.day.isEven ? '주간' : '아주긴근무명테스트',
                  shiftColors: const {
                    '주간': Colors.blue,
                    '아주긴근무명테스트': Colors.orange
                  })),
        ));
        await t.pumpAndSettle();
        expect(find.byType(AllShiftsShiftChip), findsNWidgets(last * 6));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
