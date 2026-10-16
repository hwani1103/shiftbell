import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'package:sync_path_ui/src/hearts.dart';
import 'package:sync_path_ui/src/waypoint_visual.dart';
import 'support.dart';

void main() {
  test(
    'Lifecycle while loading never overwrites the existing saved game',
    () async {
      final store = _PendingStore();
      final s = GameSessionController(pilot(), store);
      final loading = s.initialize();
      s.setForeground(false);
      s.tickHearts();
      await s.flush();
      expect(store.writes, 0);
      store.reading.complete(null);
      await loading;
      expect(s.foreground, false);
      s.dispose();
    },
  );
  test(
    'Blue is selected on open/restart; buttons toggle; completing a path selects next',
    () async {
      final s = await session(0);
      expect(s.selectedUnitId, 'A');
      expect(s.destinations, isNotEmpty);
      s.toggleUnit('A');
      expect(s.selectedUnitId, isNull);
      expect(s.append(const Cell(0, 2)), isFalse);
      s.toggleUnit('B');
      expect(s.selectedUnitId, 'B');
      s.toggleUnit('B');
      expect(s.selectedUnitId, isNull);
      s.toggleUnit('A');
      s.append(const Cell(0, 2));
      expect(s.selectedUnitId, 'A');
      s.append(s.level.goal);
      expect(s.selectedUnitId, 'B');
      s.selectUnit('A');
      s.undo();
      expect(s.routes.first.endpoints.length, 1);
      s.leave();
      s.openLevel(0);
      expect(s.selectedUnitId, 'A');
      expect(s.routes.first.endpoints, isEmpty);
      s.toggleUnit('A');
      s.restart();
      expect(s.selectedUnitId, 'A');
      s.dispose();
    },
  );

  test(
    'Only exhaustion starts recovery; foreground and background credit combine',
    () {
      final h = LevelHearts();
      h.spend();
      h.elapse(const Duration(days: 2), foreground: true);
      expect(h.available, 2);
      expect(h.recovering, false);
      h.spend();
      h.spend();
      expect(h.spend(), false);
      h.elapse(const Duration(seconds: 30), foreground: true);
      h.elapse(const Duration(minutes: 30), foreground: false);
      expect(h.available, 1);
      expect(h.fraction, 0);
      h.spend(); // does not restart an in-progress recovery cycle
      h.elapse(const Duration(minutes: 3), foreground: true);
      expect(h.available, 3);
      expect(h.recovering, false);
    },
  );

  test(
    'Automatic selection skips finished balls and stops switching when all are ready',
    () async {
      final level = LevelSpec(
        identity: const LevelIdentity(
          'selection',
          'four',
          1,
          constantSpeedRuleSet,
        ),
        map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
        goal: const Cell(2, 2),
        maxCommands: 2,
        units: const [
          UnitSpec('A', Cell(0, 0)),
          UnitSpec('B', Cell(4, 0)),
          UnitSpec('C', Cell(0, 4)),
          UnitSpec('D', Cell(4, 4)),
        ],
      );
      final s = GameSessionController(
        LevelPack('selection', 1, [level]),
        MemoryProgressStore(),
      );
      await s.initialize();
      s.openLevel(0);
      s.selectUnit('C');
      s.append(const Cell(0, 2));
      s.append(level.goal);
      expect(s.selectedUnitId, 'D');
      s.selectUnit('A');
      s.append(const Cell(0, 2));
      s.append(level.goal);
      expect(s.selectedUnitId, 'B');
      s.append(const Cell(4, 2));
      s.append(level.goal);
      expect(s.selectedUnitId, 'D');
      s.append(const Cell(4, 2));
      s.append(level.goal);
      expect(s.selectedUnitId, 'D');
      expect(s.canExecute, true);
      s.toggleUnit('D');
      expect(s.selectedUnitId, isNull);
      expect(s.canExecute, true);
      s.dispose();
    },
  );

  test(
    'Per-level pools persist, lock toggle is temporary and cannot refill hearts',
    () async {
      var now = DateTime.utc(2026, 10, 15);
      final store = MemoryProgressStore();
      final s = GameSessionController(pilot(), store, clock: () => now);
      await s.initialize();
      s.openLevel(0);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      for (var i = 0; i < 3; i++) {
        s.execute();
        s.advance(const Duration(minutes: 1));
        if (i < 2) {
          s.restart();
          enter(s, fromJson(certificates()['levels'][0]['witness']));
        }
      }
      expect(s.hearts.available, 0);
      s.restart();
      expect(s.editable, false);
      expect(s.append(s.destinations.firstOrNull ?? const Cell(0, 2)), false);
      expect(s.canExecute, false);
      s.execute();
      expect(s.mode, SessionMode.planning);
      s.toggleTesting();
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      expect(s.canExecute, true);
      s.execute();
      s.advance(const Duration(minutes: 1));
      expect(s.hearts.available, 0);
      s.leave();
      s.openLevel(7);
      expect(s.hearts.available, 3);
      now = now.add(const Duration(seconds: 30));
      s.tickHearts();
      s.setForeground(false);
      now = now.add(const Duration(minutes: 30));
      await s.flush();
      s.dispose();
      final restored = GameSessionController(pilot(), store, clock: () => now);
      await restored.initialize();
      expect(restored.unlockAllForTesting, false);
      expect(
        restored.levelIndex,
        7,
      ); // preserve tester's draft without unlocking it
      restored.openLevel(7);
      expect(restored.mode, SessionMode.hub);
      restored.openLevel(0);
      expect(restored.hearts.available, 1);
      expect(restored.selectedUnitId, 'A');
      restored.dispose();
    },
  );

  test(
    'Leaving a level does not clear its hearts, completion or saved location',
    () async {
      var now = DateTime.utc(2026, 10, 15);
      final store = MemoryProgressStore();
      final s = GameSessionController(pilot(), store, clock: () => now);
      await s.initialize();
      s.openLevel(0);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      s.execute();
      s.advance(const Duration(minutes: 1));
      expect(s.unlockedIndex, 1);
      s.leave();
      s.openLevel(1);
      s.leave();
      s.openLevel(0);
      expect(s.hearts.available, 2);
      s.setForeground(false);
      now = now.add(const Duration(hours: 9));
      s.setForeground(true);
      expect(s.hearts.available, 2);
      s.leave();
      await s.flush();
      expect(
        jsonDecode(store.value!)['draft']['levelIdentity']['levelId'],
        s.level.identity.levelId,
      );
      s.dispose();
    },
  );

  test('Repeated and shared stops keep all owners and visit multiplicity', () {
    final groups = waypointGroups([
      UnitRoute('A', const [Cell(0, 5), Cell(0, 0), Cell(5, 0), Cell(0, 0)]),
      UnitRoute('B', const [Cell(0, 0)]),
      UnitRoute('C', const [Cell(0, 0)]),
      UnitRoute('D', const [Cell(0, 0)]),
    ]);
    expect(groups[const Cell(0, 0)], {0: 2, 1: 1, 2: 1, 3: 1});
    expect(groups[const Cell(0, 5)], {0: 1});
  });
}

final class _PendingStore implements ProgressStore {
  final reading = Completer<String?>();
  int writes = 0;
  @override
  Future<String?> read() => reading.future;
  @override
  Future<void> write(String value) async {
    writes++;
  }
}
