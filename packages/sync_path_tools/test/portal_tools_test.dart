import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';

void main() {
  LevelSpec level() => const LevelParser()
      .parsePack(
        File(
          '../../examples/sync_path_lab/assets/pilot_levels.json',
        ).readAsStringSync(),
      )
      .value!
      .levels[50];
  test(
    'Portal solver domain equals unpruned enumeration and independent exact oracle',
    () {
      final l = level();
      final solved = const PuzzleSolver().solve(l);
      expect(solved.exhaustive, isTrue);
      expect(solved.exactCount, BigInt.from(9));
      for (final u in l.units) {
        expect(solved.domains[u.id]!.length, directRoutes(l, u).length);
      }
      for (final rs in solved.assignments) {
        expect(oracleCollisions(l, rs), isEmpty);
      }
    },
  );
  test(
    'Portal export round trips and generator preserves both portal cells',
    () {
      final l = level();
      final solved = const PuzzleSolver().solve(l);
      final generated = const LevelGenerator().generate(
        l,
        RoutePlan(l.identity, solved.witness!),
        seed: 801015,
        attempts: 8,
      );
      expect(generated.verified, isTrue);
      expect(generated.level.portals.single.entry, l.portals.single.entry);
      expect(generated.level.portals.single.exit, l.portals.single.exit);
      final parsed = const LevelParser().parseLevel(
        jsonEncode({
          'schemaVersion': 1,
          'ruleSetId': constantSpeedRuleSet,
          ...levelJson(generated.level),
        }),
        packId: l.identity.packId,
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.value!.map.isWalkable(l.portals.single.exit), isTrue);
    },
  );
}
