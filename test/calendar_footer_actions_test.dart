import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/calendar_footer_actions.dart';

void main() {
  for (final width in [280.0, 475.0, 932.0]) {
    testWidgets('summary actions separate and independently tappable at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var monthly = 0, weekly = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      child: CalendarFooterActions(
                        monthly:
                            const Text('Überstunden im Monat 12 Std. 30 Min.'),
                        weekly: const Text('Wochenarbeitszeit ›',
                            textAlign: TextAlign.right),
                        onMonthly: () => monthly++,
                        onWeekly: () => weekly++,
                      ))))));
      final left = find.byKey(const ValueKey('calendar-monthly-summary'));
      final right = find.byKey(const ValueKey('calendar-weekly-summary'));
      final l = tester.getRect(left), r = tester.getRect(right);
      expect(r.right - l.left, width);
      expect(r.left - l.right, 16);
      expect(l.height, greaterThanOrEqualTo(48));
      expect(r.height, greaterThanOrEqualTo(48));
      await tester.tap(left);
      expect(monthly, 1);
      expect(weekly, 0);
      await tester.tap(right);
      expect(monthly, 1);
      expect(weekly, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
