import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/theme/calendar_layout_contract.dart';
import 'package:shiftbell/theme/calendar_reading_palette.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/utils/calendar_cell_annotations.dart';
import 'package:shiftbell/widgets/calendar_overtime_label.dart';
import 'package:shiftbell/widgets/contract_calendar_cell.dart';
import 'package:shiftbell/widgets/detail_calendar_cell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('OtTest')
          ..addFont(Future.value(ByteData.sublistView(
              File('C:/Windows/Fonts/malgun.ttf').readAsBytesSync()))))
        .load();
  });
  test(
      'weekday lunar priority, holiday/OT blocking, month boundary, no weekend',
      () {
    final week = DateTime(2026, 10, 1);
    final blocked = <DateTime>{};
    for (final expected in [
      DateTime(2026, 9, 30),
      DateTime(2026, 9, 29),
      DateTime(2026, 10, 1),
      DateTime(2026, 9, 28),
      DateTime(2026, 10, 2)
    ]) {
      expect(
          calendarLunarLabelDate(week,
              hasHoliday: blocked.contains, hasOvertime: (_) => false),
          expected);
      expect(
          calendarLunarLabelDate(week,
              hasHoliday: (_) => false, hasOvertime: blocked.contains),
          expected);
      blocked.add(expected);
    }
    expect(
        calendarLunarLabelDate(week,
            hasHoliday: blocked.contains, hasOvertime: (_) => false),
        isNull);
    expect(
        calendarOvertimeLabels(90), ['+ 1h 30m', '+1h 30m', '+1h30m', '1h30m']);
    expect(calendarOvertimeLabels(30).first, '+ 30m');
    expect(calendarOvertimeLabels(480).first, '+ 8h');
  });
  testWidgets('event OT removes only as many spaces as needed', (t) async {
    const style = TextStyle(fontFamily: 'OtTest', fontSize: 8, height: 1.12);
    double width(String text) {
      final p = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling)
        ..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    final labels = calendarOvertimeLabels(90);
    for (var i = 0; i < labels.length; i++) {
      await t.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
                  width: width(labels[i]) + 1.01,
                  height: 14,
                  child: const CalendarOvertimeLabel(
                      minutes: 90, style: style, compactSpaces: true)))));
      expect(find.text(labels[i]), findsOneWidget);
    }
  });
  final themes = [
    CalendarThemeId.mainWhite,
    CalendarThemeId.minimal,
    CalendarThemeId.materialCard,
    ...CalendarDetailProfile.values.map((p) => p.theme)
  ];
  for (final theme in themes) {
    testWidgets(
        '${theme.name}: OT with 0/2/3 memos, holidays, sizes, live transitions',
        (t) async {
      for (final size in [
        const Size(411.43 / 7, 104),
        const Size(320 / 7, 64)
      ]) {
        for (final palette in [AppUiTimeTheme.daytime, AppUiTimeTheme.night]) {
          for (final holiday in [null, '대체공휴일']) {
            for (final count in [0, 2, 3, 2]) {
              final key = GlobalKey();
              final reading = CalendarReadingPalette(palette.palette,
                  dark: false, design: theme);
              final p = CalendarLayoutProfile.forTheme(theme);
              final memos = ['첫메모', '가운데메모', '마지막메모'].take(count).toList();
              final cell = p != null
                  ? ContractCalendarCell(
                      profile: p,
                      palette: reading,
                      day: 16,
                      shift: '주간근무',
                      shiftColor: Colors.blue,
                      shiftTextColor: Colors.white,
                      memos: memos,
                      holiday: holiday,
                      overtimeMinutes: 90,
                      isToday: true,
                      isOutside: false,
                      isRed: holiday != null,
                      flushTop: false)
                  : DetailCalendarCell(
                      profile: CalendarDetailProfile.forTheme(theme)!,
                      palette: reading,
                      day: 16,
                      shift: '주간근무',
                      shiftColor: Colors.blue,
                      shiftTextColor: Colors.white,
                      memos: memos,
                      holiday: holiday,
                      overtimeMinutes: 90,
                      phoneDecorations: true,
                      today: true,
                      outside: false,
                      red: holiday != null,
                      selected: false);
              await t.pumpWidget(MaterialApp(
                  theme: ThemeData(fontFamily: 'OtTest'),
                  home: Scaffold(
                      body: Center(
                          child: RepaintBoundary(
                              key: key,
                              child: SizedBox.fromSize(
                                  size: size, child: cell))))));
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
              final otFinder = find.byType(CalendarOvertimeLabel);
              expect(otFinder, findsOneWidget);
              final content = [
                find.text('16'),
                if (holiday != null) find.text(holiday),
                find.descendant(of: otFinder, matching: find.byType(Text)),
                for (final memo in memos) find.text(memo)
              ];
              final bounds = t.getRect(find.byWidget(cell));
              final rects = <Rect>[];
              for (final finder in content) {
                expect(finder, findsOneWidget);
                final render = t.renderObject<RenderParagraph>(finder);
                expect(render.text.toPlainText(), isNotEmpty);
                expect(render.didExceedMaxLines, isFalse);
                final rect = MatrixUtils.transformRect(
                    render.getTransformTo(null), Offset.zero & render.size);
                expect(rect.left, greaterThanOrEqualTo(bounds.left - .1));
                expect(rect.right, lessThanOrEqualTo(bounds.right + .1));
                expect(rect.top, greaterThanOrEqualTo(bounds.top - .1));
                expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + .1));
                for (final previous in rects) {
                  final overlap = previous.intersect(rect);
                  expect(overlap.width > .1 && overlap.height > .1, isFalse,
                      reason:
                          '$theme $size holiday=$holiday memos=$count: $previous / $rect');
                }
                rects.add(rect);
              }
              if (holiday != null && count == 3 && p != null) {
                final dateSize =
                    t.widget<Text>(find.text('16')).style!.fontSize!;
                final memoSize =
                    t.widget<Text>(find.text(memos.first)).style!.fontSize!;
                final holidaySize =
                    t.widget<Text>(find.text(holiday)).style!.fontSize!;
                expect(dateSize, greaterThan(memoSize));
                expect(memoSize, greaterThan(holidaySize));
                expect(t.widget<CalendarOvertimeLabel>(otFinder).style.fontSize,
                    holidaySize);
              }
              if (theme == CalendarThemeId.diary)
                expect(find.byKey(const ValueKey('diary-today-outline')),
                    findsOneWidget);
              if (theme == CalendarThemeId.editorial)
                expect(find.byKey(const ValueKey('editorial-phone-corner')),
                    findsOneWidget);
              if (size.width > 58 && holiday != null && count == 3) {
                await t.runAsync(() async {
                  final image = await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 4);
                  final png =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  final file = File(
                      'artifacts/calendar_ot_2026_10_16/renders/${theme.name}_${palette.name}.png');
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(png!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
          }
        }
      }
    });
  }
}
