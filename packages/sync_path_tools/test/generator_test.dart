import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';
import 'package:test/test.dart';

void main() {
  final pack = const LevelParser()
      .parsePack(
        File(
          '../../docs/next_version_27이후/game_design_v1/08_pilot_levels.json',
        ).readAsStringSync(),
      )
      .value!;
  final cert =
      jsonDecode(
            File(
              '../../docs/next_version_27이후/game_design_v1/09_pilot_certificates.json',
            ).readAsStringSync(),
          )
          as Map;
  RoutePlan witness(int i) => RoutePlan(pack.levels[i].identity, [
    for (final r in cert['levels'][i]['witness'])
      UnitRoute(r['unitId'] as String, [
        for (final e in r['endpoints']) Cell(e[0] as int, e[1] as int),
      ]),
  ]);
  test(
    'S07/S08 deterministic seeded mutation preserves witness, revision and export verification',
    () {
      final a = const LevelGenerator().generate(
        pack.levels[1],
        witness(1),
        seed: 20261013,
      );
      final b = const LevelGenerator().generate(
        pack.levels[1],
        witness(1),
        seed: 20261013,
      );
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      expect(a.verified, isTrue);
      expect(a.level.identity.revision, 2);
      expect(a.acceptedMutations, greaterThan(0));
      expect(
        (const SimulationEngine().simulate(a.level, a.witness)
                as SimulationTrace)
            .outcome,
        SimulationOutcome.success,
      );
      expect(a.toJson()['generatorVersion'], generatorVersion);
      expect(a.toJson()['solverVersion'], solverVersion);
    },
  );
  test(
    'S09 preserved every traversed seed cell, even cells between endpoints',
    () {
      final source = pack.levels[5], plan = witness(5);
      final generated = const LevelGenerator().generate(
        source,
        plan,
        seed: 42,
        attempts: 64,
      );
      for (final r in plan.routes) {
        var cell = source.units.singleWhere((u) => u.id == r.unitId).start;
        expect(generated.level.map.isWalkable(cell), isTrue);
        for (final end in r.endpoints) {
          final dx = (end.x - cell.x).sign, dy = (end.y - cell.y).sign;
          while (cell != end) {
            cell = Cell(cell.x + dx, cell.y + dy);
            expect(generated.level.map.isWalkable(cell), isTrue);
          }
        }
      }
      expect(const LevelValidator().validate(generated.level).isValid, isTrue);
    },
  );
  test('UNKNOWN budget never exports verified candidate', () {
    final result = const LevelGenerator().generate(
      pack.levels.first,
      witness(0),
      seed: 1,
      budget: const SolverBudget(maxNodes: 0),
    );
    expect(result.verified, isFalse);
    expect(result.solver.status, SolverStatus.unknown);
    expect(result.toJson()['exactCount'], isNull);
  });
  test(
    'S10 early arrival preserved; invalid seed witness and bounds refused',
    () {
      final early = const LevelGenerator().generate(
        pack.levels[8],
        witness(8),
        seed: 7,
      );
      expect(early.witness.routes.map((r) => r.endpoints.length), [3, 2, 3]);
      expect(early.verified, isTrue);
      expect(
        () => const LevelGenerator().generate(
          pack.levels.first,
          RoutePlan(pack.levels.first.identity, []),
          seed: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => const LevelGenerator().generate(
          pack.levels.first,
          witness(0),
          seed: 0,
        ),
        throwsArgumentError,
      );
    },
  );
}
