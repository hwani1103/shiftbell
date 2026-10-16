import 'dart:convert';
import 'package:test/test.dart';
import 'package:sync_path_core/sync_path_core.dart';

LevelSpec fixture({
  Cell b = const Cell(4, 0),
  List<TimedGate> gates = const [],
  List<PortalPair>? portals,
}) => LevelSpec(
  identity: const LevelIdentity('portal-test', 'P1', 1, constantSpeedRuleSet),
  map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
  goal: const Cell(4, 4),
  units: [const UnitSpec('A', Cell(0, 0)), UnitSpec('B', b)],
  maxCommands: 5,
  gates: gates,
  portals: portals ?? const [PortalPair('1', Cell(2, 0), Cell(2, 3))],
  requiredMechanics: const [
    'straight-motion',
    'absorbing-shared-goal',
    'endpoint-portals',
    'timed-gates',
  ],
);
SimulationTrace run(LevelSpec l, List<Cell> a, List<Cell> b) =>
    const SimulationEngine().simulate(
          l,
          RoutePlan(l.identity, [UnitRoute('A', a), UnitRoute('B', b)]),
        )
        as SimulationTrace;
const aPath = [Cell(2, 0), Cell(4, 3), Cell(4, 4)];
void main() {
  test(
    'transfer costs no extra move or time; every traveled cell costs one time',
    () {
      final t = run(fixture(), aPath, [const Cell(4, 4)]);
      expect(t.outcome, SimulationOutcome.success);
      expect(t.portals.single.timeUnits, 2);
      expect(t.arrivals.firstWhere((e) => e.unitId == 'A').timeUnits, 5);
      expect(t.motions.where((e) => e.unitId == 'A').length, 3);
      for (final p in t.motions) {
        expect(
          p.durationUnits,
          (p.end.x - p.start.x).abs() + (p.end.y - p.start.y).abs(),
        );
      }
      expect(
        t.motions.where((e) => e.unitId == 'A').elementAt(1).start,
        const Cell(2, 3),
      );
    },
  );
  test('crossing IN without ending there does not transfer', () {
    final t = run(
      fixture(b: const Cell(0, 4)),
      [const Cell(4, 0), const Cell(4, 4)],
      [const Cell(4, 4)],
    );
    expect(t.portals, isEmpty);
    expect(t.outcome, SimulationOutcome.success);
  });
  test('exact entry contact blocks transfer at the same instant', () {
    final t = run(fixture(), aPath, [
      const Cell(0, 0),
      const Cell(0, 4),
      const Cell(4, 4),
    ]);
    expect(t.outcome, SimulationOutcome.collision);
    expect(t.durationInTimeUnits, Rational(2));
    expect(
      t.earliestCollisions.single.position,
      RationalPoint.cell(const Cell(2, 0)),
    );
  });
  test('exact exit contact is detected without a moving bridge', () {
    final t = run(fixture(b: const Cell(4, 3)), aPath, [
      const Cell(0, 3),
      const Cell(0, 4),
      const Cell(4, 4),
    ]);
    expect(t.outcome, SimulationOutcome.collision);
    expect(t.durationInTimeUnits, Rational(2));
    expect(
      t.earliestCollisions.single.position,
      RationalPoint.cell(const Cell(2, 3)),
    );
  });
  test('there is no collision along the space between IN and OUT', () {
    final t = run(fixture(b: const Cell(1, 1)), aPath, [
      const Cell(3, 1),
      const Cell(3, 4),
      const Cell(4, 4),
    ]);
    expect(t.outcome, SimulationOutcome.success);
  });
  test('reusable portal can be used twice by the same ball', () {
    final t = run(
      fixture(),
      [const Cell(2, 0), const Cell(2, 0), const Cell(4, 3), const Cell(4, 4)],
      [const Cell(4, 4)],
    );
    expect(t.outcome, SimulationOutcome.success);
    expect(t.portals.map((e) => e.timeUnits), [2, 5]);
  });
  test('portal shortcut opens another balls gate at exact constant speed', () {
    final l = fixture(gates: const [TimedGate('1', Cell(3, 3), Cell(4, 2), 2)]);
    final t = run(l, aPath, [
      const Cell(3, 0),
      const Cell(4, 0),
      const Cell(4, 4),
    ]);
    expect(t.outcome, SimulationOutcome.success);
    expect(t.gateTimeline.activations.single.time, 3);
    final failed = run(l, aPath, [const Cell(4, 4)]);
    expect(failed.outcome, SimulationOutcome.closedGate);
    expect(failed.durationInTimeUnits, Rational(2));
  });
  test(
    'portal placement rejects overlapping devices, starts, goals, pairs',
    () {
      for (final p in const [
        PortalPair('1', Cell(2, 0), Cell(2, 0)),
        PortalPair('1', Cell(0, 0), Cell(2, 3)),
        PortalPair('1', Cell(2, 0), Cell(4, 4)),
      ]) {
        expect(
          const LevelValidator().validate(fixture(portals: [p])).isValid,
          isFalse,
        );
      }
      expect(
        const LevelValidator()
            .validate(
              fixture(gates: const [TimedGate('g', Cell(1, 0), Cell(2, 3), 2)]),
            )
            .isValid,
        isFalse,
      );
    },
  );
  test('bounded parser preserves portal and rejects malformed portal', () {
    final j = <String, Object>{
      'schemaVersion': 1,
      'ruleSetId': constantSpeedRuleSet,
      'id': 'P1',
      'revision': 1,
      'width': 5,
      'height': 5,
      'rows': List.filled(5, '.....'),
      'goal': [4, 4],
      'units': [
        {
          'id': 'A',
          'start': [0, 0],
        },
        {
          'id': 'B',
          'start': [4, 0],
        },
      ],
      'maxCommands': 5,
      'requiredMechanics': [
        'straight-motion',
        'absorbing-shared-goal',
        'endpoint-portals',
      ],
      'portals': [
        {
          'id': '1',
          'entry': [2, 0],
          'exit': [2, 3],
        },
      ],
    };
    expect(
      const LevelParser()
          .parseLevel(jsonEncode(j), packId: 'p')
          .value!
          .portals
          .single
          .exit,
      const Cell(2, 3),
    );
    j['portals'] = [
      {
        'id': '1',
        'entry': [2, 0],
        'exit': [9, 3],
      },
    ];
    expect(
      const LevelParser().parseLevel(jsonEncode(j), packId: 'p').isValid,
      isFalse,
    );
  });
  test(
    'editor validates next endpoint from exit, even when not aligned to entry',
    () {
      final l = fixture();
      expect(
        const RouteValidator()
            .validateRoute(l, l.units.first, UnitRoute('A', aPath))
            .isValid,
        isTrue,
      );
      expect(
        legalDestinations(l, l.afterEndpoint(const Cell(2, 0))),
        contains(const Cell(4, 3)),
      );
    },
  );
}
