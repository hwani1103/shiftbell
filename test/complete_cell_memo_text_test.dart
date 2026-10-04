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
        expect(tester.takeException(), isNull);
      });
    }
  }
}
