import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/app_content_frame.dart';

void main() {
  const fold8Cover = Size(400, 632);
  const fold8Inner = Size(662, 876);

  Future<void> pumpFrame(WidgetTester tester, Size viewport) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppContentFrame(child: child!),
        home: Builder(
          builder: (context) => SizedBox.expand(
            key: const ValueKey('content'),
            child: Text('${MediaQuery.sizeOf(context).width}'),
          ),
        ),
      ),
    );
  }

  testWidgets('Fold8 cover keeps the normal phone width', (tester) async {
    await pumpFrame(tester, fold8Cover);

    expect(tester.getRect(find.byKey(const ValueKey('content'))),
        const Rect.fromLTWH(0, 0, 400, 632));
    expect(find.text('400.0'), findsOneWidget);
  });

  testWidgets('Fold8 inner uses the full window', (tester) async {
    await pumpFrame(tester, fold8Inner);

    expect(tester.getRect(find.byKey(const ValueKey('content'))),
        const Rect.fromLTWH(0, 0, 662, 876));
    expect(find.text('662.0'), findsOneWidget);
  });
}
