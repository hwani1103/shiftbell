// 출시 적합성 재검토(docs/release_audit/g6/recheck_2026_09_15/release_readiness_review.md) 반영분 회귀 테스트
//  - AUD-01 로딩 중 시스템 뒤로가기로 진행창이 닫히지 않고, 작업이 끝나면 자기 진행창만 닫음(위에 다른 route가 있어도)
//  - AUD-02 네이티브가 재시작을 거절하면(그 사이 울림 시작) 기다렸다 다시 요청
//  - AUD-05 날짜가 바뀌면 "오늘"을 구독하는 provider가 다시 계산됨

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/providers/current_date_provider.dart';
import 'package:shiftbell/services/app_restart.dart';
import 'package:shiftbell/utils/blocking_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AUD-01 runWithBlockingProgress', () {
    Future<BuildContext> pumpHome(WidgetTester tester) async {
      late BuildContext homeContext;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        homeContext = context;
        return const Scaffold(body: Text('home'));
      })));
      return homeContext;
    }

    testWidgets('뒤로가기로 안 닫히고, 끝나면 자기 진행창만 닫음', (tester) async {
      final ctx = await pumpHome(tester);
      final task = Completer<int>();
      final result = runWithBlockingProgress(ctx, () => task.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: '시스템 뒤로가기로 진행창이 닫히면 안 됨');

      // 작업 중 위에 다른 route가 올라온 경우에도 그 route는 건드리지 않아야 함
      unawaited(Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('top')))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      task.complete(7);
      expect(await result, 7);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('top'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      Navigator.of(ctx).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('home'), findsOneWidget);
      expect(Navigator.of(ctx).canPop(), isFalse, reason: '메인 route는 그대로 남아야 함');
    });

    testWidgets('작업이 실패해도 진행창만 닫고 예외를 그대로 전달', (tester) async {
      final ctx = await pumpHome(tester);
      final result = runWithBlockingProgress<void>(ctx, () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        throw StateError('injected');
      });
      // 예외가 나기 전에 기대를 먼저 걸어야 테스트 zone이 "처리 안 된 예외"로 보지 않음
      final expectation = expectLater(result, throwsStateError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await expectation;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(Navigator.of(ctx).canPop(), isFalse);
    });
  });

  group('AUD-02 restartAppWhenNoAlarmRinging', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

    test('네이티브가 거절하면 대기 안내 후 다시 요청', () async {
      var restartCalls = 0;
      var waited = 0;
      messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
        if (call.method == 'isAlarmRingingLive') return false;
        if (call.method == 'restartApp') return ++restartCalls >= 2; // 첫 요청: 그 사이 울림 시작 → 거절
        return null;
      });
      await restartAppWhenNoAlarmRinging(onWaiting: () => waited++);
      expect(restartCalls, 2);
      expect(waited, greaterThanOrEqualTo(1));
    });

    test('울림 상태 조회 실패는 네이티브 최종 판단에 맡김(거절되면 재시도)', () async {
      var restartCalls = 0;
      messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
        if (call.method == 'isAlarmRingingLive') throw PlatformException(code: 'INJECTED');
        if (call.method == 'restartApp') return ++restartCalls >= 2;
        return null;
      });
      await restartAppWhenNoAlarmRinging();
      expect(restartCalls, 2);
    });
  });

  group('AUD-05 currentDateProvider', () {
    tearDown(() => currentDateClock = DateTime.now);

    test('자정을 넘기면 오늘을 구독하는 provider만 다시 계산', () {
      var now = DateTime(2026, 9, 15, 23, 59);
      currentDateClock = () => now;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var computed = 0;
      final dependent = Provider<DateTime>((ref) {
        computed++;
        return ref.watch(currentDateProvider);
      });

      expect(container.read(dependent), DateTime(2026, 9, 15));
      expect(computed, 1);

      now = DateTime(2026, 9, 15, 23, 59, 50);
      container.read(currentDateProvider.notifier).refresh();
      expect(container.read(dependent), DateTime(2026, 9, 15));
      expect(computed, 1, reason: '같은 날짜면 재계산 안 함');

      now = DateTime(2026, 9, 16, 0, 1);
      container.read(currentDateProvider.notifier).refresh(); // 자정 타이머 또는 앱 재개
      expect(container.read(dependent), DateTime(2026, 9, 16));
      expect(computed, 2);
    });
  });
}
