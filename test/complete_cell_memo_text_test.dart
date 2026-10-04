import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/complete_cell_memo_text.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    for (final value in ['긴메모내용확인', 'Long memo text', '가👨‍👩‍👧‍👦나']) {
      testWidgets('memo uses complete prefix without ellipsis: $value/$scale',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 32,
                child: CompleteCellMemoText(value,
                    style: const TextStyle(fontSize: 15)),
              ),
            ),
          ),
        ));
        final shown = tester.widget<Text>(find.descendant(
            of: find.byType(CompleteCellMemoText),
            matching: find.byType(Text)));
        final result = shown.data!;
        expect(result, isNot(contains('...')));
        expect(value.characters.toList().join().startsWith(result), isTrue);
        expect(value.characters.toList().take(result.characters.length).join(),
            result);
        final label = find.descendant(
            of: find.byType(CompleteCellMemoText), matching: find.byType(Text));
        final memoRect = tester.getRect(find.byType(CompleteCellMemoText));
        final textRect = tester.getRect(label);
        expect(textRect.left, greaterThanOrEqualTo(memoRect.left + 2));
        expect(textRect.right, lessThanOrEqualTo(memoRect.right - 2));
        double measure(String text) {
          final painter = TextPainter(
              text: TextSpan(text: text, style: shown.style),
              textDirection: TextDirection.ltr,
              textScaler: shown.textScaler!,
              maxLines: 1)
            ..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        expect(measure(result), lessThanOrEqualTo(27.5));
        if (result.characters.length < value.characters.length) {
          expect(
              measure(
                  value.characters.take(result.characters.length + 1).join()),
              greaterThan(27.5),
              reason: 'Show every complete character that fits');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
