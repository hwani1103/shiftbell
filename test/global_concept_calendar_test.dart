import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/widgets/complete_cell_memo_text.dart';
import 'package:shiftbell/widgets/global_concept_calendar_cell.dart';
import 'package:shiftbell/widgets/wide_calendar_cell.dart';

void main() {
  test('Runs respect week start, month edge, empty shifts and actual names',
      () {
    String shift(DateTime d) => d.day <= 15 ? 'Day' : 'Night';
    expect(calendarShiftRun(DateTime(2026, 10, 13), 1, shift),
        (index: 1, length: 4));
    expect(calendarShiftRun(DateTime(2026, 10, 13), 7, shift),
        (index: 2, length: 5));
    expect(calendarShiftRun(DateTime(2026, 10, 1), 1, shift),
        (index: 0, length: 4));
    expect(calendarShiftRun(DateTime(2026, 10, 1), 1, (_) => 'Day'),
        (index: 3, length: 7));
    expect(
        calendarShiftRun(
            DateTime(2026, 10, 13), 1, (d) => d.weekday >= 6 ? '' : 'Day'),
        (index: 1, length: 5));
    expect(calendarShiftRun(DateTime(2026, 10, 18), 7, (_) => ''),
        (index: 0, length: 1));
    expect(calendarShiftRun(DateTime(2026, 10, 18), 7, (_) => '미설정'),
        (index: 0, length: 1));
    expect(calendarShiftRun(DateTime(2026, 10, 15), 1, shift),
        (index: 3, length: 4));
  });

  for (final theme in [
    CalendarThemeId.periwinkle,
    CalendarThemeId.softMosaic
  ]) {
    testWidgets(
        '${theme.name}: short landscape / cover cells retain three memos',
        (tester) async {
      for (final size in [
        const Size(40, 70),
        const Size(58, 103),
        const Size(105, 80),
        const Size(133, 126)
      ]) {
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: const MediaQueryData(size: Size(411, 891)),
                child: child!),
            home: Scaffold(
                body: Center(
                    child: SizedBox.fromSize(
                        size: size,
                        child: GlobalConceptCalendarCell(
                            theme: theme,
                            date: DateTime(2026, 10, 8),
                            shift: 'Afternoon Shift',
                            shiftColor: Colors.indigo,
                            shiftTextColor: Colors.white,
                            memos: const [
                              'Appointment',
                              'Dentist',
                              'Buy groceries'
                            ],
                            today: true,
                            outside: false,
                            red: false,
                            selected: true,
                            runIndex: 1,
                            runLength: 3))))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$theme $size');
        final lines = tester.widgetList<Text>(find.descendant(
            of: find.byType(CompleteCellMemoText),
            matching: find.byType(Text)));
        expect(lines, hasLength(3));
        for (final line in lines) {
          expect(line.data!.length, greaterThanOrEqualTo(2),
              reason: '$theme $size: ${line.data}');
        }
      }
    });
  }
  for (final theme in [
    CalendarThemeId.periwinkle,
    CalendarThemeId.softMosaic
  ]) {
    testWidgets(
        '${theme.name}: resize switches only wide cells to date-left memos-right',
        (tester) async {
      for (final window in [
        const Size(411, 891),
        const Size(475, 751),
        const Size(704, 933),
        const Size(933, 704),
        const Size(752, 835),
        const Size(411, 891),
      ]) {
        final split = WideCalendarCell.appliesTo(window);
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(size: window),
          child: Center(
              child: SizedBox(
            width: window.width / 7,
            height: split ? 82 : 103,
            child: GlobalConceptCalendarCell(
              theme: theme,
              date: DateTime(2026, 10, 9),
              shift: 'Afternoon Shift',
              shiftColor: Colors.blue,
              shiftTextColor: Colors.white,
              memos: const [
                'Clinic appointment',
                'Dinner with family',
                'Equipment safety training'
              ],
              today: true,
              outside: false,
              red: false,
              selected: false,
            ),
          )),
        )));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$theme $window');
        final date = tester.getRect(find.byKey(const ValueKey('concept-date')));
        final shift =
            tester.getRect(find.byKey(const ValueKey('concept-shift')));
        final memo = tester.getRect(find.byType(CompleteCellMemoText).first);
        expect(find.byType(CompleteCellMemoText), findsNWidgets(3));
        for (final text in tester.widgetList<Text>(find.descendant(
            of: find.byType(CompleteCellMemoText),
            matching: find.byType(Text)))) {
          expect(text.data, isNotEmpty,
              reason: '$theme $window memo must remain visible');
        }
        if (split) {
          expect(date.left, lessThan(memo.left));
          expect(date.top, greaterThanOrEqualTo(shift.bottom));
          expect(memo.top, greaterThanOrEqualTo(shift.bottom));
        } else {
          expect(date.bottom, lessThanOrEqualTo(shift.top));
          expect(memo.top, greaterThanOrEqualTo(shift.bottom));
        }
      }
    });
  }
}
