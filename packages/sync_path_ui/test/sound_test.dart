import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart';

void main() {
  test(
    'Sound events match accepted input, execute and one result only',
    () async {
      final sounds = <GameSound>[];
      final all = pilot();
      final s = GameSessionController(
        LevelPack(all.id, all.revision, [all.levels.first]),
        MemoryProgressStore(),
        onSound: sounds.add,
      );
      addTearDown(s.dispose);
      await s.initialize();
      s.openLevel(0);
      expect(sounds, isEmpty);
      s.toggleUnit('B');
      s.toggleUnit('B');
      expect(sounds, [GameSound.select]);
      s.append(const Cell(0, 2)); // deselected: no accepted input
      expect(sounds.length, 1);
      s.toggleUnit('A');
      s.append(const Cell(0, 2));
      s.undo();
      expect(sounds.sublist(1), [
        GameSound.select,
        GameSound.route,
        GameSound.undo,
      ]);
      s.undo();
      expect(sounds.last, GameSound.undo);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      s.execute();
      expect(sounds.last, GameSound.start);
      s.advance(const Duration(seconds: 30));
      expect(sounds.last, GameSound.clear);
      s.advance(const Duration(seconds: 30));
      expect(sounds.where((sound) => sound == GameSound.clear).length, 1);
    },
  );

  test('Failure sound, persistent mute and lifecycle silence', () async {
    final sounds = <GameSound>[];
    var stopped = 0;
    final store = MemoryProgressStore();
    final all = pilot();
    final pack = LevelPack(all.id, all.revision, [all.levels[8]]);
    final s = GameSessionController(
      pack,
      store,
      onSound: sounds.add,
      onSilence: () => stopped++,
    );
    addTearDown(s.dispose);
    await s.initialize();
    s.openLevel(0);
    enter(s, fromJson(certificates()['levels'][8]['failureExample']['routes']));
    s.execute();
    s.advance(const Duration(seconds: 30));
    expect(sounds.last, GameSound.failure);
    s.toggleSound();
    expect(stopped, 1);
    s.restart();
    final count = sounds.length;
    s.toggleUnit('B');
    expect(sounds.length, count);
    s.setForeground(false);
    expect(stopped, 2);
    s.leave();
    expect(stopped, 3);
    await s.flush();
    final restored = GameSessionController(pack, store);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.soundEnabled, isFalse);
  });
}
