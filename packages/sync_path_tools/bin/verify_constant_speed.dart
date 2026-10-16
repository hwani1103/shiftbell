import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/src/solver.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';

void main(List<String> args) {
  final pack = const LevelParser()
      .parsePack(File(args[0]).readAsStringSync())
      .value!;
  final reports = <Object>[];
  for (final level in pack.levels) {
    final solver = const PuzzleSolver().solve(level);
    stdout.writeln(
      '${level.identity.levelId} ${solver.status.name} exact=${solver.exactCount} domains=${solver.domains.values.map((r) => r.length).toList()}',
    );
    if (solver.status != SolverStatus.sat || !solver.exhaustive) {
      exitCode = 1;
      continue;
    }
    for (final u in level.units) {
      String key(UnitRoute r) =>
          r.endpoints.map((c) => '${c.x},${c.y}').join(';');
      final direct = directRoutes(level, u).map(key).toSet();
      final computed = solver.domains[u.id]!.map(key).toSet();
      if (direct.length != computed.length || !direct.containsAll(computed))
        throw StateError('Domain mismatch');
    }
    var combos = 0, safe = 0;
    void visit(int i, List<UnitRoute> routes) {
      if (i < level.units.length) {
        for (final r in solver.domains[level.units[i].id]!)
          visit(i + 1, [...routes, r]);
        return;
      }
      combos++;
      final oracle = oracleCollisions(level, routes);
      final trace =
          const SimulationEngine().simulate(
                level,
                RoutePlan(level.identity, routes),
              )
              as SimulationTrace;
      if (oracle.isEmpty != trace.earliestCollisions.isEmpty)
        throw StateError('Outcome mismatch');
      String contacts(List<CollisionEvent> es) => es
          .map((e) => '${e.globalTime}|${e.position.toJson()}|${e.unitIds}')
          .join(';');
      if (contacts(oracle) != contacts(trace.earliestCollisions))
        throw StateError('Contact mismatch ${level.identity.levelId}');
      if (oracle.isEmpty) safe++;
    }

    visit(0, []);
    if (BigInt.from(safe) != solver.exactCount)
      throw StateError('Count mismatch');
    final plan = RoutePlan(level.identity, solver.witness!);
    final trace =
        const SimulationEngine().simulate(level, plan) as SimulationTrace;
    reports.add({
      'level': level.identity.toJson(),
      'domains': {
        for (final e in solver.domains.entries) e.key: e.value.length,
      },
      'combinations': combos,
      'safeSolutions': safe,
      'witness': {
        'levelIdentity': level.identity.toJson(),
        'routeRevision': 0,
        'routes': plan.routes.map((r) => r.toJson()).toList(),
      },
      'trace': trace.toJson(),
    });
  }
  File(args[1]).writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'ruleSetId': constantSpeedRuleSet, 'levels': reports}),
  );
}
