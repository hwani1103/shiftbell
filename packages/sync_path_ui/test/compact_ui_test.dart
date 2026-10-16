import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'gates_campaign_test.dart' show current, open;
import 'support.dart' show enter, fromJson;

Future<void> tap(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Compact four-ball board fits 320x600; menu has help and reset; no replay UI',
    (t) async {
      t.view.physicalSize = const Size(320, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = await open(49);
      await t.pumpWidget(SyncPathGameApp(session: s));
      await t.pumpAndSettle();
      expect(find.text('LV 50'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.byKey(const ValueKey('replay')), findsNothing);
      expect(find.byKey(const ValueKey('restart')), findsNothing);
      expect(
        t.getRect(find.byKey(const ValueKey('execute'))).bottom,
        lessThanOrEqualTo(600),
      );
      expect(
        t.getRect(find.byKey(const ValueKey('unit-A'))).top,
        t.getRect(find.byKey(const ValueKey('unit-D'))).top,
      );
      await tap(t, 'game-menu');
      expect(find.byKey(const ValueKey('menu-help')), findsOneWidget);
      await tap(t, 'menu-restart');
      expect(s.routes.every((r) => r.endpoints.isEmpty), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  testWidgets('Last non-goal endpoint shows red counter and undo restores it', (
    t,
  ) async {
    final s = await open(0);
    s.selectUnit('A');
    s.append(const Cell(0, 1));
    s.append(const Cell(0, 0));
    await t.pumpWidget(SyncPathGameApp(session: s));
    await t.pumpAndSettle();
    expect(find.text(const GameStrings().exhausted), findsOneWidget);
    final card = t.widget<OutlinedButton>(find.byKey(const ValueKey('unit-A')));
    expect(card.style!.side!.resolve({})!.color, GameSkin.light.collision);
    expect(s.canExecute, isFalse);
    await tap(t, 'undo');
    expect(find.text(const GameStrings().exhausted), findsNothing);
    expect(s.routes.first.endpoints.length, 1);
    await t.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets('Failure prioritizes fresh restart; partial edit remains in menu', (
    t,
  ) async {
    final s = await open(30);
    final p = jsonDecode(
      File(
        '../../docs/next_version_27이후/game_implementation_v8/gate_verification.json',
      ).readAsStringSync(),
    );
    enter(s, fromJson(p['levels'][0]['failure']));
    await t.pumpWidget(SyncPathGameApp(session: s));
    await t.pumpAndSettle();
    final before = t.getTopLeft(find.byType(GameBoard));
    s.execute();
    s.advance(const Duration(minutes: 1));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byType(GameBoard)), before);
    expect(find.byKey(const ValueKey('restart')), findsOneWidget);
    expect(find.byKey(const ValueKey('exit')), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tap(t, 'restart');
    expect(s.mode, SessionMode.planning);
    expect(s.routes.every((r) => r.endpoints.isEmpty), isTrue);
    expect(t.getTopLeft(find.byType(GameBoard)), before);
    await t.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'Only Lv1 first entry opens basic rules, persisted after dismissal',
    (t) async {
      final store = MemoryProgressStore();
      final s = GameSessionController(
        current(),
        store,
        unlockAllForTesting: true,
      );
      await s.initialize();
      s.openLevel(0);
      await t.pumpWidget(SyncPathGameApp(session: s, showIntro: true));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      expect(find.byKey(const ValueKey('help-back')), findsNothing);
      await tap(t, 'help-next');
      expect(s.rulesSeen, isTrue);
      expect(s.gateRulesSeen, isFalse);
      s.openLevel(30);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await s.flush();
      await t.pumpWidget(const SizedBox());
      s.dispose();
      final restored = GameSessionController(
        current(),
        store,
        unlockAllForTesting: true,
      );
      await restored.initialize();
      expect(restored.rulesSeen, isTrue);
      expect(restored.gateRulesSeen, isFalse);
      restored.openLevel(0);
      await t.pumpWidget(SyncPathGameApp(session: restored, showIntro: true));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      restored.dispose();
    },
  );
}
