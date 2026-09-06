import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiftbell/main.dart';

void main() {
  testWidgets('MyApp builds without throwing', (WidgetTester tester) async {
    // ⭐ 2026-09-04 - LOW 항목 수정(전체_코드_점검_리포트_2026-09-04.md).
    // MyApp은 main.dart의 runApp()에서 항상 ProviderScope 하위로 실행되는데
    // (calendarThemeProvider override 포함), 이 테스트만 그 없이 pump해서
    // "No ProviderScope found"로 항상 실패하고 있었음.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
