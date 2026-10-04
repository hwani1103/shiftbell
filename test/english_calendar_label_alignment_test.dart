import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/english_calendar_label.dart';

void main() {
  testWidgets('fitted English shift names stay centered in a fixed-height badge',
      (tester) async {
    for (final scale in [1.0, 1.3]) {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final name in ['Day Off', 'Day Shift', 'Night duty', 'Afternoon Shift', 'WWWWWWWWWWWWWWWW'])
              SizedBox(
                key: ValueKey('badge-$name'),
                width: 45,
                height: 24,
                child: EnglishCalendarLabel(name,
                    textKey: ValueKey('text-$name'),
                    style: const TextStyle(fontSize: 14, height: 1.15),
                    textScaler: TextScaler.linear(scale)),
              ),
          ]),
        ),
      ));
      for (final name in ['Day Off', 'Day Shift', 'Night duty', 'Afternoon Shift', 'WWWWWWWWWWWWWWWW']) {
        final text = tester.widget<Text>(find.byKey(ValueKey('text-$name')));
        expect(text.maxLines, 1);
        expect(text.softWrap, false);
        expect(text.data, name);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        final badge = tester.getRect(find.byKey(ValueKey('badge-$name')));
        final line = tester.getRect(find.byKey(ValueKey('text-$name')));
        expect(line.center.dy, closeTo(badge.center.dy, .01), reason: name);
        expect(line.top, greaterThanOrEqualTo(badge.top));
        expect(line.bottom, lessThanOrEqualTo(badge.bottom));
        expect(line.left, greaterThanOrEqualTo(badge.left - .01));
        expect(line.right, lessThanOrEqualTo(badge.right + .01));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
