import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/sync_path_tools.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';

String sampleKey(LevelSpec l, UnitRoute r) {
  final m = oracleSamples(l, r);
  final keys = m.keys.toList()..sort();
  return jsonEncode([
    for (final t in keys)
      [t, ...(m[t]!.toList()..sort()).map((c) => c.toJson())],
  ]);
}

List<(int, Cell)> visits(LevelSpec l, UnitRoute r) => [
  for (final e in oracleSamples(l, r).entries)
    if (e.key.isEven)
      for (final c in e.value) (e.key ~/ 2, Cell(c.x ~/ 2, c.y ~/ 2)),
];
int? gateFailure(LevelSpec l, List<UnitRoute> rs, [String? ignore]) {
  final paths = [for (final r in rs) visits(l, r)];
  int? failure;
  for (final g in l.gates.where((g) => g.id != ignore)) {
    final activations = [
      for (final path in paths)
        for (final (t, c) in path)
          if (t > 0 && c == g.trigger) t,
    ];
    for (final path in paths)
      for (final (t, c) in path) {
        if (c == g.door &&
            !activations.any((a) => a <= t && t < a + g.openFor)) {
          if (failure == null || t < failure) failure = t;
        }
      }
  }
  return failure;
}

void main(List<String> args) {
  final pack = const LevelParser().parsePack(File(args[0]).readAsStringSync());
  if (!pack.isValid) throw StateError('${pack.issues}');
  final design = jsonDecode(File(args[1]).readAsStringSync());
  final reports = <Object>[];
  for (final l in pack.value!.levels.skip(50).take(20)) {
    final solved = const PuzzleSolver().solve(l);
    if (!solved.exhaustive || solved.status != SolverStatus.sat)
      throw StateError('${l.identity.levelId}: ${solved.reason}');
    final ds = <List<UnitRoute>>[];
    final weights = <Map<String, int>>[];
    for (final u in l.units) {
      final direct = directRoutes(l, u);
      final actual = solved.domains[u.id]!;
      final a = direct.map((r) => jsonEncode(r.toJson())).toSet(),
          b = actual.map((r) => jsonEncode(r.toJson())).toSet();
      if (a.length != b.length || a.difference(b).isNotEmpty)
        throw StateError('Domain mismatch');
      final grouped = <String, UnitRoute>{}, count = <String, int>{};
      for (final r in direct) {
        final key = sampleKey(l, r);
        grouped[key] = r;
        count.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
      ds.add(grouped.values.toList());
      weights.add(count);
    }
    final compiled = <String, List<LinearPiece>>{};
    for (var i = 0; i < ds.length; i++)
      for (var ri = 0; ri < ds[i].length; ri++) {
        final routes = [
          for (var j = 0; j < ds.length; j++) j == i ? ds[i][ri] : ds[j].first,
        ];
        compiled['$i:$ri'] = const MotionCompiler()
            .compile(l, RoutePlan(l.identity, routes))
            .pieces
            .where((p) => p.unitId == l.units[i].id)
            .toList();
      }
    final pairs = <String, bool>{};
    var pairChecks = 0, portalContacts = 0;
    List<UnitRoute>? collisionWitness, closedWitness;
    for (var i = 0; i < ds.length; i++)
      for (var j = i + 1; j < ds.length; j++)
        for (var ai = 0; ai < ds[i].length; ai++)
          for (var bi = 0; bi < ds[j].length; bi++) {
            final expected = oracleCollisions(l, [ds[i][ai], ds[j][bi]]);
            final actual = earliestTemporalCollisions([
              ...compiled['$i:$ai']!,
              ...compiled['$j:$bi']!,
            ], l.goal);
            String key(List<CollisionEvent> events) => jsonEncode(
              events
                  .map(
                    (c) => [
                      c.globalTime.toJson(),
                      c.position.toJson(),
                      c.unitIds,
                    ],
                  )
                  .toList(),
            );
            if (key(expected) != key(actual))
              throw StateError(
                'Exact pair oracle mismatch ${l.identity.levelId} $i $ai $j $bi',
              );
            pairs['$i:$ai:$j:$bi'] = expected.isEmpty;
            pairChecks++;
            if (expected.any(
              (c) => l.portals.any(
                (p) =>
                    c.position == RationalPoint.cell(p.entry) ||
                    c.position == RationalPoint.cell(p.exit),
              ),
            ))
              portalContacts++;
            if (expected.isNotEmpty)
              collisionWitness ??= [
                for (var k = 0; k < ds.length; k++)
                  k == i
                      ? ds[i][ai]
                      : k == j
                      ? ds[j][bi]
                      : ds[k].first,
              ];
          }
    var safe = 0, raw = 0, checked = 0;
    final essential = {for (final g in l.gates) g.id: 0};
    void search(List<int> chosen) {
      final i = chosen.length;
      if (i < ds.length) {
        for (var ri = 0; ri < ds[i].length; ri++) {
          if (List.generate(
            i,
            (j) => j,
          ).every((j) => pairs['$j:${chosen[j]}:$i:$ri']!))
            search([...chosen, ri]);
        }
        return;
      }
      checked++;
      final rs = [for (var k = 0; k < ds.length; k++) ds[k][chosen[k]]];
      final failure = gateFailure(l, rs);
      final trace =
          const SimulationEngine().simulate(l, RoutePlan(l.identity, rs))
              as SimulationTrace;
      if (failure == null) {
        if (trace.outcome != SimulationOutcome.success || trace.portals.isEmpty)
          throw StateError('Safe oracle/essential portal mismatch');
        for (final g in l.gates) {
          var cooperation = false;
          for (final r in rs) {
            final path = visits(l, r);
            for (final (t, c) in path)
              if (c == g.door &&
                  !path.any(
                    (v) =>
                        v.$2 == g.trigger && v.$1 <= t && t < v.$1 + g.openFor,
                  ))
                cooperation = true;
          }
          if (!cooperation) throw StateError('Optional cooperation');
        }
        safe++;
        var weight = 1;
        for (var k = 0; k < rs.length; k++) {
          weight *= weights[k][sampleKey(l, rs[k])]!;
        }
        raw += weight;
      } else {
        if (trace.outcome != SimulationOutcome.closedGate ||
            trace.durationInTimeUnits != Rational(failure))
          throw StateError('Gate time mismatch');
        closedWitness ??= rs;
        for (final g in l.gates)
          if (gateFailure(l, rs, g.id) == null)
            essential[g.id] = essential[g.id]! + 1;
      }
    }

    search([]);
    final d = design['levels'].singleWhere(
      (d) => d['id'] == l.identity.levelId,
    );
    if (safe != d['distinctSolutions'] ||
        raw != d['rawSolutions'] ||
        solved.exactCount != BigInt.from(raw) ||
        essential.values.any((v) => v == 0))
      throw StateError(
        'Count mismatch ${l.identity.levelId}: $safe $raw vs ${d['distinctSolutions']} ${d['rawSolutions']}',
      );
    final witness = [
      for (final r in d['witness'])
        UnitRoute(r['unitId'], [
          for (final c in r['endpoints']) Cell(c[0], c[1]),
        ]),
    ];
    if ((const SimulationEngine().simulate(l, RoutePlan(l.identity, witness))
                as SimulationTrace)
            .outcome !=
        SimulationOutcome.success)
      throw StateError('Hint failed');
    reports.add({
      'id': l.identity.levelId,
      'safeDistinct': safe,
      'safeRaw': raw,
      'pairChecks': pairChecks,
      'portalContactPairs': portalContacts,
      'checkedBasePlans': checked,
      'essentialGateRejectedPlans': essential,
      'allSolutionsUsePortal': true,
      'allGatesRequireCooperation': true,
      'witness': [for (final r in witness) r.toJson()],
      if (closedWitness != null)
        'closedFailure': [for (final r in closedWitness!) r.toJson()],
      if (collisionWitness != null)
        'collisionFailure': [for (final r in collisionWitness) r.toJson()],
    });
    print(
      '${l.identity.levelId} PASS safe=$safe raw=$raw pairChecks=$pairChecks portalContacts=$portalContacts',
    );
  }
  File(args[2]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'levels': reports,
      'oracle':
          'independent half-time occupancy, instantaneous entry and exit, declarative gate windows',
    }),
  );
}
