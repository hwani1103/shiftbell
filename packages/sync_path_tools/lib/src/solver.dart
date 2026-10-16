import 'package:sync_path_core/sync_path_core.dart';

const solverVersion = 'sync-path-csp-v2.2.0';

enum SolverStatus { sat, unsat, unknown }

final class SolverBudget {
  final int maxNodes;
  final int maxDomainRoutes;
  final int solutionCap;
  final int maxCacheEntries;
  const SolverBudget({
    this.maxNodes = 1000000,
    this.maxDomainRoutes = 10000,
    this.solutionCap = 10000,
    this.maxCacheEntries = 10000,
  });
  void validate() {
    if (maxNodes < 0 ||
        maxDomainRoutes < 1 ||
        maxDomainRoutes > 10000 ||
        solutionCap < 1 ||
        solutionCap > 10000 ||
        maxCacheEntries < 0 ||
        maxCacheEntries > 100000) {
      throw ArgumentError('Invalid bounded solver budget');
    }
  }
}

final class SolverResult {
  final SolverStatus status;
  final bool exhaustive;
  final String? reason;
  final int nodesUsed;
  final BigInt lowerBound;
  BigInt? get exactCount => exhaustive ? lowerBound : null;
  bool get truncated => !exhaustive;
  final Map<String, List<UnitRoute>> domains;
  final List<List<UnitRoute>> assignments;
  List<UnitRoute>? get witness =>
      assignments.isEmpty ? null : assignments.first;
  SolverResult({
    required this.status,
    required this.exhaustive,
    required this.reason,
    required this.nodesUsed,
    required this.lowerBound,
    required Map<String, List<UnitRoute>> domains,
    required List<List<UnitRoute>> assignments,
  }) : domains = Map.unmodifiable({
         for (final e in domains.entries)
           e.key: List<UnitRoute>.unmodifiable(e.value),
       }),
       assignments = List.unmodifiable(
         assignments.map((a) => List<UnitRoute>.unmodifiable(a)),
       );
}

final class PuzzleSolver {
  const PuzzleSolver();
  SolverResult solve(
    LevelSpec level, {
    SolverBudget budget = const SolverBudget(),
  }) {
    budget.validate();
    final validation = const LevelValidator().validate(level);
    if (!validation.isValid) throw ArgumentError(validation.issues.join(', '));
    final run = _Search(level, budget);
    return run.solve();
  }
}

/// All caches live within one immutable level search, never just a level ID.
final class _Search {
  final LevelSpec level;
  final SolverBudget budget;
  int nodes = 0;
  String? stopped;
  final domains = <String, List<UnitRoute>>{};
  final assignments = <List<UnitRoute>>[];
  final compatibility = <String, bool>{};
  late final units = level.units.toList()..sort((a, b) => a.id.compareTo(b.id));
  late final distances = minimumCommandsToGoal(level);
  late final graph = {
    for (final c in level.map.walkable) c: legalDestinations(level, c),
  };
  _Search(this.level, this.budget);
  void charge() {
    if (nodes >= budget.maxNodes) throw const _Limit('nodeBudget');
    nodes++;
  }

  SolverResult solve() {
    try {
      for (final unit in units) {
        final routes = <UnitRoute>[];
        domains[unit.id] = routes;
        void enumerate(Cell current, List<Cell> prefix) {
          charge();
          if (current == level.goal) {
            if (routes.length >= budget.maxDomainRoutes)
              throw const _Limit('domainBudget');
            routes.add(UnitRoute(unit.id, prefix));
            return;
          }
          if ((distances[current] ?? 999) > level.maxCommands - prefix.length)
            return;
          for (final next in graph[current]!) {
            enumerate(level.afterEndpoint(next), [...prefix, next]);
          }
        }

        enumerate(unit.start, []);
      }
      search({}, {
        for (final entry in domains.entries)
          entry.key: List.generate(entry.value.length, (i) => i),
      });
    } on _Limit catch (limit) {
      stopped = limit.reason;
    }
    return SolverResult(
      status: assignments.isNotEmpty
          ? SolverStatus.sat
          : stopped == null
          ? SolverStatus.unsat
          : SolverStatus.unknown,
      exhaustive: stopped == null,
      reason: stopped,
      nodesUsed: nodes,
      lowerBound: BigInt.from(assignments.length),
      domains: domains,
      assignments: assignments,
    );
  }

  bool compatible(String a, int ai, String b, int bi) {
    final key = a.compareTo(b) < 0 ? '$a:$ai|$b:$bi' : '$b:$bi|$a:$ai';
    final cached = compatibility[key];
    if (cached != null) return cached;
    charge();
    final ar = domains[a]![ai];
    final br = domains[b]![bi];
    var ac = units.firstWhere((u) => u.id == a).start;
    var bc = units.firstWhere((u) => u.id == b).start;
    var safe = true;
    if (level.identity.ruleSetId == constantSpeedRuleSet) {
      List<LinearPiece> timed(UnitRoute r, Cell start) {
        var cell = start, time = 0;
        final pieces = <LinearPiece>[];
        for (var i = 0; i < r.endpoints.length; i++) {
          final end = r.endpoints[i];
          final distance = (end.x - cell.x).abs() + (end.y - cell.y).abs();
          pieces.add(
            LinearPiece(
              r.unitId,
              i + 1,
              cell,
              end,
              startTimeUnits: time,
              endTimeUnits: time + distance,
            ),
          );
          cell = level.afterEndpoint(end);
          time += distance;
        }
        return pieces;
      }

      for (final ap in timed(ar, ac)) {
        for (final bp in timed(br, bc)) {
          final contact = const TemporalCollisionResolver().resolve(ap, bp);
          if (contact is! NoContact &&
              !temporalGoalContact(contact, ap, bp, level.goal)) {
            safe = false;
            break;
          }
        }
        if (!safe) break;
      }
      if (compatibility.length < budget.maxCacheEntries)
        compatibility[key] = safe;
      return safe;
    }
    for (var i = 0; i < ar.endpoints.length && i < br.endpoints.length; i++) {
      final ae = ar.endpoints[i];
      final be = br.endpoints[i];
      final contact = const CollisionResolver().resolve(
        LinearPiece(a, i + 1, ac, ae),
        LinearPiece(b, i + 1, bc, be),
      );
      if (contact is! NoContact &&
          !const CollisionPolicy().allows(contact, level.goal)) {
        safe = false;
        break;
      }
      ac = ae;
      bc = be;
    }
    if (compatibility.length < budget.maxCacheEntries)
      compatibility[key] = safe;
    return safe;
  }

  void search(Map<String, int> chosen, Map<String, List<int>> remaining) {
    charge();
    if (remaining.isEmpty) {
      final solution = [
        for (final unit in units) domains[unit.id]![chosen[unit.id]!],
      ];
      final trace = const SimulationEngine().simulate(
        level,
        RoutePlan(level.identity, solution),
      );
      if (trace is! SimulationTrace ||
          trace.outcome != SimulationOutcome.success) {
        if (trace is SimulationTrace &&
            trace.outcome == SimulationOutcome.closedGate)
          return;
        throw StateError('CSP witness failed full engine verification');
      }
      assignments.add(solution);
      if (assignments.length >= budget.solutionCap)
        throw const _Limit('solutionCap');
      return;
    }
    final order = remaining.keys.toList()
      ..sort((a, b) {
        final diff = remaining[a]!.length.compareTo(remaining[b]!.length);
        return diff == 0 ? a.compareTo(b) : diff;
      });
    final id = order.first;
    for (final candidate in remaining[id]!) {
      final next = <String, List<int>>{};
      var viable = true;
      for (final other in order.skip(1)) {
        final candidates = [
          for (final oi in remaining[other]!)
            if (compatible(id, candidate, other, oi)) oi,
        ];
        if (candidates.isEmpty) {
          viable = false;
          break;
        }
        next[other] = candidates;
      }
      if (viable) search({...chosen, id: candidate}, next);
    }
  }
}

final class _Limit implements Exception {
  final String reason;
  const _Limit(this.reason);
}

/// Content diagnostics only; neither trick is forbidden by the base solver.
bool hasStraightSplit(Cell start, UnitRoute route) {
  final dirs = _directions(start, route);
  for (var i = 1; i < dirs.length; i++) {
    if (dirs[i] == dirs[i - 1]) return true;
  }
  return false;
}

bool hasReverse(Cell start, UnitRoute route) {
  final dirs = _directions(start, route);
  for (var i = 1; i < dirs.length; i++) {
    if (dirs[i].x == -dirs[i - 1].x && dirs[i].y == -dirs[i - 1].y) return true;
  }
  return false;
}

List<Cell> _directions(Cell start, UnitRoute route) {
  final dirs = <Cell>[];
  var current = start;
  for (final end in route.endpoints) {
    dirs.add(Cell((end.x - current.x).sign, (end.y - current.y).sign));
    current = end;
  }
  return dirs;
}
