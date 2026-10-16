import 'package:sync_path_core/sync_path_core.dart';
import 'solver.dart';

const generatorVersion = 'witness-wall-v1.1.0';

final class GeneratedCandidate {
  final LevelSpec level;
  final RoutePlan witness;
  final SolverResult solver;
  final int seed;
  final int acceptedMutations;
  final int rejectedMutations;
  bool get verified => solver.exhaustive && solver.status == SolverStatus.sat;
  GeneratedCandidate(
    this.level,
    this.witness,
    this.solver,
    this.seed,
    this.acceptedMutations,
    this.rejectedMutations,
  );
  Map<String, Object?> toJson() => {
    'generatorVersion': generatorVersion,
    'solverVersion': solverVersion,
    'ordering': 'x-then-y; Park-Miller seeded shuffle',
    'seed': seed,
    'verified': verified,
    'solverStatus': solver.status.name,
    'exactCount': solver.exactCount?.toString(),
    'lowerBound': solver.lowerBound.toString(),
    'truncated': solver.truncated,
    'nodesUsed': solver.nodesUsed,
    'acceptedMutations': acceptedMutations,
    'rejectedMutations': rejectedMutations,
    'level': levelJson(level),
    'witness': witness.routes.map((r) => r.toJson()).toList(),
    'quality': {
      'walkableCells': level.map.walkable.length,
      'routeCounts': {
        for (final e in solver.domains.entries) e.key: e.value.length,
      },
      'earlySolutions': solver.assignments
          .where((a) => a.any((r) => r.endpoints.length < level.maxCommands))
          .length,
      'humanPlaytest': 'NOT_TESTED',
    },
  };
}

Map<String, Object> levelJson(LevelSpec level) => {
  'id': level.identity.levelId,
  'revision': level.identity.revision,
  'width': level.map.width,
  'height': level.map.height,
  'rows': level.map.rows,
  'goal': level.goal.toJson(),
  'units': [
    for (final u in level.units) {'id': u.id, 'start': u.start.toJson()},
  ],
  'maxCommands': level.maxCommands,
  'requiredMechanics': level.requiredMechanics,
  if (level.portals.isNotEmpty)
    'portals': [
      for (final p in level.portals)
        {'id': p.id, 'entry': p.entry.toJson(), 'exit': p.exit.toJson()},
    ],
  if (level.gates.isNotEmpty)
    'gates': [
      for (final g in level.gates)
        {
          'id': g.id,
          'trigger': g.trigger.toJson(),
          'door': g.door.toJson(),
          'openFor': g.openFor,
        },
    ],
};

/// Small local authoring tool: preserve every cell of a safe seed witness,
/// mutate other walls, then reject disconnected/UNKNOWN/unverified candidates.
final class LevelGenerator {
  const LevelGenerator();
  GeneratedCandidate generate(
    LevelSpec source,
    RoutePlan witness, {
    required int seed,
    int attempts = 8,
    SolverBudget budget = const SolverBudget(),
  }) {
    if (seed < 1 || seed > 2147483646 || attempts < 0 || attempts > 64)
      throw ArgumentError('Bounded seed/attempts required');
    final initial = const SimulationEngine().simulate(source, witness);
    if (initial is! SimulationTrace ||
        initial.outcome != SimulationOutcome.success)
      throw ArgumentError('Seed witness must be valid and safe');
    final protected = <Cell>{
      source.goal,
      for (final p in source.portals) ...[p.entry, p.exit],
      for (final g in source.gates) ...[g.trigger, g.door],
    };
    for (final route in witness.routes) {
      var current = source.units.singleWhere((u) => u.id == route.unitId).start;
      protected.add(current);
      for (final end in route.endpoints) {
        final dx = (end.x - current.x).sign, dy = (end.y - current.y).sign;
        while (current != end) {
          current = Cell(current.x + dx, current.y + dy);
          protected.add(current);
        }
        current = source.afterEndpoint(end);
      }
    }
    final identity = LevelIdentity(
      source.identity.packId,
      source.identity.levelId,
      source.identity.revision + 1,
      source.identity.ruleSetId,
    );
    LevelSpec rebuild(List<String> rows) => LevelSpec(
      identity: identity,
      map: GridMap(
        width: source.map.width,
        height: source.map.height,
        rows: rows,
      ),
      goal: source.goal,
      gates: source.gates,
      portals: source.portals,
      units: source.units,
      maxCommands: source.maxCommands,
      requiredMechanics: source.requiredMechanics,
    );
    var level = rebuild(source.map.rows);
    var plan = RoutePlan(identity, witness.routes, revision: witness.revision);
    var solved = const PuzzleSolver().solve(level, budget: budget);
    if (!solved.exhaustive || solved.status != SolverStatus.sat)
      return GeneratedCandidate(level, plan, solved, seed, 0, 0);
    final cells = [
      for (var x = 0; x < source.map.width; x++)
        for (var y = 0; y < source.map.height; y++)
          if (!protected.contains(Cell(x, y))) Cell(x, y),
    ];
    var state = seed;
    for (var i = cells.length - 1; i > 0; i--) {
      state = (state * 16807) % 2147483647;
      final j = state % (i + 1);
      final temp = cells[i];
      cells[i] = cells[j];
      cells[j] = temp;
    }
    var accepted = 0, rejected = 0;
    for (final cell in cells.take(attempts)) {
      final rows = level.map.rows.toList();
      final row = rows[cell.y].split('');
      row[cell.x] = row[cell.x] == '.' ? '#' : '.';
      rows[cell.y] = row.join();
      final candidate = rebuild(rows);
      if (!const LevelValidator().validate(candidate).isValid) {
        rejected++;
        continue;
      }
      final trace = const SimulationEngine().simulate(candidate, plan);
      if (trace is! SimulationTrace ||
          trace.outcome != SimulationOutcome.success) {
        rejected++;
        continue;
      }
      final candidateSolver = const PuzzleSolver().solve(
        candidate,
        budget: budget,
      );
      if (!candidateSolver.exhaustive ||
          candidateSolver.status != SolverStatus.sat) {
        rejected++;
        continue;
      }
      level = candidate;
      solved = candidateSolver;
      accepted++;
    }
    // Recheck the exported witness independently of CSP before marking verified.
    plan = RoutePlan(
      level.identity,
      witness.routes,
      revision: witness.revision,
    );
    final finalTrace = const SimulationEngine().simulate(level, plan);
    if (finalTrace is! SimulationTrace ||
        finalTrace.outcome != SimulationOutcome.success)
      throw StateError('Generated witness failed final validation');
    return GeneratedCandidate(level, plan, solved, seed, accepted, rejected);
  }
}
