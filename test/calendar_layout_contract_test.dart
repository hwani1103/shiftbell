import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/calendar_layout_contract.dart';
import 'package:shiftbell/theme/calendar_reading_palette.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/contract_calendar_cell.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.isWindows) {
      final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
      await (FontLoader('ReferenceFont')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  const style =
      TextStyle(fontFamily: 'ReferenceFont', fontSize: 14, height: 1.43);
  for (final profile in [
    CalendarLayoutProfile.main,
    CalendarLayoutProfile.simple,
    CalendarLayoutProfile.soft
  ]) {
    CalendarCellGeometry solve(Size size, int count, {bool today = false}) =>
        CalendarCellGeometry.resolve(
            profile: profile,
            size: size,
            inherited: style,
            direction: TextDirection.ltr,
            locale: const Locale('ko'),
            memoCount: count,
            flushTop: false,
            today: today);
    test('${profile.theme.name} preserves cell ratios over proportional sizes',
        () {
      final a = solve(const Size(360 / 7, 95), 3);
      final b = solve(const Size(480 / 7, 95 * 4 / 3), 3);
      expect(a.density, 1);
      expect(b.density, 1);
      expect(b.chip.height / a.chip.height, closeTo(4 / 3, .001));
      expect(b.chip.left / a.chip.left, closeTo(4 / 3, .001));
      expect(b.info.fontSize / a.info.fontSize, closeTo(4 / 3, .02));
      expect(b.info.lineHeight / a.info.lineHeight, closeTo(4 / 3, .15));
    });
    test(
        '${profile.theme.name} reserves three rows without count-dependent shrinking',
        () {
      for (final size in [
        const Size(320 / 7, 64),
        const Size(411 / 7, 94),
        const Size(760 / 7, 72),
        const Size(600 / 7, 180)
      ]) {
        final empty = solve(size, 0);
        for (final count in [1, 2, 3]) {
          final g = solve(size, count);
          expect(g.unit, empty.unit);
          expect(solve(size, count, today: true).unit, empty.unit);
          expect(g.info.fontSize, empty.info.fontSize);
          expect(g.chip, empty.chip);
          expect(g.memoRows.length, count);
          expect(g.chip.top, greaterThanOrEqualTo(-.01));
          if (!profile.isMain)
            expect(g.annotation.top, greaterThanOrEqualTo(g.date.bottom - .01));
          for (final r in g.memoRows) {
            expect(r.top, greaterThanOrEqualTo(g.annotation.bottom - .01));
            expect(r.bottom, lessThanOrEqualTo(size.height + .02));
          }
          if (g.memoRows.isNotEmpty) {
            expect(
                g.date.bottom, lessThanOrEqualTo(g.memoRows.first.top + .02));
          }
        }
      }
    });
    testWidgets(
        '${profile.theme.name} shares actual information font and fits long names',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 58,
                      height: 105,
                      child: DefaultTextStyle(
                          style: style,
                          child: ContractCalendarCell(
                              profile: profile,
                              palette: CalendarReadingPalette(
                                  AppUiTimeTheme.daytime.palette,
                                  dark: false),
                              day: 15,
                              shift: '매우긴근무이름 EarlyEarly',
                              shiftColor: Colors.blue,
                              shiftTextColor: Colors.white,
                              memos: const ['첫메모여섯글자', '둘째메모', '셋째메모'],
                              holiday: '부처님오신날',
                              isToday: true,
                              isOutside: false,
                              isRed: true,
                              flushTop: false)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data?.contains('메모') ?? false)
          .toList();
      expect(labels.length, 3);
      final holiday = tester.widget<Text>(find.text('부처님오신날'));
      for (final label in labels) {
        expect(label.style!.fontSize, holiday.style!.fontSize);
        expect(label.style!.height, holiday.style!.height);
      }
      final name = find.descendant(
          of: find.byType(ShiftChipLabel), matching: find.byType(Text));
      final chip = find.byKey(const ValueKey('contract-shift-background'));
      expect(tester.getRect(chip).contains(tester.getCenter(name)), isTrue);
      expect(tester.getSize(name).width,
          lessThanOrEqualTo(tester.getSize(chip).width * .9 + .02));
    });
  }
}
