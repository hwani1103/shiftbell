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
import 'campaign30_condensed_test.dart' show campaign30;

final evidenceDir = '../../docs/next_version_27이후/game_implementation_v8';
LevelPack current() => const LevelParser()
    .parsePack(
      File(
        '../../examples/sync_path_lab/assets/pilot_levels.json',
      ).readAsStringSync(),
    )
    .value!;
Map<String, dynamic> proof() =>
    jsonDecode(File('$evidenceDir/gate_verification.json').readAsStringSync());
Future<GameSessionController> open(int i) async {
  final s = GameSessionController(
    current(),
    MemoryProgressStore(),
    unlockAllForTesting: true,
    playbackRate: 1.5,
  );
  await s.initialize();
  s.openLevel(i);
  return s;
}

Map<String, PuzzleCopy> currentCopy() {
  final j =
      jsonDecode(
            File(
              '../../examples/sync_path_lab/assets/pilot_copy.json',
            ).readAsStringSync(),
          )
          as Map;
  return {
    for (final e in j.entries)
      e.key as String: PuzzleCopy(
        e.value['titleKo'] ?? '',
        e.value['titleEn'] ?? '',
        List<String>.from(e.value['hintsKo']),
        List<String>.from(e.value['hintsEn']),
      ),
  };
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
    'Fifty levels preserve first thirty and all twenty gate hints succeed',
    () async {
      final p = current(), old = campaign30();
      expect(p.levels.length, 100);
      for (var i = 0; i < 30; i++) {
        expect(p.levels[i].map.rows, old.levels[i].map.rows);
        expect(p.levels[i].goal, old.levels[i].goal);
        expect(p.levels[i].gates, isEmpty);
      }
      for (var i = 30; i < 50; i++) {
        final l = p.levels[i];
        expect(l.gates.length, i < 41 ? 1 : 2);
        expect(
          l.units.length,
          i < 33
              ? 2
              : i < 41
              ? 3
              : 4,
        );
        expect(l.map.width, isIn([5, 6, 7]));
        expect(l.map.width, l.map.height);
        final s = await open(i);
        enter(s, fromJson(proof()['levels'][i - 30]['witness']));
        s.execute();
        expect(s.trace!.outcome, SimulationOutcome.success);
        s.advance(const Duration(minutes: 1));
        expect(s.completedLevels, contains(l.identity));
        s.dispose();
      }
    },
  );
  testWidgets('Gate failure, seek, editing and narrow-board rendering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    for (final i in [30, 33, 41, 49]) {
      final s = await open(i);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SyncPathGameApp(
            session: s,
            copy: currentCopy(),
            visuals: BoardVisuals(
              unit: RollingBallVisual(),
              tile: BlockTileVisual(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(const GameStrings().gateHelp), findsNothing);
      expect(
        tester
            .getRect(find.byKey(ValueKey('cell-${s.level.map.width - 1}-0')))
            .right,
        lessThanOrEqualTo(320),
      );
      await tester.runAsync(() async {
        final img =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File(
          '../../docs/next_version_27이후/game_implementation_v11/regression_previews/L${i + 1}.png',
        );
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes!.buffer.asUint8List());
        img.dispose();
      });
      enter(s, fromJson(proof()['levels'][i - 30]['failure']));
      s.execute(reducedMotion: true);
      s.seek(s.trace!.durationInTimeUnits.toDouble());
      s.nextScene();
      await tester.pumpAndSettle();
      expect(s.mode, SessionMode.failureReview);
      final fail = s.trace!.gateTimeline.failures.first;
      expect(
        find.text(const GameStrings().gateFailure(fail.unitId, fail.gateId)),
        findsOneWidget,
      );
      expect(
        s.trace!.gateTimeline.remaining(fail.gateId, s.replay!.position),
        0,
      );
      s.seek(0);
      await tester.pumpAndSettle();
      expect(s.trace!.gateTimeline.remaining(fail.gateId, 0), 0);
      s.editFailure();
      await tester.pumpAndSettle();
      expect(s.mode, SessionMode.planning);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    }
  });
}
