import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/widgets/global_concept_calendar_cell.dart';

// Calculate relative luminance independently from the production helper.
double luminance(Color color) {
  double linear(double value) => value <= .04045
      ? value / 12.92
      : math.pow((value + .055) / 1.055, 2.4).toDouble();
  return .2126 * linear(color.r) +
      .7152 * linear(color.g) +
      .0722 * linear(color.b);
}

double contrast(Color foreground, Color background) {
  final a = luminance(foreground), b = luminance(background);
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  testWidgets(
      'Soft Mosaic chooses the most readable black/white on its actual badge',
      (tester) async {
    final colors = <Color>{
      ...kMainLightPalette,
      ...kMainDarkPalette,
      ...kPeriwinklePalette,
      Colors.black,
      Colors.white,
      const Color(0xFF4B4B4B),
      const Color(0xFF505050),
      const Color(0xFF535353),
      const Color(0xFF575757),
      const Color(0xFF006000),
      const Color(0xFF0020A0),
      const Color(0xFF600060),
      const Color(0xFFFFD000),
    };
    var blackCount = 0, whiteCount = 0;
    for (final color in colors) {
      for (final window in [const Size(411, 891), const Size(704, 933)]) {
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(size: window),
          child: Center(
              child: SizedBox(
            width: 72,
            height: 108,
            child: GlobalConceptCalendarCell(
              theme: CalendarThemeId.softMosaic,
              date: DateTime(2026, 10, 9), shift: 'Night',
              shiftColor: color,
              // Deliberately incorrect: the mosaic must calculate its own ink.
              shiftTextColor: Colors.pink,
              memos: const [], today: false, outside: false,
              red: false, selected: true,
            ),
          )),
        )));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final text = find.text('Night');
        final actualInk = tester.widget<Text>(text).style!.color!;
        final badge = tester.widget<Container>(
            find.ancestor(of: text, matching: find.byType(Container)).first);
        final actualBackground = (badge.decoration! as BoxDecoration).color!;
        final black = contrast(Colors.black, actualBackground);
        final white = contrast(Colors.white, actualBackground);
        expect(actualInk.toARGB32(),
            (black >= white ? Colors.black : Colors.white).toARGB32(),
            reason:
                'shift=${color.toARGB32().toRadixString(16)} window=$window');
        expect(
            contrast(actualInk, actualBackground), greaterThanOrEqualTo(4.5));
        actualInk == Colors.black ? blackCount++ : whiteCount++;
        // The pale cell background would choose black here, but its badge
        // needs white. This catches accidentally using the wrong background.
        if (color == Colors.black) expect(actualInk, Colors.white);
      }
    }
    expect(blackCount, greaterThan(0));
    expect(whiteCount, greaterThan(0));
  });
}
