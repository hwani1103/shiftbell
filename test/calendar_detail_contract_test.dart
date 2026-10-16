import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/detail_calendar_cell.dart';
import 'package:shiftbell/widgets/complete_cell_memo_text.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/theme/calendar_reading_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final p in CalendarDetailProfile.values) {
    test(p.theme.name + ' fits all information rows at real cell sizes', () {
      for (final size in [
        const Size(320 / 7, 64),
        const Size(411 / 7, 104),
        const Size(480 / 7, 125),
        const Size(760 / 7, 72)
      ]) {
        final g = CalendarDetailGeometry.resolve(
            profile: p,
            size: size,
            inherited: const TextStyle(fontSize: 14, height: 1.43),
            direction: TextDirection.ltr,
            locale: const Locale('ko'));
        for (final rect in [g.date, g.chip, g.annotation, ...g.memos]) {
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width + .01));
          expect(rect.bottom, lessThanOrEqualTo(size.height + .01));
        }
        expect(g.memos.first.top, greaterThanOrEqualTo(g.annotation.bottom));
        for (var i = 1; i < 3; i++)
          expect(g.memos[i].top, greaterThanOrEqualTo(g.memos[i - 1].bottom));
      }
    });
    testWidgets(
        p.theme.name + ' shares final information metrics and palette contrast',
        (tester) async {
      for (final theme in AppUiTimeTheme.values) {
        final palette =
            CalendarReadingPalette(theme.palette, dark: false, design: p.theme);
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 58,
                        height: 105,
                        child: DetailCalendarCell(
                            profile: p,
                            palette: palette,
                            day: 16,
                            shift: '매우긴근무이름',
                            shiftColor: Colors.black,
                            shiftTextColor: Colors.white,
                            memos: const ['메모내용여섯글자', 'Meeting', '마지막메모'],
                            holiday: '부처님오신날',
                            today: true,
                            outside: false,
                            red: true,
                            selected: true))))));
        final info = tester
            .widgetList<CompleteCellMemoText>(find.byType(CompleteCellMemoText))
            .toList();
        expect(info.length, p.grid ? 3 : 4);
        if (p.grid) {
          expect(find.text('부처님오신날'), findsOneWidget);
        }
        expect(info.map((w) => w.style.fontSize).toSet(), hasLength(1));
        expect(info.map((w) => w.style.height).toSet(), hasLength(1));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 58,
                  height: 70,
                  child: DetailCalendarCell(
                      profile: p,
                      palette: CalendarReadingPalette(
                          AppUiTimeTheme.night.palette,
                          dark: false),
                      day: 27,
                      shift: '',
                      shiftColor: Colors.transparent,
                      shiftTextColor: Colors.white,
                      memos: const [],
                      today: false,
                      outside: true,
                      red: false,
                      selected: false)))));
      expect(find.text('27'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test('dark grid bands and mosaic surfaces keep identity in every palette',
      () {
    for (final theme in AppUiTimeTheme.values) {
      final p = CalendarReadingPalette(theme.palette, dark: false);
      expect(p.darkBand.computeLuminance(), lessThan(.15));
      expect(CalendarContrast.ratio(p.onDarkBand, p.darkBand),
          greaterThanOrEqualTo(4.5));
      expect(CalendarContrast.ratio(p.detailMemoText, p.detailMemoSurface),
          greaterThanOrEqualTo(4.5));
      expect(p.detailSurface(false), isNot(p.detailSurface(true)));
      for (final shift in [
        Colors.red,
        Colors.blue,
        Colors.white,
        Colors.black,
        const Color(0xffe8edfc)
      ]) {
        final fill = p.mosaicSurface(shift),
            outside = p.mosaicSurface(shift, outside: true);
        if (shift != p.surface) expect(fill, isNot(outside));
        final chip = p.mosaicChip(shift);
        expect(CalendarContrast.ratio(CalendarContrast.ink(chip), chip),
            greaterThanOrEqualTo(4.5));
        expect(CalendarContrast.ratio(CalendarReadingPalette.redOn(fill), fill),
            greaterThanOrEqualTo(4.5));
      }
    }
  });
  testWidgets(
      'grid holiday uses all space after the date and keeps common shift ink',
      (t) async {
    await (FontLoader('GridTest')
          ..addFont(Future.value(ByteData.sublistView(
              File('C:/Windows/Fonts/malgun.ttf').readAsBytesSync()))))
        .load();
    final profile = CalendarDetailProfile.values.singleWhere((p) => p.grid);
    for (final width in [320 / 7, 411 / 7]) {
      for (final day in [5, 10]) {
        for (final palette in [AppUiTimeTheme.daytime, AppUiTimeTheme.night]) {
          final key = GlobalKey();
          await t.pumpWidget(MaterialApp(
              theme: ThemeData(fontFamily: 'GridTest'),
              home: Scaffold(
                  body: Center(
                      child: RepaintBoundary(
                          key: key,
                          child: SizedBox(
                              width: width,
                              height: 105,
                              child: DetailCalendarCell(
                                  profile: profile,
                                  palette: CalendarReadingPalette(
                                      palette.palette,
                                      dark: false),
                                  day: day,
                                  shift: '휴무',
                                  shiftColor: const Color(0xFFF45151),
                                  shiftTextColor: Colors.white,
                                  memos: const ['첫 메모', '가운데 메모', '마지막 메모'],
                                  holiday: '대체공휴일',
                                  today: false,
                                  outside: false,
                                  red: true,
                                  selected: false)))))));
          await t.pumpAndSettle();
          expect(find.text('대체공휴일'), findsOneWidget);
          expect(find.text('대체공'), findsNothing);
          final label = t.renderObject<RenderParagraph>(find.text('대체공휴일'));
          final rect = MatrixUtils.transformRect(
              label.getTransformTo(null), Offset.zero & label.size);
          final date = t.getRect(find.text('$day'));
          final cell = t.getRect(find.byType(DetailCalendarCell));
          expect(rect.left, greaterThanOrEqualTo(date.right));
          expect(rect.right, lessThanOrEqualTo(cell.right));
          expect(cell.right - rect.right, lessThan(2));
          expect(t.widget<ShiftChipLabel>(find.byType(ShiftChipLabel)).color,
              Colors.white);
          expect(find.byType(CompleteCellMemoText), findsNWidgets(3));
          expect(t.takeException(), isNull);
          if (width > 58 && day == 10)
            await t.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 4);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory('artifacts/dark_grid_detail_2026_10_16')
                  .create(recursive: true);
              await File('artifacts/dark_grid_detail_2026_10_16/' +
                      palette.name +
                      '.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
        }
      }
    }
  });
}
