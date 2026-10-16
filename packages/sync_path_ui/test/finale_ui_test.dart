import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'package:sync_path_ui/src/campaign_visuals.dart';
import 'gates_campaign_test.dart' show current, currentCopy;
import 'support.dart' show enter, fromJson;

const output = String.fromEnvironment(
  'SYNC_PATH_UI_PREVIEW_DIR',
  defaultValue:
      '../../docs/next_version_27이후/game_implementation_v11/ui_previews',
);
Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$output/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (name, path) in [
      ('packages/sync_path_ui/GameSans', 'assets/fonts/GameSansSubset.ttf'),
      (
        'MaterialIcons',
        'C:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(name)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });
  testWidgets('Mounting while already inactive uses the slow heart clock', (
    t,
  ) async {
    var now = DateTime.utc(2026, 10, 15);
    final store = MemoryProgressStore();
    final s = GameSessionController(current(), store, clock: () => now);
    await s.initialize();
    s.hearts.spend();
    s.hearts.spend();
    s.hearts.spend();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pumpWidget(SyncPathGameApp(session: s));
    expect(s.foreground, false);
    now = now.add(const Duration(minutes: 1));
    s.tickHearts();
    expect(s.hearts.available, 0);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    now = now.add(const Duration(seconds: 59));
    await t.pump(const Duration(seconds: 1));
    expect(s.hearts.available, 1);
    await s.flush();
    await t.pumpWidget(const SizedBox());
    s.dispose();
    final restored = GameSessionController(current(), store, clock: () => now);
    await restored.initialize();
    expect(restored.hasPlayed, false);
    restored.dispose();
  });
  test('Every level card chooses readable ink, final red grows darker', () {
    for (var n = 1; n <= 100; n++) {
      final bg = CampaignColors.card(n).computeLuminance();
      final fg = CampaignColors.ink(CampaignColors.card(n)).computeLuminance();
      final ratio = bg > fg ? (bg + .05) / (fg + .05) : (fg + .05) / (bg + .05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'LV $n');
      if (n > 95)
        expect(bg, lessThan(CampaignColors.card(n - 1).computeLuminance()));
    }
  });
  testWidgets(
    'Saved location is visible on first hub and after Android back; test lock stays reachable',
    (t) async {
      t.view.physicalSize = const Size(320, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final store = MemoryProgressStore();
      final initial = GameSessionController(
        current(),
        store,
        unlockAllForTesting: true,
      );
      await initial.initialize();
      initial.openLevel(68);
      initial.leave();
      await initial.flush();
      initial.dispose();
      final s = GameSessionController(current(), store);
      await s.initialize();
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SyncPathGameApp(session: s),
        ),
      );
      await t.pumpAndSettle();
      final card = find.byKey(const ValueKey('level-68'));
      expect(t.getRect(card).top, greaterThan(40));
      expect(t.getRect(card).bottom, lessThan(600));
      expect(
        t.widget<OutlinedButton>(card).style!.side!.resolve({})!.width,
        3.5,
      );
      final locked = t.widget<OutlinedButton>(card);
      expect(locked.onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('test-lock')));
      await t.pumpAndSettle();
      expect(s.unlockAllForTesting, true);
      expect(t.widget<OutlinedButton>(card).onPressed, isNotNull);
      await capture(t, key, 'hub-resume');
      await t.tap(card);
      await t.pumpAndSettle();
      expect(s.selectedUnitId, 'A');
      expect(find.text('A'), findsNothing);
      expect(find.byKey(const ValueKey('heart-0')), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(s.mode, SessionMode.hub);
      expect(t.getRect(card).bottom, lessThan(600));
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  testWidgets(
    'Shared revisited endpoints show four flags; empty hearts refill visibly',
    (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      var now = DateTime.utc(2026, 10, 15);
      final l = LevelSpec(
        identity: const LevelIdentity(
          'visual',
          'shared',
          1,
          constantSpeedRuleSet,
        ),
        map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
        goal: const Cell(4, 4),
        maxCommands: 8,
        units: const [
          UnitSpec('A', Cell(0, 0)),
          UnitSpec('B', Cell(4, 0)),
          UnitSpec('C', Cell(0, 4)),
          UnitSpec('D', Cell(4, 3)),
        ],
      );
      final s = GameSessionController(
        LevelPack('visual', 1, [l]),
        MemoryProgressStore(),
        clock: () => now,
      );
      await s.initialize();
      s.openLevel(0);
      for (final (id, points) in [
        ('A', const [Cell(0, 2), Cell(2, 2), Cell(0, 2), Cell(2, 2)]),
        ('B', const [Cell(4, 2), Cell(2, 2)]),
        ('C', const [Cell(2, 4), Cell(2, 2)]),
        ('D', const [Cell(2, 3), Cell(2, 2)]),
      ]) {
        s.selectUnit(id);
        for (final p in points) {
          expect(s.append(p), true);
        }
      }
      s.hearts.spend();
      s.hearts.spend();
      s.hearts.spend();
      now = now.add(const Duration(seconds: 30));
      s.tickHearts();
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SyncPathGameApp(
            session: s,
            visuals: BoardVisuals(
              unit: RollingBallVisual(),
              tile: BlockTileVisual(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, key, 'shared-stops-heart-half');
      expect(s.hearts.available, 0);
      expect(s.hearts.fraction, .5);
      now = now.add(const Duration(seconds: 30));
      s.tickHearts();
      await t.pumpAndSettle();
      expect(s.hearts.available, 1);
      await capture(t, key, 'shared-stops-heart-full');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  testWidgets(
    'Final board remains usable at 320px; campaign stops at its last level',
    (t) async {
      t.view.physicalSize = const Size(320, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      const previewPath = String.fromEnvironment('SYNC_PATH_UI_PREVIEW_PACK');
      final previewPack = previewPath.isEmpty
          ? current()
          : const LevelParser()
                .parsePack(File(previewPath).readAsStringSync())
                .value!;
      final s = GameSessionController(
        previewPack,
        MemoryProgressStore(),
        unlockAllForTesting: true,
      );
      await s.initialize();
      s.openLevel(s.pack.levels.length - 1);
      for (final (skin, height) in [
        (GameSkin.light, 600.0),
        (GameSkin.dark, 600.0),
        (GameSkin.light, 480.0),
      ]) {
        t.view.physicalSize = Size(320, height);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(
              session: s,
              skin: skin,
              copy: currentCopy(),
              visuals: BoardVisuals(
                unit: RollingBallVisual(),
                tile: BlockTileVisual(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final lastCell = find.byKey(
          ValueKey('cell-${s.level.map.width - 1}-0'),
        );
        final cellBounds = t.getRect(lastCell);
        expect(cellBounds.left, greaterThanOrEqualTo(0));
        expect(cellBounds.right, lessThanOrEqualTo(320));
        await t.ensureVisible(find.byKey(const ValueKey('execute')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('execute')).hitTestable(),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await capture(
          t,
          key,
          '${previewPath.isEmpty ? '' : 'candidate-'}final-${skin == GameSkin.dark ? 'dark' : 'light'}-${height.toInt()}',
        );
        await t.pumpWidget(const SizedBox());
      }
      if (previewPath.isEmpty) {
        final proof = jsonDecode(
          File(
            '../../docs/next_version_27이후/game_implementation_v11/finale_verification.json',
          ).readAsStringSync(),
        );
        enter(s, fromJson(proof['levels'].last['witness']));
        expect(s.routes.every((r) => r.endpoints.length == 14), true);
        t.view.physicalSize = const Size(400, 800);
        final planKey = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: planKey,
            child: SyncPathGameApp(
              session: s,
              visuals: BoardVisuals(
                unit: RollingBallVisual(),
                tile: BlockTileVisual(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await capture(t, planKey, 'final-planned-flags');
        s.execute(reducedMotion: true);
        final activation = s.trace!.gateTimeline.activations.first;
        s.seek(activation.time + .5);
        await t.pumpAndSettle();
        expect(
          s.trace!.gateTimeline.remaining(
            activation.gateId,
            s.replay!.position,
          ),
          greaterThan(0),
        );
        await capture(t, planKey, 'final-door-open');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
      s.leave();
      s.openLevel(s.pack.levels.length);
      expect(s.mode, SessionMode.hub);
      t.view.physicalSize = const Size(400, 850);
      final hubKey = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: hubKey,
          child: SyncPathGameApp(session: s, copy: currentCopy()),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('LV ${s.pack.levels.length}').hitTestable(),
        findsOneWidget,
      );
      await capture(
        t,
        hubKey,
        '${previewPath.isEmpty ? '' : 'candidate-'}final-hub-red',
      );
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
