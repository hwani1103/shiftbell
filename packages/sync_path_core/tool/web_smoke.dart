import 'dart:convert';
import 'package:sync_path_core/sync_path_core.dart';
import 'web_fixtures.g.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Cell cell(dynamic j) => Cell(j[0] as int, j[1] as int);
Rational fraction(dynamic j) => Rational(j[0] as int, j[1] as int);
List<UnitRoute> routes(dynamic j) => [
  for (final r in j)
    UnitRoute(r['unitId'] as String, [for (final e in r['endpoints']) cell(e)]),
];

// Runs compiled JavaScript without a browser or Flutter. Development data only.
void main() {
  final pack = const LevelParser().parsePack(pilotLevels).value!;
  final certificates = jsonDecode(pilotWitnesses) as List;
  for (var i = 0; i < pack.levels.length; i++) {
    final level = pack.levels[i];
    final trace = const SimulationEngine().simulate(
      level,
      RoutePlan(level.identity, routes(certificates[i]['witness'])),
    );
    require(
      trace is SimulationTrace && trace.outcome == SimulationOutcome.success,
      'JS witness ${level.identity.levelId}',
    );
  }
  final fixtures = jsonDecode(collisionFixtures) as Map<String, dynamic>;
  for (final v in fixtures['vectors']) {
    final contact = const CollisionResolver().resolve(
      LinearPiece('A', 1, cell(v['startA']), cell(v['endA'])),
      LinearPiece('B', 1, cell(v['startB']), cell(v['endB'])),
    );
    final expected = v['expected'];
    if (expected == null) {
      require(contact is NoContact, v['id'] as String);
    } else if (expected['interval'] == true) {
      require(contact is CoincidentInterval, v['id'] as String);
    } else {
      require(
        contact is InstantContact &&
            contact.time == fraction(expected['time']) &&
            contact.position ==
                RationalPoint(
                  fraction(expected['position'][0]),
                  fraction(expected['position'][1]),
                ),
        v['id'] as String,
      );
    }
  }
  final bad = pilotLevels.replaceFirst('"width": 5', '"width": 5.0');
  require(
    !const LevelParser().parsePack(bad).isValid,
    'JS must reject float lexical integers',
  );
  final early = fixtures['earlyArrivalCase'];
  final levelInput = {
    ...early['level'] as Map<String, dynamic>,
    'schemaVersion': 1,
    'ruleSetId': supportedRuleSet,
  };
  final level = const LevelParser()
      .parseLevel(jsonEncode(levelInput), packId: 'test-pack')
      .value!;
  final trace =
      const SimulationEngine().simulate(
            level,
            RoutePlan(level.identity, routes(early['routes'])),
          )
          as SimulationTrace;
  require(
    trace.outcome == SimulationOutcome.success &&
        trace.arrivals.first.step == 1 &&
        trace.arrivals.last.step == 3 &&
        trace.motions.length == 4,
    'JS early arrival/removal',
  );
  // 64-cell access, including indexes >=32, uses cells and sets rather than bitsets.
  final large = LevelSpec(
    identity: const LevelIdentity('test-pack', 'large', 1, supportedRuleSet),
    map: GridMap(width: 8, height: 8, rows: List.filled(8, '........')),
    goal: const Cell(7, 7),
    units: const [UnitSpec('A', Cell(0, 7)), UnitSpec('B', Cell(7, 0))],
    maxCommands: 1,
  );
  final largeTrace =
      const SimulationEngine().simulate(
            large,
            RoutePlan(large.identity, [
              UnitRoute('A', [large.goal]),
              UnitRoute('B', [large.goal]),
            ]),
          )
          as SimulationTrace;
  require(
    largeTrace.outcome == SimulationOutcome.success,
    'JS full 64-cell grid',
  );
  print(
    'PASS: JS 12 witnesses, 20 collision vectors, float rejection, early arrival, 64-cell map',
  );
}
