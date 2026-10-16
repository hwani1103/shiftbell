import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';

void main() {
  test('Generator/export retain gate positions, duration and safe witness', () {
    final pack = const LevelParser()
        .parsePack(
          File(
            '../../examples/sync_path_lab/assets/pilot_levels.json',
          ).readAsStringSync(),
        )
        .value!;
    final l = pack.levels[30];
    final solved = const PuzzleSolver().solve(l);
    final generated = const LevelGenerator().generate(
      l,
      RoutePlan(l.identity, solved.witness!),
      seed: 801014,
      attempts: 2,
    );
    expect(generated.verified, isTrue);
    expect(generated.level.gates, l.gates);
    final exported = const LevelParser().parsePack(
      jsonEncode({
        'schemaVersion': 1,
        'ruleSetId': constantSpeedRuleSet,
        'packId': pack.id,
        'revision': 1,
        'levels': [levelJson(generated.level)],
      }),
    );
    expect(exported.isValid, isTrue);
    final g = exported.value!.levels.single.gates.single;
    expect(g.door, l.gates.single.door);
    expect(g.trigger, l.gates.single.trigger);
    expect(g.openFor, l.gates.single.openFor);
  });
}
