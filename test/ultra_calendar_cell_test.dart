import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/widgets/wide_calendar_cell.dart';

void main() {
  setUpAll(() async {
    final bytes = await File(Platform.isWindows
            ? 'C:/Windows/Fonts/malgun.ttf'
            : 'test/fixtures/layout_fonts/Jua-Regular.ttf')
        .readAsBytes();
    await (FontLoader('UltraTest')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  for (final theme in CalendarThemeId.values) {
    testWidgets('${theme.name}: Ultra two-line annotations stay beside memos',
        (tester) async {
      for (final size in [const Size(104, 78), const Size(114, 65)]) {
        for (final scale in [1.0, 1.14, 1.3, 1.6]) {
          for (final value in [
            '추석',
            '개천절',
            '국군의날',
            '대체공휴일',
            '임시대체공휴',
            '(8.15)'
          ]) {
            for (final count in [1, 2, 3]) {
              final holiday = !value.startsWith('(');
              await tester.pumpWidget(MaterialApp(
                  theme: ThemeData(fontFamily: 'UltraTest'),
                  home: MediaQuery(
                      data: MediaQueryData(
                          size: const Size(752, 834.67),
                          textScaler: TextScaler.linear(scale)),
                      child: Scaffold(
                          body: Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox.fromSize(
                                  size: size,
                                  child: WideCalendarCell(
                                      theme: theme,
                                      day: 29,
                                      shift: '야간근무',
                                      shiftColor: Colors.blue,
                                      shiftTextColor: Colors.white,
                                      memos: ['첫메모가긴경우', '둘째', '셋째']
                                          .take(count)
                                          .toList(),
                                      isToday: true,
                                      isOutside: false,
                                      isRed: true,
                                      annotation: value,
                                      isHoliday: holiday)))))));
              await tester.pump();
              expect(tester.takeException(), isNull,
                  reason: '$theme $size $scale $value $count');
              final annotation = find.byKey(const ValueKey('wide-annotation'));
              final text = tester.widget<Text>(annotation);
              final rect = tester.getRect(annotation);
              final contentInset = [
                CalendarThemeId.diary,
                CalendarThemeId.materialCard,
                CalendarThemeId.eventChip
              ].contains(theme)
                  ? 2.0
                  : 0.0;
              final split = contentInset + (size.width - contentInset * 2) * .4;
              expect(rect.right, lessThanOrEqualTo(split + .01));
              expect(rect.bottom, lessThanOrEqualTo(size.height));
              expect(text.textScaler!.scale(1), 1);
              expect(text.style!.fontSize, 9.2);
              expect(
                  tester
                      .renderObject<RenderParagraph>(annotation)
                      .didExceedMaxLines,
                  isFalse);
              if (holiday) {
                expect(text.data!.replaceAll('\n', ''), value);
                expect(text.data!.split('\n').length, lessThanOrEqualTo(2));
                for (final line in text.data!.split('\n')) {
                  expect(line.characters.length, lessThanOrEqualTo(3));
                }
              } else {
                expect(text.data, value);
                expect(text.maxLines, 1);
              }
              final date = tester.getRect(find.text('29'));
              expect(rect.overlaps(date), isFalse);
              final memo = find.byWidgetPredicate(
                  (w) => w is Text && (w.data?.contains('첫메모') ?? false));
              expect(tester.getRect(memo).left, greaterThanOrEqualTo(split));
              final memoText = tester.widget<Text>(memo);
              expect(memoText.data, '첫메모가긴경우');
              expect(memoText.textScaler!.scale(1), 1);
              expect(memoText.style!.fontSize,
                  lessThanOrEqualTo(count <= 2 ? 10.5 : 8.4));
              final dateText = tester.widget<Text>(find.text('29'));
              expect(dateText.textScaler!.scale(1), 1);
              expect(dateText.style!.fontSize, 14);
              expect(
                  tester
                      .widget<Text>(
                          find.byKey(const ValueKey('shift-badge-text')))
                      .textScaler!
                      .scale(1),
                  {
                    CalendarThemeId.minimal,
                    CalendarThemeId.materialCard,
                    CalendarThemeId.initialBadge,
                    CalendarThemeId.eventChip,
                  }.contains(theme)
                      ? 1.3
                      : (scale > 1.3 ? 1.3 : scale));
              final band =
                  tester.getRect(find.byKey(const ValueKey('wide-shift-band')));
              final shift = tester
                  .getRect(find.byKey(const ValueKey('shift-badge-text')));
              expect(shift.center.dy, closeTo(band.center.dy, .01));
              if (theme == CalendarThemeId.initialBadge) {
                final circle = tester
                    .getRect(find.byKey(const ValueKey('wide-initial-circle')));
                expect(circle.top, greaterThanOrEqualTo(3));
                expect(circle.width, closeTo(circle.height, .01));
              }
            }
          }
        }
      }
    });
  }
}
