import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/src/solver.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';

// Independent equivalence key: every visited cell at integer logical time.
// Straight command splitting cannot create a different trajectory.
String trajectory(Cell start, UnitRoute route) {
  final cells = [start];
  var c = start;
  for (final end in route.endpoints) {
    final dx = (end.x - c.x).sign, dy = (end.y - c.y).sign;
    while (c != end) {
      c = Cell(c.x + dx, c.y + dy);
      cells.add(c);
    }
  }
  return cells.map((c) => '${c.x},${c.y}').join(';');
}

String contacts(List<CollisionEvent> e) => e
    .map((c) => '${c.globalTime}|${c.position.toJson()}|${c.unitIds}')
    .join(';');
void main(List<String> args) {
  final parsed = const LevelParser().parsePack(
    File(args[0]).readAsStringSync(),
  );
  if (!parsed.isValid) throw StateError(parsed.issues.toString());
  final pack = parsed.value!, reports = <Object>[];
  final design = args.length > 2
      ? jsonDecode(File(args[2]).readAsStringSync()) as Map<String, dynamic>
      : null;
  var totalPairs = 0, totalAssignments = 0;
  for (final l in pack.levels) {
    final solved = const PuzzleSolver().solve(l);
    if (!solved.exhaustive || solved.status != SolverStatus.sat)
      throw StateError('${l.identity.levelId}: incomplete/unsolved');
    final domains = <List<UnitRoute>>[];
    for (final u in l.units) {
      String key(UnitRoute r) => jsonEncode(r.toJson());
      final direct = directRoutes(l, u).map(key).toSet(),
          actual = solved.domains[u.id]!.map(key).toSet();
      if (direct.length != actual.length || !direct.containsAll(actual))
        throw StateError('Domain mismatch');
      final unique = <String, UnitRoute>{};
      for (final r in solved.domains[u.id]!) {
        final k = trajectory(u.start, r);
        if (!unique.containsKey(k) ||
            r.endpoints.length < unique[k]!.endpoints.length)
          unique[k] = r;
      }
      domains.add(unique.values.toList());
    }
    String planKey(List<UnitRoute> routes) => [
      for (var i = 0; i < routes.length; i++)
        trajectory(l.units[i].start, routes[i]),
    ].join('|');
    final matrices = <String, List<List<bool>>>{};
    var pairs = 0;
    for (var i = 0; i < l.units.length; i++)
      for (var j = i + 1; j < l.units.length; j++) {
        final pairLevel = LevelSpec(
          identity: l.identity,
          map: l.map,
          goal: l.goal,
          units: [l.units[i], l.units[j]],
          maxCommands: l.maxCommands,
        );
        final matrix = <List<bool>>[];
        for (final a in domains[i]) {
          final row = <bool>[];
          for (final b in domains[j]) {
            final oracle = oracleCollisions(pairLevel, [a, b]);
            final result =
                const SimulationEngine().simulate(
                      pairLevel,
                      RoutePlan(l.identity, [a, b]),
                    )
                    as SimulationTrace;
            if (contacts(oracle) != contacts(result.earliestCollisions))
              throw StateError('Pair mismatch ${l.identity.levelId}');
            row.add(oracle.isEmpty);
            pairs++;
          }
          matrix.add(row);
        }
        matrices['$i:$j'] = matrix;
      }
    final independent = <String>{};
    List<UnitRoute>? witness;
    void visit(List<int> chosen) {
      final i = chosen.length;
      if (i == domains.length) {
        final routes = [for (var k = 0; k < i; k++) domains[k][chosen[k]]];
        final result =
            const SimulationEngine().simulate(l, RoutePlan(l.identity, routes))
                as SimulationTrace;
        if (result.outcome != SimulationOutcome.success ||
            oracleCollisions(l, routes).isNotEmpty)
          throw StateError('Full solution mismatch');
        independent.add(planKey(routes));
        witness ??= routes;
        return;
      }
      for (var r = 0; r < domains[i].length; r++) {
        var safe = true;
        for (var k = 0; k < i; k++)
          if (!matrices['$k:$i']![chosen[k]][r]) {
            safe = false;
            break;
          }
        if (safe) visit([...chosen, r]);
      }
    }

    visit([]);
    final actual = solved.assignments.map(planKey).toSet();
    if (actual.length != independent.length || !actual.containsAll(independent))
      throw StateError('Independent CSP mismatch');
    final rng = Random(271030);
    Map<String, Object>? failure;
    for (var n = 0; n < 40; n++) {
      final routes = [for (final d in domains) d[rng.nextInt(d.length)]];
      final trace =
          const SimulationEngine().simulate(l, RoutePlan(l.identity, routes))
              as SimulationTrace;
      if (contacts(trace.earliestCollisions) !=
          contacts(oracleCollisions(l, routes)))
        throw StateError('Full failure mismatch');
      if (trace.outcome == SimulationOutcome.collision)
        failure ??= {
          'routes': routes.map((r) => r.toJson()).toList(),
          'trace': trace.toJson(),
        };
    }
    final plan = RoutePlan(l.identity, witness!);
    if (design != null) {
      final entry = (design['levels'] as List).singleWhere(
        (e) => e['id'] == l.identity.levelId,
      );
      if (entry['witness'] != null) {
        final hintRoutes = [
          for (final r in entry['witness'] as List)
            UnitRoute(r['unitId'] as String, [
              for (final c in r['endpoints'] as List)
                Cell(c[0] as int, c[1] as int),
            ]),
        ];
        final hinted = const SimulationEngine().simulate(
          l,
          RoutePlan(l.identity, hintRoutes),
        );
        if (hinted is! SimulationTrace ||
            hinted.outcome != SimulationOutcome.success ||
            oracleCollisions(l, hintRoutes).isNotEmpty)
          throw StateError('Hint witness invalid ${l.identity.levelId}');
      }
    }
    final trace = const SimulationEngine().simulate(l, plan) as SimulationTrace;
    reports.add({
      'level': l.identity.toJson(),
      'rawDomains': {
        for (final e in solved.domains.entries) e.key: e.value.length,
      },
      'temporalDomains': [for (final d in domains) d.length],
      'pairComparisons': pairs,
      'rawSolutionCount': solved.exactCount.toString(),
      'distinctSolutionCount': independent.length,
      'independentAssignmentSetEqual': true,
      'witness': {
        'levelIdentity': l.identity.toJson(),
        'routeRevision': 0,
        'routes': witness!.map((r) => r.toJson()).toList(),
      },
      'trace': trace.toJson(),
      if (failure != null) 'failureExample': failure,
    });
    totalPairs += pairs;
    totalAssignments += independent.length;
    stdout.writeln(
      '${l.identity.levelId} PASS ${l.units.length} units pairs=$pairs solutions=${independent.length}',
    );
  }
  File(args[1]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'packId': pack.id,
      'ruleSetId': constantSpeedRuleSet,
      'verification':
          'Every raw domain, every distinct pair trajectory, exact independent joint solution set, every safe assignment and 40 full plans per level',
      'pairComparisons': totalPairs,
      'distinctSafeAssignments': totalAssignments,
      'levels': reports,
    }),
  );
}
