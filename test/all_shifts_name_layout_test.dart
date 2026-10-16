import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/all_shifts_view.dart';
import 'package:shiftbell/widgets/app_shift_chip.dart';

void main() {
  for (final names in [
    ['주간', '야간'],
    ['주간근무', '야간', '특별연장근무'],
    ['Day', 'Night Duty', 'WWWWWWWWWW'],
    ['Afternoon Shift', 'Sleepover Shift', 'WWWWWWWWWWWWWWWW']
  ]) {
    for (final size in [
      const Size(320, 568),
      const Size(360, 780),
      const Size(411.43, 891.43),
      const Size(806, 895),
      const Size(1280, 800)
    ]) {
      testWidgets('whole aligned cells $names $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const capture = bool.fromEnvironment('SHIFT_CAPTURE');
        if (capture) {
          await tester.runAsync(() async {
            final loader = FontLoader('ShiftPreview')
              ..addFont(File('C:/Windows/Fonts/malgun.ttf')
                  .readAsBytes()
                  .then((b) => ByteData.sublistView(b)));
            await loader.load();
          });
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(360, 780),
            builder: (context, _) {
              ScreenUtil.configure(
                  data: appContentMediaQuery(
                      MediaQueryData.fromView(View.of(context))),
                  designSize: const Size(360, 780));
              return MaterialApp(
                locale: const Locale('ko'),
                theme: ThemeData(fontFamily: capture ? 'ShiftPreview' : null),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ],
                home: Scaffold(
                    body: RepaintBoundary(
                        key: boundary,
                        child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            child: MonthShiftTable(
                                year: 2026,
                                month: 10,
                                lastDay: 31,
                                teams: const ['A', 'B', 'C', 'D'],
                                myTeam: 'C',
                                teamOffsets: const {
                                  'A': 0,
                                  'B': 1,
                                  'C': 2,
                                  'D': 3
                                },
                                baseDate: DateTime(2026, 10, 1),
                                pattern: names,
                                shiftColorMap: {
                                  for (final name in names)
                                    name: Colors.blue.shade100
                                },
                                isViewingCurrentRealMonth: false,
                                onPrevMonth: () {},
                                onNextMonth: () {})))),
              );
            }));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in find.text('C').evaluate()) {
          Container? cell;
          label.visitAncestorElements((element) {
            if (element.widget is Container &&
                (element.widget as Container).decoration is BoxDecoration) {
              cell = element.widget as Container;
              return false;
            }
            return true;
          });
          expect((cell!.decoration as BoxDecoration).color,
              Theme.of(label).colorScheme.primary);
        }
        final chips = find.byType(AppShiftChip);
        final first = tester.getRect(chips.first);
        final band = tester
            .getRect(find.byKey(const ValueKey('roster-timeline-block-1')));
        expect(band.left, closeTo(8.w, .001));
        expect(band.right, closeTo(size.width - 8.w, .001));
        final days = tester
            .getRect(find.byKey(const ValueKey('roster-timeline-days-1')));
        final second = tester.getRect(chips.at(1));
        final columnWidth = second.left - first.left;
        final visibleCount = days.width / columnWidth;
        if (size.width < 600) {
          expect(visibleCount, closeTo(visibleCount.roundToDouble(), .001));
          for (var block = 0; block < 2; block++) {
            final viewport = tester.getRect(find.byKey(
                ValueKey('roster-timeline-days-${block == 0 ? 1 : 16}')));
            final rightTeam = tester.getRect(find
                .ancestor(
                    of: find.text('A').at(block * 2 + 1),
                    matching: find.byType(SizedBox))
                .first);
            expect(viewport.right, closeTo(rightTeam.left, .001),
                reason: 'No unused strip before the right team column');
            expect(viewport.width / columnWidth,
                closeTo((viewport.width / columnWidth).roundToDouble(), .001));
          }
          expect(first.left - days.left,
              closeTo((second.left - first.right) / 2, .001));
        }
        final scroll = tester.widget<SingleChildScrollView>(
            find.byKey(const ValueKey('roster-timeline-days-1')));
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        if (size.width < 600) {
          expect(
              scroll.controller!.offset / columnWidth,
              closeTo((scroll.controller!.offset / columnWidth).roundToDouble(),
                  .001));
        }
        scroll.controller!.jumpTo(0);
        await tester.pumpAndSettle();
        for (var i = 0; i < 15; i++) {
          final rect = tester.getRect(chips.at(i));
          expect(rect.width, closeTo(first.width, 0.001));
          expect(rect.height, closeTo(first.height, 0.001));
          expect(rect.top, first.top);
        }
        if (names.first == '주간근무') expect(find.text('주간근무'), findsWidgets);
        if (names.first == 'Afternoon Shift') {
          expect(find.text('Afternoon Shift'), findsWidgets);
          expect(find.text('WWWWWWWWWWWWWWWW'), findsWidgets);
        }
        for (final team in ['A', 'B', 'C', 'D']) {
          final label = tester.getRect(find.text(team).first);
          // The first block uses 15 columns on phones, 16 on wide windows.
          final index = ['A', 'B', 'C', 'D'].indexOf(team) * 15;
          final cell = tester.getRect(chips.at(index));
          expect(label.center.dy, closeTo(cell.center.dy, 0.1));
        }
        if (capture && size.width == 806) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('.tmp/shift-grid-${names.first}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
