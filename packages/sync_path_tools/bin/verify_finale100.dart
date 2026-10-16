import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';
import 'verify_portals70.dart' show gateFailure, visits;

final class Candidate {
  final UnitRoute route;
  final BigInt occupancy;
  final int distance;
  Candidate(this.route, this.occupancy, this.distance);
}

/// Independent ray enumeration: reads rows directly. It does not call the
/// runtime destination function or the Python author's graph construction.
List<Candidate> enumerate(LevelSpec l, UnitSpec unit) {
  final goal = l.goal, result = <Candidate>[];
  List<Cell> ray(Cell c) {
    if (c == goal) return [];
    final ends = <Cell>[];
    for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      var x = c.x + dx, y = c.y + dy;
      while (x >= 0 &&
          x < l.map.width &&
          y >= 0 &&
          y < l.map.height &&
          l.map.rows[y][x] == '.') {
        final end = Cell(x, y);
        ends.add(end);
        if (end == goal) break;
        x += dx;
        y += dy;
      }
    }
    return ends;
  }

  final graph = {for (final c in l.map.walkable) c: ray(c)};
  final distance = {goal: 0};
  for (var i = 0; i < l.map.width * l.map.height; i++) {
    var changed = false;
    for (final e in graph.entries) {
      for (final end in e.value) {
        final n = distance[l.afterEndpoint(end)];
        if (n != null && (distance[e.key] ?? 999) > n + 1) {
          distance[e.key] = n + 1;
          changed = true;
        }
      }
    }
    if (!changed) break;
  }
  var nodes = 0;
  void visit(Cell c, List<Cell> path, (int, int)? direction) {
    if (++nodes > 2000000) throw StateError('UNKNOWN: enumeration budget');
    if (c == goal) {
      final r = UnitRoute(unit.id, path),
          samples = oracleSamples(l, UnitRoute(unit.id, path));
      var mask = BigInt.zero;
      for (final e in samples.entries) {
        for (final p in e.value) {
          if (p == Cell(goal.x * 2, goal.y * 2)) continue;
          final index = e.key * 256 + p.y * 16 + p.x;
          mask |= BigInt.one << index;
        }
      }
      result.add(
        Candidate(
          r,
          mask,
          (samples.keys.reduce((a, b) => a > b ? a : b) + 1) ~/ 2,
        ),
      );
      if (result.length > 2000) throw StateError('UNKNOWN: domain budget');
      return;
    }
    if ((distance[c] ?? 999) > l.maxCommands - path.length) return;
    for (final end in graph[c]!) {
      final d = ((end.x - c.x).sign, (end.y - c.y).sign);
      if (d == direction) continue;
      visit(l.afterEndpoint(end), [
        ...path,
        end,
      ], l.portalAt(end) == null ? d : null);
    }
  }

  visit(unit.start, [], null);
  return result;
}

void main(List<String> args) {
  final parsed = const LevelParser().parsePack(
    File(args[0]).readAsStringSync(),
  );
  if (!parsed.isValid) throw StateError('${parsed.issues}');
  final design = jsonDecode(File(args[1]).readAsStringSync()) as Map;
  final reports = <Object>[];
  for (final l in parsed.value!.levels.skip(70)) {
    final d = (design['levels'] as List).singleWhere(
      (d) => d['id'] == l.identity.levelId,
    );
    final ds = [for (final u in l.units) enumerate(l, u)];
    if (jsonEncode(ds.map((d) => d.length).toList()) !=
        jsonEncode(d['canonicalDomains']))
      throw StateError('Domain mismatch ${l.identity.levelId}');
    final tables = <(int, int), List<List<int>>>{};
    var pairs = 0;
    for (var i = 0; i < ds.length; i++) {
      for (var j = i + 1; j < ds.length; j++) {
        tables[(i, j)] = [
          for (final a in ds[i])
            [
              for (var bi = 0; bi < ds[j].length; bi++)
                if ((a.occupancy & ds[j][bi].occupancy) == BigInt.zero) bi,
            ],
        ];
        pairs += ds[i].length * ds[j].length;
      }
    }
    var safe = 0, base = 0, minMax = 999, minSum = 999, minExtra = 999;
    final removal = List.filled(l.gates.length, 0);
    final shortest = [
      for (final domain in ds)
        domain.map((r) => r.distance).reduce((a, b) => a < b ? a : b),
    ];
    List<UnitRoute>? closed;
    void choose(List<int> chosen) {
      final i = chosen.length;
      if (i < ds.length) {
        var allowed = List.generate(ds[i].length, (k) => k).toSet();
        for (var k = 0; k < i; k++) {
          allowed = allowed.intersection(tables[(k, i)]![chosen[k]].toSet());
        }
        for (final candidate in allowed) {
          choose([...chosen, candidate]);
        }
        return;
      }
      if (++base > 50000) throw StateError('UNKNOWN: assignment budget');
      final rs = [for (var k = 0; k < ds.length; k++) ds[k][chosen[k]]].route;
      final failure = gateFailure(l, rs);
      if (failure != null) {
        closed ??= rs;
        for (var g = 0; g < l.gates.length; g++) {
          if (gateFailure(l, rs, l.gates[g].id) == null) removal[g]++;
        }
        return;
      }
      safe++;
      for (final g in l.gates) {
        final paths = rs.map((r) => visits(l, r)).toList();
        var requiresAnotherBall = false;
        for (final path in paths) {
          for (final (t, c) in path) {
            if (c == g.door &&
                !path.any(
                  (v) => v.$2 == g.trigger && v.$1 <= t && t < v.$1 + g.openFor,
                )) {
              requiresAnotherBall = true;
            }
          }
        }
        if (!requiresAnotherBall)
          throw StateError('Gate does not require cooperation');
      }
      final trace = const SimulationEngine().simulate(
        l,
        RoutePlan(l.identity, rs),
      );
      if (trace is! SimulationTrace ||
          trace.outcome != SimulationOutcome.success)
        throw StateError('Engine rejected oracle solution');
      final maximum = rs
          .map((r) => r.endpoints.length)
          .reduce((a, b) => a > b ? a : b);
      final sum = rs.fold(0, (a, r) => a + r.endpoints.length);
      var extra = 0;
      for (var k = 0; k < ds.length; k++) {
        extra += ds[k][chosen[k]].distance - shortest[k];
      }
      if (maximum < minMax) minMax = maximum;
      if (sum < minSum) minSum = sum;
      if (extra < minExtra) minExtra = extra;
    }

    choose([]);
    if (safe != d['canonicalSolutions'] ||
        base != d['baseSolutions'] ||
        minMax != l.maxCommands ||
        minSum != d['minimumTotalCommands'] ||
        minExtra != d['minimumExtraDistance'] ||
        removal.any((n) => n == 0)) {
      throw StateError(
        '${l.identity.levelId} audit mismatch safe=$safe base=$base min=$minMax/$minSum extra=$minExtra',
      );
    }
    final witness = [
      for (final r in d['witness'])
        UnitRoute(r['unitId'], [
          for (final c in r['endpoints']) Cell(c[0], c[1]),
        ]),
    ];
    final trace =
        const SimulationEngine().simulate(l, RoutePlan(l.identity, witness))
            as SimulationTrace;
    if (trace.outcome != SimulationOutcome.success)
      throw StateError('Hint witness failed');
    if (closed != null) {
      final failureTrace =
          const SimulationEngine().simulate(l, RoutePlan(l.identity, closed!))
              as SimulationTrace;
      if (failureTrace.outcome != SimulationOutcome.closedGate)
        throw StateError('Closed gate example mismatch');
    }
    reports.add({
      'id': l.identity.levelId,
      'status': 'PASS',
      'canonicalSolutions': safe,
      'basePlans': base,
      'pairChecks': pairs,
      'minimumRequiredMaxCommands': minMax,
      'minimumTotalCommands': minSum,
      'minimumExtraDistance': minExtra,
      'gateRemovalAdds': removal,
      'witness': [for (final r in witness) r.toJson()],
      'duration': trace.durationInTimeUnits.toDouble(),
      'closedFailure': closed?.map((r) => r.toJson()).toList(),
    });
    print(
      '${l.identity.levelId} PASS canonical=$safe minMax=$minMax minSum=$minSum extra=$minExtra pairs=$pairs',
    );
  }
  File(args[2]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'levels': reports,
      'method':
          'independent canonical ray enumeration + exact half-time occupancy + engine for every safe canonical plan',
      'rawCommandCounts':
          'Not claimed. Same-direction splits preserve constant-speed timing and can be merged except at a portal entry.',
      'humanDifficulty': 'NOT_PLAYTESTED',
    }),
  );
}

extension on List<Candidate> {
  List<UnitRoute> get route => [for (final c in this) c.route];
}
