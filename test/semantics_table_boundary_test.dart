import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/semantics_table_boundary.dart';

void main() {
  testWidgets('table labels survive repeated accessibility owner changes',
      (tester) async {
    Widget screen(String label) => MaterialApp(home: Scaffold(
      body: SemanticsTableBoundary(child: Table(children: [
        TableRow(children: [Text(label), const Text('second cell')]),
      ])),
    ));
    await tester.pumpWidget(screen('October 5'));
    for (var i = 0; i < 3; i++) {
      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('October ${5+i}'), findsOneWidget);
      } finally {
        handle.dispose();
      }
      await tester.pumpWidget(screen('October ${6+i}'));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    final afterDispose = tester.ensureSemantics();
    await tester.pump();
    afterDispose.dispose();
    expect(tester.takeException(), isNull);
  }, semanticsEnabled: false);
}
