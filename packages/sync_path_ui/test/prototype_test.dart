import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart' show enter, fromJson;

LevelPack pack() => const LevelParser()
    .parsePack(
      File(
        '../../docs/next_version_27이후/game_implementation_v4/previous_12_levels.json',
      ).readAsStringSync(),
    )
    .value!;
List<dynamic> report() => jsonDecode(
  File(
    '../../docs/next_version_27이후/game_implementation_v3/level_verification.json',
  ).readAsStringSync(),
)['levels'];
Future<BoardVisuals> visuals() async =>
    BoardVisuals(unit: RollingBallVisual(), tile: BlockTileVisual());

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
      final loader = FontLoader(name)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
  });
  test(
    'All 12 new-rule traces render at constant velocity and exact collision anchors',
    () async {
      var samples = 0;
      final p = pack();
      for (var i = 0; i < 12; i++) {
        final l = p.levels[i];
        final s = GameSessionController(
          LevelPack(p.id, p.revision, [l]),
          MemoryProgressStore(),
        );
        await s.initialize();
        s.openLevel(0);
        enter(s, fromJson(report()[i]['witness']['routes']));
        s.execute();
        final cursor = s.replay!;
        for (var tick = 0; tick < cursor.end * 60; tick++) {
          cursor.seek(tick / 60);
          final frame = const MovementPresentation().frame(
            s,
            visualTime: Duration(days: tick),
          );
          for (final u in frame.units) {
            final piece = s.trace!.motions
                .where(
                  (p) =>
                      p.unitId == u.unitId &&
                      p.startTimeUnits <= cursor.position,
                )
                .last;
            final exact = piece.positionAtGlobal(Rational(tick, 60));
            expect(u.position.x, closeTo(exact.x.toDouble(), 1e-9));
            expect(u.position.y, closeTo(exact.y.toDouble(), 1e-9));
            expect(u.distanceCells / u.durationUnits, 1);
            samples++;
          }
        }
        s.dispose();
      }
      expect(samples, greaterThan(5000));
    },
  );
  test(
    'Selection and motion poses are visual only; reduced motion has a static pose',
    () {
      UnitVisualFrame frame({
        bool selected = false,
        bool reduce = false,
        double distance = 4,
        double duration = 4,
        double progress = .5,
      }) => UnitVisualFrame(
        unitId: 'A',
        paletteIndex: 0,
        position: const DisplayPoint(2, 2),
        facing: UnitFacing.left,
        state: UnitVisualState.moving,
        moveProgress: progress,
        distanceCells: distance,
        durationUnits: duration,
        visualTime: const Duration(seconds: 1),
        playing: true,
        reducedMotion: reduce,
        selected: selected,
      );
      const c = UnitAnimationController();
      expect(
        c.pose(frame(selected: true)).scale,
        greaterThan(c.pose(frame()).scale),
      );
      expect(c.pose(frame()).state, UnitAnimationState.walk);
      expect(
        c.pose(frame(distance: 4, duration: 2)).state,
        UnitAnimationState.run,
      );
      expect(c.pose(frame(progress: 0)).state, UnitAnimationState.start);
      expect(c.pose(frame(progress: 1)).state, UnitAnimationState.stop);
      expect(c.pose(frame(reduce: true)).stride, 0);
    },
  );
  testWidgets(
    'Rolling balls / selection / direction / reactions / pause / background / disposal, 320 and 412 px',
    (tester) async {
      final folder = Directory(
        '../../docs/next_version_27이후/game_implementation_v11/legacy_previews',
      )..createSync(recursive: true);
      for (final width in [320.0, 412.0]) {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        final s = GameSessionController(
          pack(),
          MemoryProgressStore(),
          unlockAllForTesting: true,
        );
        await s.initialize();
        s.openLevel(7);
        final art = await tester.runAsync(visuals);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(
              key: ValueKey(width),
              session: s,
              visuals: art!,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        Future<void> shot(String name) async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${folder.path}/$name-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await shot('selected');
        enter(s, fromJson(report()[7]['witness']['routes']));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await shot('planned');
        s.execute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1400));
        await shot('walking');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        final paused = s.replay!.position;
        await tester.pump(const Duration(seconds: 3));
        expect(s.replay!.position, paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(s.mode, SessionMode.paused);
        s.resume();
        await tester.pump();
        await tester.pump(const Duration(seconds: 10));
        expect(s.mode, SessionMode.successReview);
        await tester.pump(const Duration(milliseconds: 200));
        await shot('goal');
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        s.openLevel(1);
        enter(s, [
          UnitRoute('A', [const Cell(2, 0), const Cell(2, 2)]),
          UnitRoute('B', [const Cell(2, 0), const Cell(2, 2)]),
        ]);
        s.execute();
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(s.mode, SessionMode.failureReview);
        await tester.pump(const Duration(milliseconds: 250));
        await shot('collision');
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        s.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('Prototype respects reduced motion and manual cell-time replay', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final s = GameSessionController(
      pack(),
      MemoryProgressStore(),
      unlockAllForTesting: true,
    );
    await s.initialize();
    s.openLevel(7);
    final art = await tester.runAsync(visuals);
    await tester.pumpWidget(SyncPathGameApp(session: s, visuals: art!));
    await tester.pumpAndSettle();
    enter(s, fromJson(report()[7]['witness']['routes']));
    s.execute(reducedMotion: true);
    await tester.pumpAndSettle();
    expect(s.mode, SessionMode.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(s.replay!.position, 0);
    s.nextScene();
    expect(s.replay!.position, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
