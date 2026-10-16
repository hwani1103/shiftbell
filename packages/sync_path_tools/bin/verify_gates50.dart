import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';

List<Cell> expand(LevelSpec l, UnitRoute r) {
  final path = [l.units.singleWhere((u) => u.id == r.unitId).start];
  for (final end in r.endpoints) {
    final dx = (end.x - path.last.x).sign, dy = (end.y - path.last.y).sign;
    while (path.last != end) {
      path.add(Cell(path.last.x + dx, path.last.y + dy));
    }
  }
  return path;
}

// Independent declarative gate oracle: each door visit needs some preceding
// trigger visit in its half-open interval, from any unit.
int? gateFailure(LevelSpec l, List<UnitRoute> routes, [String? ignore]) {
  final paths = [for (final r in routes) expand(l, r)];
  int? first;
  for (final g in l.gates.where((g) => g.id != ignore)) {
    final triggers = [
      for (final p in paths)
        for (var t = 1; t < p.length; t++)
          if (p[t] == g.trigger) t,
    ];
    for (final p in paths) {
      for (var t = 1; t < p.length; t++) {
        if (p[t] == g.door &&
            !triggers.any((a) => a <= t && t < a + g.openFor)) {
          if (first == null || t < first) first = t;
        }
      }
    }
  }
  return first;
}

void main(List<String> args) {
  final pack = const LevelParser().parsePack(File(args[0]).readAsStringSync());
  if (!pack.isValid) throw StateError(pack.issues.toString());
  final design = jsonDecode(File(args[1]).readAsStringSync());
  final reports = <Object>[];
  for (final l in pack.value!.levels.skip(30).take(20)) {
    final solved = const PuzzleSolver().solve(l);
    if (!solved.exhaustive || solved.status != SolverStatus.sat)
      throw StateError('${l.identity.levelId} ${solved.reason}');
    final domains = <List<UnitRoute>>[];
    final weights = <Map<String, int>>[];
    String key(UnitRoute r) =>
        jsonEncode(expand(l, r).map((e) => e.toJson()).toList());
    for (final u in l.units) {
      final direct = directRoutes(l, u);
      final actual = solved.domains[u.id]!;
      if (direct
              .map((r) => jsonEncode(r.toJson()))
              .toSet()
              .difference(actual.map((r) => jsonEncode(r.toJson())).toSet())
              .isNotEmpty ||
          direct.length != actual.length)
        throw StateError('Domain mismatch');
      final grouped = <String, UnitRoute>{};
      final counts = <String, int>{};
      for (final r in direct) {
        grouped[key(r)] = r;
        counts.update(key(r), (v) => v + 1, ifAbsent: () => 1);
      }
      domains.add(grouped.values.toList());
      weights.add(counts);
    }
    var safe = 0, raw = 0, checks = 0;
    final essential = {for (final g in l.gates) g.id: 0};
    List<UnitRoute>? witness, failed;
    final pairs = <String, bool>{};
    void search(List<UnitRoute> prefix, List<int> indices) {
      final i = prefix.length;
      if (i == domains.length) {
        checks++;
        final failure = gateFailure(l, prefix);
        if (failure != null) {
          for (final g in l.gates) {
            if (gateFailure(l, prefix, g.id) == null)
              essential[g.id] = essential[g.id]! + 1;
          }
        }
        final trace =
            const SimulationEngine().simulate(l, RoutePlan(l.identity, prefix))
                as SimulationTrace;
        if (failure == null) {
          if (trace.outcome != SimulationOutcome.success)
            throw StateError('Oracle success mismatch');
          final paths = [for (final r in prefix) expand(l, r)];
          for (final g in l.gates) {
            var needsOther = false;
            for (var u = 0; u < paths.length; u++) {
              final own = paths[u];
              for (var t = 1; t < own.length; t++) {
                if (own[t] == g.door &&
                    !List.generate(own.length, (i) => i).any(
                      (a) => own[a] == g.trigger && a <= t && t < a + g.openFor,
                    ))
                  needsOther = true;
              }
            }
            if (!needsOther)
              throw StateError('Gate does not require cooperation');
          }
          safe++;
          var w = 1;
          for (var k = 0; k < prefix.length; k++) {
            w *= weights[k][key(prefix[k])]!;
          }
          raw += w;
          witness ??= List.of(prefix);
        } else {
          if (trace.outcome != SimulationOutcome.closedGate ||
              trace.durationInTimeUnits != Rational(failure))
            throw StateError('Oracle failure mismatch');
          failed ??= List.of(prefix);
        }
        return;
      }
      for (var ri = 0; ri < domains[i].length; ri++) {
        final route = domains[i][ri];
        var compatible = true;
        for (var j = 0; j < i; j++) {
          final pk = '$j:${indices[j]}:$i:$ri';
          if (!(pairs.putIfAbsent(
            pk,
            () => oracleCollisions(l, [prefix[j], route]).isEmpty,
          ))) {
            compatible = false;
            break;
          }
        }
        if (compatible) search([...prefix, route], [...indices, ri]);
      }
    }

    search([], []);
    if (essential.values.any((n) => n == 0)) throw StateError('Redundant gate');
    final d = design['levels'].singleWhere(
      (e) => e['id'] == l.identity.levelId,
    );
    if (safe != d['distinctSolutions'] ||
        raw != d['rawSolutions'] ||
        BigInt.from(raw) != solved.exactCount ||
        failed == null)
      throw StateError(
        'Count/essential gate mismatch ${l.identity.levelId} $safe $raw',
      );
    final authored = [
      for (final r in d['witness'])
        UnitRoute(r['unitId'], [
          for (final c in r['endpoints']) Cell(c[0], c[1]),
        ]),
    ];
    if ((const SimulationEngine().simulate(l, RoutePlan(l.identity, authored))
                as SimulationTrace)
            .outcome !=
        SimulationOutcome.success)
      throw StateError('Hint witness failed');
    reports.add({
      'id': l.identity.levelId,
      'safeDistinct': safe,
      'essentialGateRejectedPlans': essential,
      'allSolutionsRequireOtherUnit': true,
      'safeRaw': raw,
      'checkedBasePlans': checks,
      'pairChecks': pairs.length,
      'witness': [for (final r in authored) r.toJson()],
      'failure': [for (final r in failed!) r.toJson()],
    });
    print('${l.identity.levelId} PASS safe=$safe raw=$raw checked=$checks');
  }
  File(args[2]).writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'levels': reports, 'independentGateOracle': true}),
  );
}
