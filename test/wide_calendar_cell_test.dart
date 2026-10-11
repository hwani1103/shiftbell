import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/widgets/wide_calendar_cell.dart';
import 'package:shiftbell/widgets/complete_cell_memo_text.dart';

void main() {
  testWidgets(
      'Korean wide memo font stays constant for one, two and three lines',
      (tester) async {
    for (final theme in kAllCalendarThemeIds) {
      double? size;
      for (final count in [1, 2, 3]) {
        await tester.pumpWidget(MaterialApp(
            locale: const Locale('ko'),
            supportedLocales: const [Locale('ko')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: MediaQuery(
                data: const MediaQueryData(size: Size(933, 704)),
                child: Center(
                    child: SizedBox(
                        width: 131,
                        height: 57,
                        child: WideCalendarCell(
                            theme: theme,
                            day: 9,
                            shift: '야간지원근무',
                            shiftColor: Colors.blue,
                            shiftTextColor: Colors.white,
                            memos: List.filled(count, '병원 진료 예약과 가족 저녁 모임'),
                            isToday: false,
                            isOutside: false,
                            isRed: true,
                            annotation: '한글날',
                            isHoliday: true))))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$theme/$count');
        final labels = tester.widgetList<CompleteCellMemoText>(
            find.byType(CompleteCellMemoText));
        size ??= labels.first.style.fontSize;
        expect(labels, hasLength(count));
        for (final label in labels) {
          expect(label.style.fontSize, size, reason: '$theme/$count');
        }
      }
    }
  });

  testWidgets(
      'Global wide memo font stays constant for one, two and three lines',
      (tester) async {
    for (final theme in kAllCalendarThemeIds) {
      double? size;
      for (final count in [1, 2, 3]) {
        await tester.pumpWidget(MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: MediaQuery(
                data: const MediaQueryData(size: Size(933, 704)),
                child: Center(
                    child: SizedBox(
                        width: 131,
                        height: 57,
                        child: WideCalendarCell(
                            theme: theme,
                            day: 9,
                            shift: '야간지원근무',
                            shiftColor: Colors.blue,
                            shiftTextColor: Colors.white,
                            memos: List.filled(count, '병원 진료 예약과 가족 저녁 모임'),
                            isToday: false,
                            isOutside: false,
                            isRed: true,
                            annotation: null,
                            isHoliday: false))))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$theme/$count');
        final labels = tester.widgetList<CompleteCellMemoText>(
            find.byType(CompleteCellMemoText));
        size ??= labels.first.style.fontSize;
        expect(labels, hasLength(count));
        for (final label in labels) {
          expect(label.style.fontSize, size, reason: '$theme/$count');
        }
      }
    }
  });

  test('Fold inner windows use split cells; covers retain original renderers',
      () {
    expect(WideCalendarCell.appliesTo(const Size(932.57, 704)), isTrue);
    for (final size in [
      const Size(475.43, 751.24),
      const Size(360, 840),
      const Size(393, 852)
    ]) {
      expect(WideCalendarCell.appliesTo(size), isFalse);
    }
    for (final size in [const Size(752, 834.67), const Size(834.67, 752)]) {
      expect(WideCalendarCell.appliesTo(size), isTrue);
      expect(WideCalendarCell.usesWrappedAnnotations(size), isTrue);
    }
  });

  for (final theme in CalendarThemeId.values) {
    testWidgets(
        '${theme.name}: fixed annotations, bounded type, 40:60 placement',
        (tester) async {
      double? fixedHeight;
      double? bandAtMaximum;
      for (final scale in [1.0, 1.08, 1.3, 1.6, 2.0]) {
        for (final count in [1, 2, 3]) {
          await tester.pumpWidget(MaterialApp(
              locale: const Locale('ko'),
              supportedLocales: const [Locale('ko')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                  body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: 130,
                      height: 57,
                      child: WideCalendarCell(
                          theme: theme,
                          day: 29,
                          shift: '야간근무추가',
                          shiftColor: Colors.indigo,
                          shiftTextColor: Colors.white,
                          memos: ['첫번째메모가매우긴경우에도', '둘째', '셋째']
                              .take(count)
                              .toList(),
                          isToday: true,
                          isOutside: false,
                          isRed: true,
                          annotation: '대체공휴일',
                          isHoliday: true)),
                ),
              ))));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '$theme scale=$scale count=$count');
          final annotation = find.byKey(const ValueKey('wide-annotation'));
          final annotationRect = tester.getRect(annotation);
          fixedHeight ??= annotationRect.height;
          expect(annotationRect.height, closeTo(fixedHeight, .01));
          final dateRect = tester.getRect(find.text('29'));
          if (theme == CalendarThemeId.underline) {
            final marker = find.byKey(const ValueKey('wide-date-label'));
            final rect = tester.getRect(marker);
            expect(rect.width, closeTo(rect.height, .01));
            final decoration = tester
                .widget<Container>(marker)
                .foregroundDecoration! as BoxDecoration;
            expect(decoration.shape, BoxShape.circle);
            expect((decoration.border! as Border).isUniform, isTrue);
            expect(dateRect.center.dx, closeTo(rect.center.dx, .01));
            expect(dateRect.center.dy, closeTo(rect.center.dy, .01));
          }
          expect(dateRect.overlaps(annotationRect), isFalse);
          expect(dateRect.right, lessThanOrEqualTo(52));
          final memo = find.byWidgetPredicate(
              (w) => w is CompleteCellMemoText && w.text == '첫번째메모가매우긴경우에도');
          final renderedMemo =
              find.descendant(of: memo, matching: find.byType(Text));
          expect(tester.getRect(memo).left, greaterThanOrEqualTo(52));
          expect(tester.getRect(memo).bottom, lessThanOrEqualTo(57));
          final shift = find.byKey(const ValueKey('shift-badge-text'));
          final band = find.byKey(const ValueKey('wide-shift-band'));
          if (theme == CalendarThemeId.initialBadge) {
            expect(tester.widget<Text>(shift).data, '야');
            final circle = find.byKey(const ValueKey('wide-initial-circle'));
            expect(tester.getSize(circle).width, tester.getSize(circle).height);
            expect(tester.getRect(circle).top, greaterThanOrEqualTo(3));
          }
          if (theme == CalendarThemeId.editorial) {
            final corner = tester
                .getRect(find.byKey(const ValueKey('wide-editorial-corner')));
            final bandRect = tester.getRect(band);
            expect(corner.topLeft, bandRect.topLeft);
            expect(corner.bottom, bandRect.bottom);
            expect(corner.width, corner.height);
          }
          if (theme == CalendarThemeId.diary) {
            expect(tester.widget<Text>(renderedMemo).data,
                isNot(startsWith('· ')));
            final decoration =
                tester.widget<Container>(band).decoration! as BoxDecoration;
            expect(decoration.borderRadius,
                const BorderRadius.only(topRight: Radius.circular(6)));
            final header =
                tester.getRect(find.byKey(const ValueKey('wide-diary-header')));
            expect(dateRect.center.dy, closeTo(header.center.dy, .01));
            expect(tester.getRect(band).left,
                closeTo(header.left + header.width * .4, .01));
            expect(annotationRect.center.dy,
                closeTo((header.bottom + 56) / 2, .01));
          }
          if (theme == CalendarThemeId.eventChip) {
            final decoration =
                tester.widget<Container>(band).decoration! as BoxDecoration;
            expect(decoration.borderRadius, BorderRadius.circular(4));
          }
          expect(tester.getRect(shift).center.dy,
              closeTo(tester.getRect(band).center.dy, .01));
          expect(tester.widget<Text>(renderedMemo).style!.fontSize!,
              lessThanOrEqualTo(tester.widget<Text>(shift).style!.fontSize!));
          if (scale == 1.3) bandAtMaximum = tester.getSize(band).height;
          if (scale > 1.3) {
            expect(tester.getSize(band).height, closeTo(bandAtMaximum!, .01));
          }
        }
      }
    });
  }
}
