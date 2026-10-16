import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/theme/calendar_reading_palette.dart';

void main() {
  test('Soft cards keep month hierarchy and readable ink in every screen color',
      () {
    for (final time in AppUiTimeTheme.values) {
      final p = CalendarReadingPalette(time.palette,
          dark: false, design: CalendarThemeId.materialCard);
      if (p.surface != Colors.white) {
        expect(p.currentMonthCard, isNot(p.surface), reason: time.name);
      }
      if (p.text == Colors.black) {
        expect(p.currentMonthCard.computeLuminance(),
            greaterThanOrEqualTo(p.surface.computeLuminance()),
            reason: time.name);
      }
      expect(p.currentMonthCard, isNot(p.outsideMonthCard), reason: time.name);
      for (final outside in [false, true]) {
        final fill = p.cardSurface(outside);
        expect(fill.a, 1);
        for (final ink in [
          p.text,
          p.cardHoliday(outside),
          p.cardLunar(outside)
        ]) {
          expect(CalendarContrast.ratio(ink, fill), greaterThanOrEqualTo(4.5),
              reason: '${time.name}/outside=$outside');
        }
      }
    }
  });
  testWidgets('Adaptive chip outline preserves the full label layout area',
      (tester) async {
    const labelKey = ValueKey('label-area');
    Future<Size> layout(Border? border) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: Container(
                  width: 100,
                  height: 24,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration:
                      BoxDecoration(color: Colors.white, border: border),
                  child: const SizedBox.expand(key: labelKey)))));
      return tester.getSize(find.byKey(labelKey));
    }

    final original = await layout(null);
    final protected =
        await layout(CalendarContrast.chipOutline(Colors.white, Colors.white));
    expect(protected, original);
  });
  test(
      'Every design uses the actual backdrop and conservative reading contrast',
      () {
    for (final design in CalendarThemeId.values) {
      for (final time in AppUiTimeTheme.values) {
        final p = CalendarReadingPalette(time.palette,
            dark: design.isDark, design: design);
        expect(p.surface, time.palette.background);
        expect([Colors.black, Colors.white], contains(p.text));
        for (final ink in [p.text, p.muted, p.outside, p.holiday]) {
          expect(CalendarContrast.ratio(ink, p.selectedSurface),
              greaterThanOrEqualTo(4.5));
          expect(
              CalendarContrast.ratio(ink, p.surface), greaterThanOrEqualTo(4.5),
              reason: '${design.name}/${time.name}');
        }
        expect(CalendarContrast.ratio(p.memoText, p.memoSurface),
            greaterThanOrEqualTo(4.5));
        expect(CalendarContrast.ratio(p.onToday, p.today),
            greaterThanOrEqualTo(4.5));
        expect(CalendarContrast.ratio(p.todayHoliday, p.today),
            greaterThanOrEqualTo(4.5));
        expect(CalendarContrast.ratio(p.selection, p.surface),
            greaterThanOrEqualTo(3));
        final fills = [
          p.surface,
          p.selectedSurface,
          Colors.white,
          Colors.black,
          const Color(0x800080ff),
          ...effectiveShiftColors(['주간', '야간', '휴무', '오전', '오후'], design, null)
              .values
        ];
        for (final fill in fills) {
          for (final surface in [p.surface, p.selectedSurface]) {
            final painted = Color.alphaBlend(fill, surface);
            expect(
                CalendarContrast.ratio(
                    CalendarContrast.chipInk(fill, surface), painted),
                greaterThanOrEqualTo(4.5));
            final edge = CalendarContrast.chipOutline(fill, surface);
            if (CalendarContrast.ratio(painted, surface) < 3)
              expect(edge, isNotNull);
          }
        }
      }
    }
  });

  test(
      'Identical chip/cell colors remain identifiable, distinct chips stay clean',
      () {
    for (var rgb = 0; rgb <= 255; rgb++) {
      final fill = Color.fromARGB(255, rgb, rgb, rgb);
      final edge = CalendarContrast.chipOutline(fill, fill)!;
      expect(CalendarContrast.ratio(edge.top.color, fill),
          greaterThanOrEqualTo(4.5));
    }
    expect(CalendarContrast.chipOutline(Colors.black, Colors.white), isNull);
    expect(CalendarContrast.chipOutline(Colors.white, Colors.black), isNull);
  });

  test('Saved custom shift colors are never transformed by the reading palette',
      () {
    const custom = {'주간': 0xfff8f9fa, '야간': 0xff050607};
    for (final design in CalendarThemeId.values) {
      final colors = effectiveShiftColors(['주간', '야간'], design, custom);
      expect(colors['주간'], const Color(0xfff8f9fa));
      expect(colors['야간'], const Color(0xff050607));
    }
  });
}
