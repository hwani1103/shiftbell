// test/release_audit/g0/startup_gate_test.dart
//
// G0(T03) V4 - 시작 초기화 게이트 widget 테스트: 실패 화면/다시 시도, 지연 표시, 중복 초기화 방지,
// 오류 원문 표시 조건.
// ⚠️ main.dart의 _initializeApp/_optionalStartupStep(필수·선택 분리, 10초 상한)은 private이라 여기서
//    직접 검증하지 않음 - test_results.md에 NOT_RUN(코드 리뷰만)으로 기록.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/screens/startup_gate.dart';

void main() {
  Widget app(Future<int> Function() init, {Duration slow = const Duration(seconds: 15)}) => StartupGate<int>(
        initialize: init,
        slowThreshold: slow,
        builder: (value) => MaterialApp(home: Scaffold(body: Text('ready $value'))),
      );

  testWidgets('성공하면 builder 결과를 그림', (tester) async {
    await tester.pumpWidget(app(() async => 7));
    await tester.pumpAndSettle();
    expect(find.text('ready 7'), findsOneWidget);
  });

  testWidgets('필수 초기화 실패 → 실패 화면(재시도 버튼), 재시도 성공 → 앱', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(() async {
      calls++;
      if (calls == 1) throw StateError('db open failed: /data/secret/path');
      return 1;
    }));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.text('ready 1'), findsNothing);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('ready 1'), findsOneWidget);
  });

  testWidgets('지연되면 준비 중 표시, 그동안 재시도 버튼 없음·중복 실행 없음, 끝나면 앱', (tester) async {
    var calls = 0;
    final completer = Completer<int>();
    await tester.pumpWidget(app(() {
      calls++;
      return completer.future;
    }, slow: const Duration(seconds: 2)));

    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: '짧은 시작은 빈 화면');

    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(calls, 1);

    completer.complete(5);
    await tester.pumpAndSettle();
    expect(find.text('ready 5'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('R0-02: 끝나지 않는 초기화 → stallThreshold 뒤 다시 시도 버튼, 새 시도 성공 시 앱, 늦게 끝난 옛 시도는 무시', (tester) async {
    var calls = 0;
    final never = Completer<int>();
    await tester.pumpWidget(StartupGate<int>(
      initialize: () {
        calls++;
        return calls == 1 ? never.future : Future.value(9);
      },
      slowThreshold: const Duration(seconds: 2),
      stallThreshold: const Duration(seconds: 5),
      builder: (value) => MaterialApp(home: Scaffold(body: Text('ready $value'))),
    ));

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing, reason: '멈춤 판정 전에는 다시 시도 없음');

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ElevatedButton), findsOneWidget, reason: '멈추면 다시 시도를 열어줘야 함');
    expect(calls, 1);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('ready 9'), findsOneWidget);

    never.complete(1);
    await tester.pumpAndSettle();
    expect(find.text('ready 9'), findsOneWidget, reason: '늦게 끝난 옛 시도의 결과로 바꾸면 안 됨');
    expect(find.text('ready 1'), findsNothing);
  });

  testWidgets('실패가 여러 번 이어져도 다시 시도할 때마다 한 번씩만 실행', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(() async {
      calls++;
      throw StateError('fail $calls');
    }));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }
    expect(calls, 4);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('오류 원문은 errorDetail이 있을 때만 표시 (릴리스에서는 StartupGate가 null을 넘김)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [],
      home: Builder(builder: (context) => const SizedBox()),
    ));
    // StartupStatusScreen은 l10n이 필요하므로 StartupGate 경로로 확인: 테스트는 kReleaseMode=false라 원문이 보여야 함.
    await tester.pumpWidget(app(() async => throw StateError('raw-detail-xyz')));
    await tester.pumpAndSettle();
    expect(find.textContaining('raw-detail-xyz'), findsOneWidget);
  });
}
