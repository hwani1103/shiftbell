import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/app_text_scale.dart';

void main() {
  testWidgets('fractional scales and runtime changes reach routes and dialogs',
      (tester) async {
    var requested = 1.0;
    late StateSetter update;
    final navigator = GlobalKey<NavigatorState>();
    final observed = <String, double>{};
    Widget probe(String name) => Builder(builder: (context) {
          observed[name] = MediaQuery.textScalerOf(context).scale(20) / 20;
          return Text(name);
        });
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      update = setState;
      return MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(requested)),
          child: AppTextScale(child: child!),
        ),
        home: Scaffold(body: probe('route')),
      );
    }));
    showDialog<void>(
        context: tester.element(find.text('route')),
        builder: (_) => AlertDialog(content: probe('dialog')));
    await tester.pumpAndSettle();
    for (final scale in [1.0, 1.09, 1.25, 1.28, 1.3, 1.31, 1.6, 2.0, 1.09]) {
      update(() => requested = scale);
      await tester.pumpAndSettle();
      final expected = scale > 1.3 ? 1.3 : scale;
      expect(observed['route'], closeTo(expected, 1e-9));
      expect(observed['dialog'], closeTo(expected, 1e-9));
      expect(tester.takeException(), isNull);
    }
  });
}
