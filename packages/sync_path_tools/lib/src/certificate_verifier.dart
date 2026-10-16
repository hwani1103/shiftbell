import 'dart:convert';
import 'package:sync_path_core/sync_path_core.dart';
import 'independent_oracle.dart';
import 'solver.dart';

String routeKey(UnitRoute route) => jsonEncode(route.toJson());
String assignmentKey(List<UnitRoute> routes) => jsonEncode(
  (routes.toList()..sort((a, b) => a.unitId.compareTo(b.unitId)))
      .map((r) => r.toJson())
      .toList(),
);
void _equal(Object? actual, Object? expected, String context) {
  if (jsonEncode(actual) != jsonEncode(expected))
    throw StateError(
      '$context mismatch: actual=${jsonEncode(actual)} expected=${jsonEncode(expected)}',
    );
}

List<UnitRoute> _routes(dynamic data) => [
  for (final r in data)
    UnitRoute(r['unitId'] as String, [
      for (final e in r['endpoints']) Cell(e[0] as int, e[1] as int),
    ]),
];

/// Fails closed on any domain, safe assignment, trace, quality or version mismatch.
Map<String, Object?> verifyCertificates(
  LevelPack pack,
  Map<String, dynamic> certificates,
) {
  _equal(certificates['certificateVersion'], 1, 'certificate version');
  _equal(certificates['ruleSetId'], supportedRuleSet, 'certificate rule');
  _equal(certificates['packId'], pack.id, 'pack ID');
  _equal(certificates['packRevision'], pack.revision, 'pack revision');
  final certs = certificates['levels'] as List;
  _equal(certs.length, pack.levels.length, 'level count');
  final reports = <Map<String, Object?>>[];
  var totalCombinations = 0, totalSolutions = 0;
  for (final level in pack.levels) {
    final certificate =
        certs.singleWhere((c) => c['id'] == level.identity.levelId)
            as Map<String, dynamic>;
    final solved = const PuzzleSolver().solve(level);
    if (!solved.exhaustive || solved.status != SolverStatus.sat)
      throw StateError('Pilot must be exhaustively SAT');
    final certDomains = certificate['domains'] as List;
    final domains = <String, List<UnitRoute>>{};
    for (final unit in level.units) {
      final certDomain = certDomains.singleWhere((d) => d['unitId'] == unit.id);
      final expected = [
        for (final r in certDomain['routes'])
          UnitRoute(unit.id, [
            for (final e in r['endpoints']) Cell(e[0] as int, e[1] as int),
          ]),
      ];
      final expectedKeys = expected.map(routeKey).toList()..sort();
      _equal(
        solved.domains[unit.id]!.map(routeKey).toList()..sort(),
        expectedKeys,
        '${level.identity.levelId}/${unit.id} graph domain',
      );
      final direct = directRoutes(level, unit);
      _equal(
        direct.map(routeKey).toList()..sort(),
        expectedKeys,
        '${level.identity.levelId}/${unit.id} independent domain',
      );
      domains[unit.id] = expected;
    }
    final expectedAssignments = <String>[];
    for (final indices in certificate['safeAssignments']) {
      expectedAssignments.add(
        assignmentKey([
          for (var i = 0; i < level.units.length; i++)
            domains[level.units[i].id]![indices[i] as int],
        ]),
      );
    }
    expectedAssignments.sort();
    _equal(
      solved.assignments.map(assignmentKey).toList()..sort(),
      expectedAssignments,
      '${level.identity.levelId} CSP safe assignments',
    );
    final independentAssignments = <String>[];
    var combinations = 0;
    void combinationsDfs(List<UnitRoute> selected, int i) {
      if (i < level.units.length) {
        for (final route in domains[level.units[i].id]!) {
          combinationsDfs([...selected, route], i + 1);
        }
        return;
      }
      combinations++;
      final oracle = oracleCollisions(level, selected);
      final trace = const SimulationEngine().simulate(
        level,
        RoutePlan(level.identity, selected),
      );
      if (trace is! SimulationTrace)
        throw StateError('Certified domain was rejected by engine');
      _equal(
        trace.outcome.name,
        oracle.isEmpty ? 'success' : 'collision',
        '${level.identity.levelId} full outcome',
      );
      _equal(
        trace.earliestCollisions.map((e) => e.toJson()).toList(),
        oracle.map((e) => e.toJson()).toList(),
        '${level.identity.levelId} earliest collision',
      );
      if (oracle.isEmpty) independentAssignments.add(assignmentKey(selected));
    }

    combinationsDfs([], 0);
    independentAssignments.sort();
    _equal(
      independentAssignments,
      expectedAssignments,
      '${level.identity.levelId} independent safe assignments',
    );
    final witness = const SimulationEngine().simulate(
      level,
      RoutePlan(level.identity, _routes(certificate['witness'])),
    );
    if (witness is! SimulationTrace ||
        witness.outcome != SimulationOutcome.success)
      throw StateError('Witness rejected');
    if (certificate['failureExample'] != null) {
      final failure = certificate['failureExample'];
      final trace =
          const SimulationEngine().simulate(
                level,
                RoutePlan(level.identity, _routes(failure['routes'])),
              )
              as SimulationTrace;
      _equal(trace.outcome.name, 'collision', 'failure outcome');
      _equal(
        [
          for (final e in trace.earliestCollisions)
            {
              'units': e.unitIds,
              'step': e.step,
              'time': e.localTime.toJson(),
              'position': e.position.toJson(),
            },
        ],
        failure['earliestCollisions'],
        'failure evidence',
      );
    }
    final successes = solved.assignments;
    final mins = [
      for (final u in level.units)
        domains[u.id]!
            .map((r) => r.endpoints.length)
            .reduce((a, b) => a < b ? a : b),
    ];
    bool anyReverse(List<UnitRoute> a) => a.any(
      (r) =>
          hasReverse(level.units.singleWhere((u) => u.id == r.unitId).start, r),
    );
    bool anySplit(List<UnitRoute> a) => a.any(
      (r) => hasStraightSplit(
        level.units.singleWhere((u) => u.id == r.unitId).start,
        r,
      ),
    );
    final withoutReverse = successes.where((a) => !anyReverse(a)).length;
    final withoutSplit = successes.where((a) => !anySplit(a)).length;
    final edges = <List<String>>[];
    for (var i = 0; i < level.units.length; i++) {
      for (var j = i + 1; j < level.units.length; j++) {
        final a = level.units[i], b = level.units[j];
        if (domains[a.id]!.any(
          (ar) => domains[b.id]!.any(
            (br) => oracleCollisions(level, [ar, br]).isNotEmpty,
          ),
        ))
          edges.add([a.id, b.id]);
      }
    }
    final stats = <String, Object>{
      'routeCounts': [for (final u in level.units) domains[u.id]!.length],
      'spatialCombinations': combinations,
      'safeSolutions': successes.length,
      'earlySolutions': successes
          .where((a) => a.any((r) => r.endpoints.length < level.maxCommands))
          .length,
      'minCommands': mins,
      'minTotalCommands': successes
          .map((a) => a.fold<int>(0, (sum, r) => sum + r.endpoints.length))
          .reduce((a, b) => a < b ? a : b),
      'requiresAnyReverse': withoutReverse == 0,
      'requiresAnyStraightSplit': withoutSplit == 0,
      'allShortestCanSucceed': successes.any(
        (a) => level.units.indexed.every(
          (u) =>
              a.singleWhere((r) => r.unitId == u.$2.id).endpoints.length ==
              mins[u.$1],
        ),
      ),
      'interactionEdges': edges,
      'goalApproaches': [
        Cell(level.goal.x + 1, level.goal.y),
        Cell(level.goal.x - 1, level.goal.y),
        Cell(level.goal.x, level.goal.y + 1),
        Cell(level.goal.x, level.goal.y - 1),
      ].where(level.map.isWalkable).length,
      'arrivalRange': [
        for (final u in level.units)
          [
            successes
                .map(
                  (a) =>
                      a.singleWhere((r) => r.unitId == u.id).endpoints.length,
                )
                .reduce((a, b) => a < b ? a : b),
            successes
                .map(
                  (a) =>
                      a.singleWhere((r) => r.unitId == u.id).endpoints.length,
                )
                .reduce((a, b) => a > b ? a : b),
          ],
      ],
      'solutionsWithoutReverse': withoutReverse,
      'solutionsWithoutStraightSplit': withoutSplit,
    };
    for (final entry in stats.entries) {
      _equal(
        entry.value,
        certificate['stats'][entry.key],
        '${level.identity.levelId} ${entry.key}',
      );
    }
    reports.add({
      'levelIdentity': level.identity.toJson(),
      'status': 'PASS',
      'stats': stats,
      'nodesUsed': solved.nodesUsed,
      'exactCount': solved.exactCount.toString(),
    });
    totalCombinations += combinations;
    totalSolutions += successes.length;
  }
  return {
    'verificationVersion': 1,
    'solverVersion': solverVersion,
    'status': 'PASS',
    'methods': [
      'distance-pruned-graph-CSP',
      'direct-ray-DFS-and-exhaustive-rational-contact',
    ],
    'spatialCombinations': totalCombinations,
    'safeSolutions': totalSolutions,
    'levels': reports,
    'scope':
        'Dart host implementation and finite pilot data; UI/device/human play NOT_TESTED',
  };
}
