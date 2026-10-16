import 'dart:io';
import 'package:test/test.dart';
import 'package:sync_path_core/sync_path_core.dart';

LevelSpec level(int i) => const LevelParser()
    .parsePack(
      File(
        '../../docs/next_version_27이후/game_implementation_v4/previous_12_levels.json',
      ).readAsStringSync(),
    )
    .value!
    .levels[i - 1];
SimulationTrace run(LevelSpec l, List<UnitRoute> routes) =>
    const SimulationEngine().simulate(l, RoutePlan(l.identity, routes))
        as SimulationTrace;
void main() {
  test(
    'New runtime pack binds constant speed identity; old rule remains historical',
    () {
      expect(level(1).identity.ruleSetId, constantSpeedRuleSet);
      expect(level(1).identity.revision, 2);
    },
  );
  test('Device L07: long downward moves keep one cell per logical time', () {
    final l = level(7);
    final trace = run(l, [
      UnitRoute('A', [const Cell(2, 0), const Cell(2, 4)]),
      UnitRoute('B', [const Cell(0, 0), const Cell(2, 0), const Cell(2, 4)]),
    ]);
    expect(trace.outcome, SimulationOutcome.success);
    expect(trace.arrivals.map((a) => a.globalTime), [Rational(5), Rational(7)]);
    for (final p in trace.motions) {
      expect(
        p.durationUnits,
        (p.end.x - p.start.x).abs() + (p.end.y - p.start.y).abs(),
      );
    }
  });
  test(
    'Device L08: paths of 6,8,3 cells arrive at 6,8,3, never simultaneously',
    () {
      final l = level(8);
      final trace = run(l, [
        UnitRoute('A', [const Cell(3, 4), const Cell(3, 2), l.goal]),
        UnitRoute('B', [const Cell(4, 0), const Cell(4, 2), l.goal]),
        UnitRoute('C', [const Cell(1, 3), const Cell(1, 2), l.goal]),
      ]);
      expect(trace.outcome, SimulationOutcome.success);
      expect(
        {for (final a in trace.arrivals) a.unitId: a.globalTime},
        {'A': Rational(6), 'B': Rational(8), 'C': Rational(3)},
      );
    },
  );
  test('Different command ordinals collide on a shared absolute clock', () {
    const a = LinearPiece(
      'A',
      1,
      Cell(0, 0),
      Cell(5, 0),
      startTimeUnits: 0,
      endTimeUnits: 5,
    );
    const b = LinearPiece(
      'B',
      2,
      Cell(3, 2),
      Cell(3, 0),
      startTimeUnits: 1,
      endTimeUnits: 3,
    );
    final c = const TemporalCollisionResolver().resolve(a, b) as InstantContact;
    expect(c.time, Rational(3));
    expect(c.position, RationalPoint.cell(const Cell(3, 0)));
  });
  test('Head-on contact between cells is detected at exact half time', () {
    const a = LinearPiece(
      'A',
      1,
      Cell(0, 0),
      Cell(3, 0),
      startTimeUnits: 0,
      endTimeUnits: 3,
    );
    const b = LinearPiece(
      'B',
      1,
      Cell(3, 0),
      Cell(0, 0),
      startTimeUnits: 0,
      endTimeUnits: 3,
    );
    final c = const TemporalCollisionResolver().resolve(a, b) as InstantContact;
    expect(c.time, Rational(3, 2));
    expect(c.position.x, Rational(3, 2));
  });
  test(
    'Crossing at different times has no contact; past arrivals disappear',
    () {
      const a = LinearPiece(
        'A',
        1,
        Cell(0, 0),
        Cell(4, 0),
        startTimeUnits: 0,
        endTimeUnits: 4,
      );
      const b = LinearPiece(
        'B',
        2,
        Cell(3, 2),
        Cell(3, 0),
        startTimeUnits: 3,
        endTimeUnits: 5,
      );
      expect(const TemporalCollisionResolver().resolve(a, b), isA<NoContact>());
      const after = LinearPiece(
        'B',
        3,
        Cell(4, 2),
        Cell(4, 0),
        startTimeUnits: 5,
        endTimeUnits: 7,
      );
      expect(
        const TemporalCollisionResolver().resolve(a, after),
        isA<NoContact>(),
      );
    },
  );
  test('Simultaneous Goal is allowed, simultaneous non-Goal is not', () {
    const a = LinearPiece(
      'A',
      1,
      Cell(0, 2),
      Cell(2, 2),
      startTimeUnits: 0,
      endTimeUnits: 2,
    );
    const b = LinearPiece(
      'B',
      1,
      Cell(4, 2),
      Cell(2, 2),
      startTimeUnits: 0,
      endTimeUnits: 2,
    );
    expect(earliestTemporalCollisions([a, b], const Cell(2, 2)), isEmpty);
    expect(
      earliestTemporalCollisions([a, b], const Cell(1, 1)).single.globalTime,
      Rational(2),
    );
  });
  test('Straight splitting cannot change timing or collision', () {
    const whole = LinearPiece(
      'A',
      1,
      Cell(0, 0),
      Cell(4, 0),
      startTimeUnits: 0,
      endTimeUnits: 4,
    );
    const first = LinearPiece(
      'A',
      1,
      Cell(0, 0),
      Cell(2, 0),
      startTimeUnits: 0,
      endTimeUnits: 2,
    );
    const second = LinearPiece(
      'A',
      2,
      Cell(2, 0),
      Cell(4, 0),
      startTimeUnits: 2,
      endTimeUnits: 4,
    );
    const b = LinearPiece(
      'B',
      1,
      Cell(3, 3),
      Cell(3, 0),
      startTimeUnits: 0,
      endTimeUnits: 3,
    );
    final x = earliestTemporalCollisions([whole, b], const Cell(7, 7));
    final y = earliestTemporalCollisions([first, second, b], const Cell(7, 7));
    expect(x.single.globalTime, y.single.globalTime);
    expect(x.single.position, y.single.position);
  });
  test('Boundary contacts deduplicate pairs and retain every pair', () {
    const a1 = LinearPiece(
      'A',
      1,
      Cell(0, 1),
      Cell(1, 1),
      startTimeUnits: 0,
      endTimeUnits: 1,
    );
    const a2 = LinearPiece(
      'A',
      2,
      Cell(1, 1),
      Cell(1, 2),
      startTimeUnits: 1,
      endTimeUnits: 2,
    );
    const b = LinearPiece(
      'B',
      1,
      Cell(2, 1),
      Cell(1, 1),
      startTimeUnits: 0,
      endTimeUnits: 1,
    );
    const c = LinearPiece(
      'C',
      1,
      Cell(1, 0),
      Cell(1, 1),
      startTimeUnits: 0,
      endTimeUnits: 1,
    );
    expect(
      earliestTemporalCollisions([a1, a2, b, c], const Cell(7, 7)).length,
      3,
    );
  });
}
