// ⭐ T03 재실행용 반입(Claude, 2026-09-14): Codex R0-T 초안(docs/release_audit/g0/r0_repro_tests)을 옮기며
// 기대 결과는 바꾸지 않고 연결만 맞춤 - import 경로, README가 요청한 timeout 주입 지점으로 수정본의 stallThreshold(5초)를 주입
// (초안의 30초 가상 시간 안에 멈춤 판정이 나도록)
// R0-02 — 끝나지 않는 필수 초기화에도 유한한 복구 경로가 있어야 한다.
//
// 수정 전 기대 결과(FAIL 이유): c06ffea는 slowThreshold 뒤 spinner만 표시하고 timeout을
// 만들지 않는다. 30초를 pump해도 ElevatedButton이 없어 첫 assertion이 실패한다.
//
// 수정 후 기대 결과: 정책상 상한 안에 실패/복구 화면과 재시도 버튼이 나타난다. 재시도는
// 새 initialize 호출을 정확히 한 번 시작하며, 끝나지 않은 옛 Future가 나중에 완료되어도
// 새 성공 결과를 덮어쓰지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/screens/startup_gate.dart';

void main() {
  testWidgets('R0-02: 필수 초기화 무한 대기를 재시도할 수 있다', (tester) async {
    var calls = 0;
    final firstAttempt = Completer<int>();
    addTearDown(() {
      if (!firstAttempt.isCompleted) firstAttempt.complete(-1);
    });

    await tester.pumpWidget(
      StartupGate<int>(
        slowThreshold: const Duration(milliseconds: 100),
        stallThreshold: const Duration(seconds: 5),
        initialize: () {
          calls++;
          if (calls == 1) return firstAttempt.future;
          return Future<int>.value(7);
        },
        builder: (value) => MaterialApp(home: Scaffold(body: Text('ready $value'))),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: '먼저 지연 상태를 알려야 함');

    // 가상 시간이므로 실제로 30초 기다리지 않는다. 정확한 정책 상한을 주입 가능하게
    // 추가하면 README 설명대로 이 값을 짧은 requiredTimeout으로 교체한다.
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(ElevatedButton), findsOneWidget, reason: '필수 초기화가 끝나지 않아도 복구 동작이 있어야 함');
    expect(calls, 1, reason: '사용자 재시도 전에는 초기화를 중복 실행하면 안 됨');

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(calls, 2, reason: '한 번 누르면 새 시도도 한 번만 실행');
    expect(find.text('ready 7'), findsOneWidget);

    firstAttempt.complete(1);
    await tester.pump();
    expect(find.text('ready 7'), findsOneWidget, reason: '늦게 끝난 옛 시도는 최신 성공을 덮어쓰면 안 됨');
  });
}

