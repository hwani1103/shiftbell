import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart';

final class TestCharacter extends UnitVisual {
  int paints = 0, disposals = 0;
  final frames = <UnitVisualFrame>[];
  @override
  void paint(
    Canvas canvas,
    Offset center,
    double pitch,
    UnitVisualFrame frame,
    GameSkin skin,
  ) {
    paints++;
    frames.add(frame);
    // Intentionally huge, offset silhouette. Never a logical collider.
    canvas.drawCircle(
      center + const Offset(8, -10),
      25,
      Paint()..color = skin.goal,
    );
  }

  @override
  void dispose() {
    disposals++;
  }
}

void main() {
  test(
    'Different distances share one Step; visual clock never changes position/progress',
    () async {
      final level = LevelSpec(
        identity: const LevelIdentity(
          'test-pack',
          'speed',
          1,
          supportedRuleSet,
        ),
        map: GridMap(width: 6, height: 6, rows: List.filled(6, '......')),
        goal: const Cell(5, 5),
        units: const [UnitSpec('A', Cell(0, 0)), UnitSpec('B', Cell(0, 5))],
        maxCommands: 3,
      );
      final s = GameSessionController(
        LevelPack('test-pack', 1, [level]),
        MemoryProgressStore(),
      );
      await s.initialize();
      s.openLevel(0);
      addTearDown(s.dispose);
      enter(s, [
        UnitRoute('A', [const Cell(1, 0), const Cell(1, 5), level.goal]),
        UnitRoute('B', [level.goal]),
      ]);
      s.execute();
      s.advance(const Duration(milliseconds: 325));
      final a = const MovementPresentation().frame(
        s,
        visualTime: const Duration(milliseconds: 1),
      );
      final b = const MovementPresentation().frame(
        s,
        visualTime: const Duration(days: 1),
      );
      expect(a.units.map((u) => u.moveProgress), [0.5, 0.5]);
      expect(a.units.map((u) => u.distanceCells), [1.0, 5.0]);
      expect(
        a.units.map((u) => u.position.x),
        b.units.map((u) => u.position.x),
      );
      expect(a.units.map((u) => u.facing), [
        UnitFacing.right,
        UnitFacing.right,
      ]);
      s.advance(const Duration(milliseconds: 325));
      final after = const MovementPresentation().frame(s, reducedMotion: true);
      expect(after.units.map((u) => u.unitId), ['A']);
      expect(after.units.single.facing, UnitFacing.down);
      expect(after.cues.single.kind, VisualCueKind.goal);
      expect(after.cues.single.unitIds, ['B']);
      expect(after.units.single.reducedMotion, isTrue);
    },
  );
  test(
    'Collision pose/cue uses exact engine event, even between tiles',
    () async {
      final s = await session(11);
      addTearDown(s.dispose);
      enter(
        s,
        fromJson(certificates()['levels'][11]['failureExample']['routes']),
      );
      s.execute();
      s.advance(const Duration(seconds: 1));
      final frame = const MovementPresentation().frame(s);
      expect(
        frame.units
            .where((u) => u.state == UnitVisualState.collision)
            .map((u) => u.unitId),
        ['A', 'B'],
      );
      final cue = frame.cues.single;
      expect(cue.kind, VisualCueKind.collision);
      expect(cue.timeInSteps, Rational(1, 2));
      expect(cue.position.x, Rational(9, 2));
      expect(cue.position.y, Rational(2));
      expect(() => frame.units.clear(), throwsUnsupportedError);
      expect(() => cue.unitIds.clear(), throwsUnsupportedError);
    },
  );
  test(
    'Route snapshot is reused across frames, invalidated only by path changes',
    () async {
      final s = await session(0);
      addTearDown(s.dispose);
      final original = s.routes;
      s.selectUnit('A');
      s.append(const Cell(0, 2));
      expect(identical(original, s.routes), isFalse);
      enter(s, [
        UnitRoute('A', [s.level.goal]),
        UnitRoute('B', [const Cell(4, 2), s.level.goal]),
      ]);
      final snapshot = s.routes;
      s.execute();
      s.advance(const Duration(milliseconds: 100));
      expect(identical(snapshot, s.routes), isTrue);
      expect(() => snapshot.clear(), throwsUnsupportedError);
    },
  );
  testWidgets(
    'Renderer/silhouette replacement leaves trace unchanged and releases resources',
    (tester) async {
      final s = await session(0);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      s.execute();
      s.pause();
      final trace = jsonEncode(s.trace!.toJson());
      final first = TestCharacter();
      final second = TestCharacter();
      await tester.pumpWidget(
        SyncPathGameApp(
          session: s,
          visuals: BoardVisuals(unit: first),
        ),
      );
      await tester.pump();
      expect(first.paints, greaterThan(0));
      expect(jsonEncode(s.trace!.toJson()), trace);
      await tester.pumpWidget(
        SyncPathGameApp(
          session: s,
          visuals: BoardVisuals(unit: second),
          skin: GameSkin.dark,
        ),
      );
      await tester.pump();
      expect(first.disposals, 1);
      expect(second.paints, greaterThan(0));
      expect(jsonEncode(s.trace!.toJson()), trace);
      await tester.pumpWidget(const SizedBox());
      expect(second.disposals, 1);
    },
  );
}
