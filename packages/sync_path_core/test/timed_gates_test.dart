import 'dart:convert';
import 'package:test/test.dart';
import 'package:sync_path_core/sync_path_core.dart';

LevelSpec fixture({int duration = 2, Cell trigger = const Cell(1, 0)}) =>
    LevelSpec(
      identity: const LevelIdentity('gates', 'test', 1, constantSpeedRuleSet),
      map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
      goal: const Cell(4, 4),
      units: const [UnitSpec('A', Cell(0, 0)), UnitSpec('B', Cell(0, 2))],
      maxCommands: 4,
      requiredMechanics: const [
        'straight-motion',
        'absorbing-shared-goal',
        'timed-gates',
      ],
      gates: [TimedGate('1', trigger, const Cell(2, 2), duration)],
    );
List<UnitRoute> routes({bool split = false}) => [
  UnitRoute('A', [
    if (split) const Cell(1, 0),
    const Cell(4, 0),
    const Cell(4, 4),
  ]),
  UnitRoute('B', [const Cell(4, 2), const Cell(4, 4)]),
];
SimulationTrace run(LevelSpec l, {bool split = false}) =>
    const SimulationEngine().simulate(
          l,
          RoutePlan(l.identity, routes(split: split)),
        )
        as SimulationTrace;
void main() {
  test(
    'Earlier collision wins; earlier door wins; simultaneous events retained',
    () {
      for (final door in [
        const Cell(0, 3),
        const Cell(1, 0),
        const Cell(2, 0),
      ]) {
        final l = LevelSpec(
          identity: const LevelIdentity(
            'gate',
            'precedence',
            1,
            constantSpeedRuleSet,
          ),
          map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
          goal: const Cell(4, 4),
          units: const [UnitSpec('A', Cell(0, 0)), UnitSpec('B', Cell(4, 0))],
          maxCommands: 3,
          requiredMechanics: const [
            'straight-motion',
            'absorbing-shared-goal',
            'timed-gates',
          ],
          gates: [TimedGate('1', const Cell(1, 1), door, 2)],
        );
        final t =
            const SimulationEngine().simulate(
                  l,
                  RoutePlan(l.identity, [
                    UnitRoute('A', [const Cell(4, 0), l.goal]),
                    UnitRoute('B', [
                      const Cell(0, 0),
                      const Cell(0, 4),
                      l.goal,
                    ]),
                  ]),
                )
                as SimulationTrace;
        expect(t.durationInTimeUnits, Rational(door.x == 1 ? 1 : 2));
        expect(
          t.outcome,
          door.x == 0
              ? SimulationOutcome.collision
              : SimulationOutcome.closedGate,
        );
        expect(t.earliestCollisions.isNotEmpty, door.x != 1);
        expect(t.gateTimeline.failures.isNotEmpty, door.x != 0);
      }
    },
  );
  test('Other ball opens gate, duration does not alter speed', () {
    final t = run(fixture());
    expect(t.outcome, SimulationOutcome.success);
    expect(t.arrivals.map((e) => e.globalTime), [Rational(6), Rational(8)]);
    expect(t.gateTimeline.activations.single.unitId, 'A');
  });
  test('Expiry is exclusive and stops all playback at exact door time', () {
    final t = run(fixture(duration: 1));
    expect(t.outcome, SimulationOutcome.closedGate);
    expect(t.durationInTimeUnits, Rational(2));
    expect(t.gateTimeline.failures.single.unitId, 'B');
    expect(t.arrivals, isEmpty);
    expect(t.earliestCollisions, isEmpty);
  });
  test('Simultaneous trigger is applied before gate check', () {
    expect(
      run(fixture(trigger: const Cell(2, 0), duration: 1)).outcome,
      SimulationOutcome.success,
    );
  });
  test('Straight command splitting cannot double-activate or change timer', () {
    final a = run(fixture()), b = run(fixture(), split: true);
    expect(b.gateTimeline.toJson(), a.gateTimeline.toJson());
    expect(b.durationInTimeUnits, a.durationInTimeUnits);
  });
  test('Repeated crossing refreshes and independent gates stay isolated', () {
    final l = fixture();
    final t = evaluateGates(l, const [
      LinearPiece(
        'A',
        1,
        Cell(0, 0),
        Cell(2, 0),
        startTimeUnits: 0,
        endTimeUnits: 2,
      ),
      LinearPiece(
        'A',
        2,
        Cell(2, 0),
        Cell(0, 0),
        startTimeUnits: 2,
        endTimeUnits: 4,
      ),
      LinearPiece(
        'B',
        1,
        Cell(0, 2),
        Cell(2, 2),
        startTimeUnits: 2,
        endTimeUnits: 4,
      ),
    ]);
    expect(t.activations.map((a) => a.time), [1, 3]);
    expect(t.failures, isEmpty);
    expect(t.remaining('1', 4), 1);
    expect(t.remaining('2', 4), 0);
    expect(t.remaining('1', 5), 0);
    expect(t.remaining('1', 0), 0);
  });
  test('Future triggers cannot unlock an earlier visit', () {
    final t = evaluateGates(fixture(), const [
      LinearPiece(
        'A',
        1,
        Cell(0, 0),
        Cell(2, 0),
        startTimeUnits: 3,
        endTimeUnits: 5,
      ),
      LinearPiece(
        'B',
        1,
        Cell(0, 2),
        Cell(2, 2),
        startTimeUnits: 0,
        endTimeUnits: 2,
      ),
    ]);
    expect(t.failures.single.time, 2);
    expect(t.activations, isEmpty);
  });
  test('Parser rejects invalid gate contracts', () {
    final base = <String, dynamic>{
      'schemaVersion': 1,
      'ruleSetId': constantSpeedRuleSet,
      'packId': 'test',
      'revision': 1,
      'levels': [
        {
          'id': 'x',
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
              'start': [0, 2],
            },
          ],
          'maxCommands': 4,
          'requiredMechanics': [
            'straight-motion',
            'absorbing-shared-goal',
            'timed-gates',
          ],
          'gates': [
            {
              'id': '1',
              'trigger': [1, 0],
              'door': [2, 2],
              'openFor': 2,
            },
          ],
        },
      ],
    };
    expect(const LevelParser().parsePack(jsonEncode(base)).isValid, isTrue);
    for (final value in [0, 13, 1.5]) {
      base['levels'][0]['gates'][0]['openFor'] = value;
      expect(const LevelParser().parsePack(jsonEncode(base)).isValid, isFalse);
    }
    base['levels'][0]['gates'][0]['openFor'] = 2;
    base['levels'][0]['gates'][0]['door'] = [0, 0];
    expect(const LevelParser().parsePack(jsonEncode(base)).isValid, isFalse);
  });
}
