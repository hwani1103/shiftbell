import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/word_safe_spans.dart';

void main() {
  testWidgets('word-preserving inline text applies system scale only once', (tester) async {
    double? normalHeight;
    for (final scale in [1.0, 1.6, 2.0]) {
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Text.rich(key: const ValueKey('paragraph'),
          TextSpan(children: wordSafeSpans('Hello', const TextStyle(fontSize: 16))))),
      )));
      final height = tester.getSize(find.byKey(const ValueKey('paragraph'))).height;
      normalHeight ??= height;
      expect(height, lessThanOrEqualTo(normalHeight * scale + 2));
      expect(height, greaterThanOrEqualTo(normalHeight * scale - 2));
      expect(tester.takeException(), isNull);
    }
  });
}
