import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';
import 'package:sync_path_tools/src/certificate_verifier.dart';
import 'package:test/test.dart';

const designPath = '../../docs/next_version_27이후/game_design_v1';
LevelPack pack() => const LevelParser()
    .parsePack(File('$designPath/08_pilot_levels.json').readAsStringSync())
    .value!;
void main() {
  test(
    'S01/S03/S04/S05/S06 all domains, 359 outcomes, 47 assignments and diagnostics match independent certificates',
    () {
      final certificates =
          jsonDecode(
                File(
                  '$designPath/09_pilot_certificates.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final report = verifyCertificates(pack(), certificates);
      expect(report['spatialCombinations'], 359);
      expect(report['safeSolutions'], 47);
      final levels = report['levels'] as List;
      expect(levels[6]['stats']['solutionsWithoutReverse'], 0);
      expect(levels[8]['stats']['solutionsWithoutStraightSplit'], 0);
      expect(levels[9]['stats']['solutionsWithoutStraightSplit'], 0);
    },
  );
  test('S02 budget exhaustion is UNKNOWN, never UNSAT or zero exactCount', () {
    final result = const PuzzleSolver().solve(
      pack().levels[8],
      budget: const SolverBudget(maxNodes: 0),
    );
    expect(result.status, SolverStatus.unknown);
    expect(result.exactCount, isNull);
    expect(result.lowerBound, BigInt.zero);
    expect(result.reason, 'nodeBudget');
    expect(result.exhaustive, isFalse);
  });
  test('S02 solution cap means SAT/lowerBound/truncated, not unique/exact', () {
    final result = const PuzzleSolver().solve(
      pack().levels[5],
      budget: const SolverBudget(solutionCap: 1),
    );
    expect(result.status, SolverStatus.sat);
    expect(result.lowerBound, BigInt.one);
    expect(result.exactCount, isNull);
    expect(result.truncated, isTrue);
    expect(result.reason, 'solutionCap');
    expect(
      (const SimulationEngine().simulate(
                pack().levels[5],
                RoutePlan(pack().levels[5].identity, result.witness!),
              )
              as SimulationTrace)
          .outcome,
      SimulationOutcome.success,
    );
  });
  test('S02 domain memory budget reports UNKNOWN', () {
    final result = const PuzzleSolver().solve(
      pack().levels[8],
      budget: const SolverBudget(maxDomainRoutes: 1),
    );
    expect(result.status, SolverStatus.unknown);
    expect(result.reason, 'domainBudget');
    expect(result.exactCount, isNull);
  });
  test(
    'Exhaustive no-solution level is UNSAT despite individual reachability',
    () {
      final level = LevelSpec(
        identity: const LevelIdentity(
          'test-pack',
          'unsat',
          1,
          supportedRuleSet,
        ),
        map: GridMap(
          width: 5,
          height: 5,
          rows: ['#...#', '##.##', '##.##', '##.##', '##.##'],
        ),
        goal: const Cell(2, 4),
        units: const [UnitSpec('A', Cell(1, 0)), UnitSpec('B', Cell(3, 0))],
        maxCommands: 2,
      );
      expect(const LevelValidator().validate(level).isValid, isTrue);
      final result = const PuzzleSolver().solve(level);
      expect(result.status, SolverStatus.unsat);
      expect(result.exhaustive, isTrue);
      expect(result.exactCount, BigInt.zero);
    },
  );
  test(
    'S08 deterministic order, immutable results, cache-free equivalence',
    () {
      final level = pack().levels[6];
      final a = const PuzzleSolver().solve(level);
      final b = const PuzzleSolver().solve(
        level,
        budget: const SolverBudget(maxCacheEntries: 0),
      );
      expect(
        a.assignments.map(assignmentKey).toList(),
        b.assignments.map(assignmentKey).toList(),
      );
      expect(() => a.assignments.clear(), throwsUnsupportedError);
      expect(() => a.assignments.first.clear(), throwsUnsupportedError);
      expect(() => a.domains.clear(), throwsUnsupportedError);
      expect(() => a.domains.values.first.clear(), throwsUnsupportedError);
    },
  );
  test('Budgets are bounded before allocating any search space', () {
    expect(
      () => const PuzzleSolver().solve(
        pack().levels.first,
        budget: const SolverBudget(solutionCap: 0),
      ),
      throwsArgumentError,
    );
    expect(
      () => const PuzzleSolver().solve(
        pack().levels.first,
        budget: const SolverBudget(maxDomainRoutes: 10001),
      ),
      throwsArgumentError,
    );
  });
  test('S01 certificate mismatch fails closed', () {
    final certificates =
        jsonDecode(
              File('$designPath/09_pilot_certificates.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    certificates['levels'][0]['stats']['safeSolutions'] = 99;
    expect(() => verifyCertificates(pack(), certificates), throwsStateError);
  });
}
