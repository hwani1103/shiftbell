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

LevelPack campaign30() => const LevelParser()
    .parsePack(
      File(
        '../../docs/next_version_27이후/game_implementation_v7/previous_30_pilot_levels.json',
      ).readAsStringSync(),
    )
    .value!;
Map<String, dynamic> evidence(String name) => jsonDecode(
  File(
    '../../docs/next_version_27이후/game_implementation_v7/$name.json',
  ).readAsStringSync(),
);
Map<String, PuzzleCopy> copies30() {
  final data =
      jsonDecode(
            File(
              '../../docs/next_version_27이후/game_implementation_v7/previous_30_pilot_copy.json',
            ).readAsStringSync(),
          )
          as Map;
  return {
    for (final entry in data.entries)
      entry.key as String: PuzzleCopy(
        entry.value['titleKo'],
        entry.value['titleEn'],
        List<String>.from(entry.value['hintsKo']),
        List<String>.from(entry.value['hintsEn']),
        chapterKo: entry.value['chapterKo'],
        chapterEn: entry.value['chapterEn'],
      ),
  };
}

Future<GameSessionController> session30(int index) async {
  final s = GameSessionController(
    campaign30(),
    MemoryProgressStore(),
    unlockAllForTesting: true,
    playbackRate: 1.5,
  );
  await s.initialize();
  s.openLevel(index);
  return s;
}

final class RecordingTiles extends TileVisual {
  final frames = <TileVisualFrame>[];
  final delegate = BlockTileVisual();
  @override
  void paint(Canvas canvas, Rect bounds, TileVisualFrame frame, GameSkin skin) {
    frames.add(frame);
    delegate.paint(canvas, bounds, frame, skin);
  }

  @override
  void dispose() => delegate.dispose();
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
      final loader = FontLoader(name)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
  });
  test(
    'Thirty safe puzzles respect tutorial, unit introduction and board contracts',
    () async {
      final pack = campaign30(),
          report = evidence('level_verification'),
          design = evidence('campaign_design'),
          words = copies30();
      expect(pack.id, 'dev-campaign-30-condensed');
      expect(pack.levels.length, 30);
      expect(words.length, 30);
      expect(words.values.where((w) => w.chapterKo != null).length, 6);
      var previous = -1.0;
      for (var i = 0; i < 30; i++) {
        final l = pack.levels[i], m = design['levels'][i]['metrics'];
        expect(
          l.units.length,
          i < 6
              ? 2
              : i < 15
              ? 3
              : 4,
        );
        expect(l.map.width, isIn([5, 6, 7]));
        expect(l.map.height, l.map.width);
        for (final u in l.units)
          expect(
            (u.start.x - l.goal.x).abs() + (u.start.y - l.goal.y).abs(),
            greaterThanOrEqualTo(3),
          );
        expect(m['score'], greaterThan(previous));
        previous = (m['score'] as num).toDouble();
        final s = await session30(i);
        enter(s, fromJson(report['levels'][i]['witness']['routes']));
        expect(s.canExecute, isTrue);
        s.execute();
        expect(s.trace!.outcome, SimulationOutcome.success);
        s.advance(const Duration(minutes: 1));
        expect(s.completedLevels, contains(l.identity));
        s.dispose();
      }
      expect(report['levels'][0].containsKey('failureExample'), isFalse);
      for (final index in [1, 2])
        expect(report['levels'][index].containsKey('failureExample'), isTrue);
    },
  );
  testWidgets('Board stays anchored when starting, pausing and editing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await session30(0);
    enter(
      s,
      fromJson(
        evidence('level_verification')['levels'][0]['witness']['routes'],
      ),
    );
    await tester.pumpWidget(SyncPathGameApp(session: s, copy: copies30()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('execute')));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('cell-0-0'));
    final before = tester.getTopLeft(cell);
    await tester.tap(find.byKey(const ValueKey('execute')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getTopLeft(cell), before);
    s.pause();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(cell), before);
    s.restart();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(cell), before);
    s.leave();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('level-29')));
    await tester.tap(find.byKey(const ValueKey('level-29')));
    await tester.pumpAndSettle();
    final firstFrame = tester.getTopLeft(cell);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(cell), firstFrame);
    expect(firstFrame.dy, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'Selected ball guide and highlighted legal cells follow the chosen route',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await session30(29), tiles = RecordingTiles();
      await tester.pumpWidget(
        SyncPathGameApp(
          session: s,
          copy: copies30(),
          visuals: BoardVisuals(unit: RollingBallVisual(), tile: tiles),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unit-A')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('unit-D')));
      await tester.pumpAndSettle();
      tiles.frames.clear();
      await tester.tap(find.byKey(const ValueKey('unit-D')));
      await tester.pumpAndSettle();
      expect(s.selectedUnitId, 'D');
      expect(find.byKey(const ValueKey('unit-D')), findsOneWidget);
      expect(find.text(const GameStrings().planningUnit('D')), findsNothing);
      final legal = tiles.frames.where((f) => f.legalDestination);
      expect(legal, isNotEmpty);
      expect(
        legal.every((f) => f.destinationColor == GameSkin.light.unitColors[3]),
        isTrue,
      );
      expect(
        find.text(const GameStrings().legalCells(s.destinations.length)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  testWidgets(
    'Every map fits 320px without hiding a column; selected chapter screens render',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final folder = Directory(
        '../../docs/next_version_27이후/game_implementation_v11/historical30_previews',
      )..createSync(recursive: true);
      for (var i = 0; i < 30; i++) {
        final s = await session30(i), key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(
              session: s,
              copy: copies30(),
              visuals: BoardVisuals(
                unit: RollingBallVisual(),
                tile: BlockTileVisual(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final right = tester.getRect(
          find.byKey(ValueKey('cell-${s.level.map.width - 1}-0')),
        );
        expect(right.right, lessThanOrEqualTo(320));
        if ([0, 3, 9, 14, 19, 24, 26, 29, 34, 39, 44, 49].contains(i)) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${folder.path}/campaign30-L${i + 1}-320.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(find.byKey(const ValueKey('execute')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('execute'))).bottom,
          lessThanOrEqualTo(1100),
        );
        await tester.pumpWidget(const SizedBox());
        s.dispose();
      }
    },
  );
}
