import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/sleep_edit_dialog.dart';

void main() {
  testWidgets('320dp 화면과 큰 글씨에서도 수면 편집 시트가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final end = DateTime.now().subtract(const Duration(hours: 1));
    final start = end.subtract(const Duration(hours: 6));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => unawaited(
                  showSleepSlotEditDialog(
                    context,
                    initialStart: start,
                    initialEnd: end,
                    showDeleteButton: true,
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('취침'), findsOneWidget);
    expect(find.text('기상'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
