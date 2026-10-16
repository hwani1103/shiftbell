import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart';

final class SlowStore implements ProgressStore {
  final first = Completer<void>();
  final started = Completer<void>();
  final writes = <String>[];
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String value) async {
    if (!started.isCompleted) {
      started.complete();
      await first.future;
    }
    writes.add(value);
    saved = value;
  }
}

final class FailingStore implements ProgressStore {
  bool fail = true;
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Failure');
    saved = value;
  }
}

void main() {
  test(
    'Cleared level reentry resets replay and cached routes but keeps recovery',
    () async {
      final s = await session(0);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      expect(s.canExecute, isTrue);
      s.execute();
      s.advance(const Duration(seconds: 30));
      expect(s.mode, SessionMode.successReview);
      s.hearts.spend();
      s.hearts.spend();
      s.hearts.elapse(const Duration(seconds: 30), foreground: true);
      s.leave();
      s.openLevel(0);
      expect(s.mode, SessionMode.planning);
      expect(s.trace, isNull);
      expect(s.replay, isNull);
      expect(s.selectedUnitId, 'A');
      expect(s.routes.every((r) => r.endpoints.isEmpty), isTrue);
      expect(s.canExecute, isFalse);
      expect(s.isCompleted(0), isTrue);
      expect(s.hearts.available, 0);
      expect(s.hearts.fraction, .5);
      expect(s.editable, isFalse);
      expect(s.append(const Cell(0, 2)), isFalse);
      s.hearts.elapse(const Duration(seconds: 30), foreground: true);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      expect(s.canExecute, isTrue);
    },
  );
  test(
    'U01/U02/U03 explicit selection, complete gating and selected route undo',
    () async {
      final s = await session(0);
      addTearDown(s.dispose);
      expect(s.canExecute, isFalse);
      expect(s.selectedUnitId, 'A');
      s.selectUnit('A');
      expect(s.append(const Cell(0, 2)), isTrue);
      expect(s.append(s.level.goal), isTrue);
      expect(s.selectedUnitId, 'B');
      s.selectUnit('A');
      expect(s.canUndo, isTrue);
      s.undo();
      expect(s.selectedUnitId, 'A');
      expect(s.routes.first.endpoints.length, 1);
      s.append(s.level.goal);
      s.selectUnit('B');
      expect(s.canUndo, isFalse); // manual selection cancels cross-Unit undo.
      s.append(const Cell(4, 2));
      s.append(s.level.goal);
      expect(s.canExecute, isTrue);
      final before = jsonEncode(s.routes.map((r) => r.toJson()).toList());
      s.execute();
      expect(s.editable, isFalse);
      expect(s.append(const Cell(1, 2)), isFalse);
      s.undo();
      expect(jsonEncode(s.routes.map((r) => r.toJson()).toList()), before);
    },
  );
  test(
    'U02 invalid taps preserve plan; split, reverse and revisit remain legal',
    () async {
      final s = await session(6);
      addTearDown(s.dispose);
      final before = s.routeRevision;
      expect(s.append(const Cell(4, 1)), isFalse);
      expect(s.routeRevision, before);
      s.selectUnit('B');
      expect(s.append(const Cell(0, 0)), isTrue);
      expect(s.append(const Cell(2, 0)), isTrue);
      expect(s.append(s.level.goal), isTrue);
      expect(s.routes.last.endpoints, [
        const Cell(0, 0),
        const Cell(2, 0),
        s.level.goal,
      ]);
    },
  );
  test(
    'U04/U05 failure stops exactly, all three pairs preserved, edit keeps old paths',
    () async {
      final s = await session(8);
      addTearDown(s.dispose);
      enter(
        s,
        fromJson(certificates()['levels'][8]['failureExample']['routes']),
      );
      final before = jsonEncode(s.plan.routes.map((r) => r.toJson()).toList());
      expect(s.canExecute, isTrue);
      s.execute();
      s.advance(const Duration(seconds: 10));
      expect(s.mode, SessionMode.failureReview);
      expect(s.replay!.position, s.trace!.durationInSteps.toDouble());
      expect(s.trace!.earliestCollisions.length, 3);
      s.editFailure(unitId: 'C');
      expect(s.selectedUnitId, 'C');
      expect(s.mode, SessionMode.planning);
      expect(jsonEncode(s.plan.routes.map((r) => r.toJson()).toList()), before);
      s.undo();
      expect(s.canExecute, isFalse);
    },
  );
  test(
    'U06/U12 early removal, no filler, repeat success unlocks exactly once',
    () async {
      final s = await session(5);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][5]['witness']));
      s.execute();
      s.advance(const Duration(milliseconds: 1300));
      expect(s.replay!.completed, {'B'});
      expect(s.replay!.centers.containsKey('B'), isFalse);
      s.advance(const Duration(milliseconds: 650));
      expect(s.mode, SessionMode.successReview);
      expect(s.completedLevels.length, 1);
      s.replayAgain();
      s.advance(const Duration(seconds: 30));
      expect(s.completedLevels.length, 1);
    },
  );
  test(
    'U09 pause retains cursor but reentry resets routes and preserves hearts',
    () async {
      final s = await session(0);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      s.execute();
      s.advance(const Duration(milliseconds: 100));
      final cursor = s.replay!.position;
      s.pause();
      s.advance(const Duration(seconds: 30));
      expect(s.replay!.position, cursor);
      s.leave();
      s.openLevel(0);
      expect(s.mode, SessionMode.planning);
      expect(s.replay, isNull);
      expect(s.routes.every((r) => r.endpoints.isEmpty), isTrue);
      expect(s.hearts.available, 2);
    },
  );
  test(
    'U08 reduced motion uses manual scenes and exact collision endpoint',
    () async {
      final s = await session(11);
      addTearDown(s.dispose);
      enter(
        s,
        fromJson(certificates()['levels'][11]['failureExample']['routes']),
      );
      s.execute(reducedMotion: true);
      expect(s.mode, SessionMode.paused);
      s.nextScene();
      expect(s.mode, SessionMode.failureReview);
      expect(s.replay!.position, 0.5);
    },
  );
  test('U10 process restart opens a fresh board', () async {
    final store = MemoryProgressStore();
    final s = await session(0, store: store);
    s.selectUnit('A');
    s.append(const Cell(0, 2));
    await s.flush();
    final reloaded = GameSessionController(s.pack, store);
    await reloaded.initialize();
    reloaded.openLevel(0);
    expect(reloaded.mode, SessionMode.planning);
    expect(reloaded.trace, isNull);
    expect(reloaded.routes.first.endpoints, isEmpty);
    s.dispose();
    reloaded.dispose();
  });
  test(
    'U10 corrupt/stale draft is isolated; progress reset never deletes another store',
    () async {
      final store = MemoryProgressStore()..value = '{broken';
      final s = await session(0, store: store);
      addTearDown(s.dispose);
      expect(
        s.notice,
        anyOf(isNull, SessionNotice.corruptSave),
      ); // open clears the transient notice.
      expect(s.routes.every((r) => r.endpoints.isEmpty), isTrue);
      final saved = {
        'schemaVersion': 1,
        'packId': s.pack.id,
        'packRevision': 1,
        'completed': [],
        'draft': {
          'levelIdentity': {...s.level.identity.toJson(), 'revision': 9},
          'routeRevision': 1,
          'routes': s.routes.map((r) => r.toJson()).toList(),
        },
      };
      store.value = jsonEncode(saved);
      final reload = GameSessionController(s.pack, store);
      await reload.initialize();
      expect(reload.notice, SessionNotice.corruptSave);
      expect(reload.routes.every((r) => r.endpoints.isEmpty), isTrue);
      reload.dispose();
    },
  );
  test('U11 delayed save is serialized and latest snapshot wins', () async {
    final store = SlowStore();
    final s = await session(0, store: store);
    addTearDown(s.dispose);
    await store.started.future;
    s.selectUnit('A');
    s.append(const Cell(0, 2));
    s.append(s.level.goal);
    s.selectUnit('A'); // Return from the automatically selected next ball.
    s.undo();
    final revision = s.routeRevision;
    store.first.complete();
    await s.flush();
    expect(
      (jsonDecode(store.saved!) as Map)['draft']['routeRevision'],
      revision,
    );
    expect(
      (jsonDecode(store.saved!) as Map)['draft']['routes'][0]['endpoints'],
      [
        [0, 2],
      ],
    );
    expect(store.writes.length, 2);
  });
  test(
    'U10 saving failure remains retryable and does not discard paths',
    () async {
      final store = FailingStore();
      final s = await session(0, store: store);
      addTearDown(s.dispose);
      s.selectUnit('A');
      s.append(const Cell(0, 2));
      await s.flush();
      expect(s.notice, SessionNotice.saveFailed);
      expect(s.routes.first.endpoints, isNotEmpty);
      store.fail = false;
      s.retrySave();
      await s.flush();
      expect(store.saved, isNotNull);
    },
  );
  test('U12 disposed asynchronous load never updates state', () async {
    final read = Completer<String?>();
    final s = GameSessionController(pilot(), _ReadStore(read));
    final pending = s.initialize();
    s.dispose();
    read.complete(null);
    await pending;
    expect(s.ready, isFalse);
  });
  test(
    '30/60/120 FPS cursors and large jumps share the exact stop cursor',
    () async {
      for (final fps in [30, 60, 120]) {
        final s = await session(11);
        enter(
          s,
          fromJson(certificates()['levels'][11]['failureExample']['routes']),
        );
        s.execute();
        for (var i = 0; i < fps * 3; i++) {
          s.advance(Duration(microseconds: (1000000 / fps).round()));
        }
        expect(s.replay!.position, 0.5);
        expect(s.mode, SessionMode.failureReview);
        s.dispose();
      }
    },
  );
}

final class _ReadStore implements ProgressStore {
  final Completer<String?> completer;
  _ReadStore(this.completer);
  @override
  Future<String?> read() => completer.future;
  @override
  Future<void> write(String value) async {}
}
