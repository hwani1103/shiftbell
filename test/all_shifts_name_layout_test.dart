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
import 'package:shiftbell/widgets/team_label.dart';

void main() {
  for (final names in [
    ['주간', '야간'],
    ['주간근무', '야간', '특별연장근무'],
    ['Day', 'Night Duty', 'WWWWWWWWWW'],
    ['Afternoon Shift', 'Sleepover Shift', 'WWWWWWWWWWWWWWWW']
  ]) {
    for (final size in [
      const Size(320, 568),
      const Size(806, 895),
      const Size(1280, 800)
    ]) {
      testWidgets('whole aligned cells $names $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = const bool.fromEnvironment('SHIFT_CAPTURE');
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
                        child: MonthShiftTable(
                            year: 2026,
                            month: 10,
                            lastDay: 31,
                      teams: const ['A', 'B', 'C', 'D'],
                      myTeam: 'C',
                            teamOffsets: const {'A': 0, 'B': 1, 'C': 2, 'D': 3},
                            baseDate: DateTime(2026, 10, 1),
                            pattern: names,
                            shiftColorMap: {
                              for (final name in names)
                                name: Colors.blue.shade100
                            },
                            isViewingCurrentRealMonth: false,
                            onPrevMonth: () {},
                            onNextMonth: () {}))),
              );
            }));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in find.text('C').evaluate()) {
          Container? cell;
          label.visitAncestorElements((element) {
            if (element.widget is Container && (element.widget as Container).decoration is BoxDecoration) {
              cell = element.widget as Container;
              return false;
            }
            return true;
          });
          expect((cell!.decoration as BoxDecoration).color, kMyTeamBackground);
        }
        final chips = find.byType(AppShiftChip);
        final first = tester.getRect(chips.first);
        for (var i = 0; i < 15; i++) {
          final rect = tester.getRect(chips.at(i));
          expect(rect.width, closeTo(first.width, 0.001));
          expect(rect.height, closeTo(first.height, 0.001));
          expect(rect.top, first.top);
        }
        if (names.first == '주간근무') expect(find.text('주간\n근무'), findsWidgets);
        if (names.first == 'Afternoon Shift') {
          expect(find.text('Afternoon\nShift'), findsWidgets);
          expect(find.text('WWWWWWWW\nWWWWWWWW'), findsWidgets);
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
