import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/calendar_alarm_cards.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness cards stay bounded and editable after fold resize',
        (tester) async {
      var edits = 0;
      for (final width in [280.0, 390.0, 600.0, 840.0, 320.0]) {
        await tester.binding.setSurfaceSize(Size(width, 380));
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 380), textScaler: const TextScaler.linear(1.6)),
            child: Scaffold(
              body: CalendarAlarmCardStrip(cards: [
                for (var i = 0; i < 5; i++)
                  CalendarAlarmCard(
                    key: ValueKey(i),
                    time: '09:05',
                    label: 'Ton und Vibration / ध्वनि और कंपन',
                    leading: const Text('🔔'),
                    onTap: () => edits++,
                  ),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey(0));
        expect(tester.getSize(first).width, inInclusiveRange(132, 236));
        final scrolling = tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
        expect(scrolling.scrollDirection, Axis.horizontal);
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(1500, 0));
        await tester.pumpAndSettle();
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(edits, 5);
      await tester.binding.setSurfaceSize(null);
    });
  }
}
