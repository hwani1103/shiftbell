import 'dart:convert';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:test/test.dart';
import 'support/fixtures.dart';

SimulationTrace simulate(LevelSpec level, List<UnitRoute> routes) =>
    const SimulationEngine().simulate(
          level,
          RoutePlan(level.identity, routes, revision: 9),
        )
        as SimulationTrace;
void main() {
  final pack = pilotPack();
  final certificates = fixture('09_pilot_certificates.json')['levels'];
  for (var i = 0; i < pack.levels.length; i++) {
    final level = pack.levels[i];
    final certificate = certificates[i];
    test(
      '${level.identity.levelId} witness succeeds deterministically regardless of Unit/route order',
      () {
        final planRoutes = routes(certificate['witness']);
        final trace = simulate(level, planRoutes);
        expect(trace.outcome, SimulationOutcome.success);
        expect(trace.arrivals.length, level.units.length);
        expect(trace.routeRevision, 9);
        expect(
          trace.durationInSteps,
          Rational(
            planRoutes
                .map((r) => r.endpoints.length)
                .reduce((a, b) => a > b ? a : b),
          ),
        );
        expect(
          jsonEncode(trace.toJson()),
          jsonEncode(simulate(level, planRoutes.reversed.toList()).toJson()),
        );
        final reordered = LevelSpec(
          identity: level.identity,
          map: level.map,
          goal: level.goal,
          units: level.units.reversed.toList(),
          maxCommands: level.maxCommands,
        );
        expect(
          jsonEncode(trace.toJson()),
          jsonEncode(simulate(reordered, planRoutes).toJson()),
        );
        expect(() => trace.motions.clear(), throwsUnsupportedError);
        expect(() => trace.arrivals.clear(), throwsUnsupportedError);
        expect(() => trace.earliestCollisions.clear(), throwsUnsupportedError);
        expect(() => level.map.rows.clear(), throwsUnsupportedError);
        expect(() => level.units.clear(), throwsUnsupportedError);
        expect(
          () => planRoutes.first.endpoints.clear(),
          throwsUnsupportedError,
        );
      },
    );
    if (certificate['failureExample'] != null) {
      test(
        '${level.identity.levelId} failure matches exact earliest pair(s), time, position',
        () {
          final failure = certificate['failureExample'];
          final trace = simulate(level, routes(failure['routes']));
          expect(trace.outcome, SimulationOutcome.collision);
          final expected = failure['earliestCollisions'];
          expect(trace.earliestCollisions.length, expected.length);
          for (var j = 0; j < expected.length; j++) {
            final event = trace.earliestCollisions[j];
            expect(event.step, expected[j]['step']);
            expect(event.localTime, fraction(expected[j]['time']));
            expect(event.position, point(expected[j]['position']));
            expect(event.unitIds, expected[j]['units']);
          }
          expect(
            trace.motions.any(
              (piece) => piece.step > trace.earliestCollisions.first.step,
            ),
            isFalse,
          );
          expect(
            trace.arrivals.every(
              (a) => a.globalTime.compareTo(trace.durationInSteps) <= 0,
            ),
            isTrue,
          );
        },
      );
    }
  }
  test('E11/E12 A arrives on Step 1, B on Step 3, no filler pieces', () {
    final early = fixture('10_collision_fixtures.json')['earlyArrivalCase'];
    final j = Map<String, dynamic>.from(early['level'] as Map)
      ..['schemaVersion'] = 1
      ..['ruleSetId'] = supportedRuleSet;
    final level = const LevelParser()
        .parseLevel(jsonEncode(j), packId: 'test-pack')
        .value!;
    final trace = simulate(level, routes(early['routes']));
    expect(trace.outcome, SimulationOutcome.success);
    expect(trace.arrivals.map((a) => [a.unitId, a.step]), [
      ['A', 1],
      ['B', 3],
    ]);
    expect(trace.motions.where((p) => p.unitId == 'A').length, 1);
    expect(trace.motions.length, 4);
  });
  test('E10/E13 shared Goal endpoint is safe; everyone finishes before N', () {
    final level = openLevel(goal: const Cell(2, 0));
    final trace = simulate(level, [
      UnitRoute('A', [level.goal]),
      UnitRoute('B', [level.goal]),
    ]);
    expect(trace.outcome, SimulationOutcome.success);
    expect(trace.durationInSteps, Rational.one);
    expect(trace.motions.length, 2);
  });
  test(
    'E16 Goal arrival at forbidden collision time is recorded but cannot win',
    () {
      final level = openLevel(
        goal: const Cell(4, 4),
        units: const [
          UnitSpec('A', Cell(0, 0)),
          UnitSpec('B', Cell(2, 2)),
          UnitSpec('C', Cell(0, 4)),
        ],
      );
      final trace = simulate(level, [
        UnitRoute('A', [const Cell(2, 0), const Cell(4, 0), level.goal]),
        UnitRoute('B', [const Cell(2, 0), const Cell(4, 0), level.goal]),
        UnitRoute('C', [level.goal]),
      ]);
      expect(trace.outcome, SimulationOutcome.collision);
      expect(trace.durationInSteps, Rational.one);
      expect(trace.arrivals.map((a) => a.unitId), ['C']);
      expect(trace.earliestCollisions.single.unitIds, ['A', 'B']);
    },
  );
  test(
    'E17 boundary collision belongs to previous Step once; future arrival suppressed',
    () {
      final level = pack.levels[1];
      final trace = simulate(
        level,
        routes(certificates[1]['failureExample']['routes']),
      );
      expect(trace.earliestCollisions.single.step, 1);
      expect(trace.earliestCollisions.single.localTime, Rational.one);
      expect(trace.earliestCollisions.single.globalTime, Rational.one);
      expect(trace.arrivals, isEmpty);
      expect(trace.motions.every((p) => p.step == 1), isTrue);
    },
  );
  test('E19 input list mutation cannot change a plan snapshot', () {
    final level = openLevel(goal: const Cell(2, 0));
    final endpoints = [level.goal];
    final route = UnitRoute('A', endpoints);
    final routeList = [
      route,
      UnitRoute('B', [level.goal]),
    ];
    final plan = RoutePlan(level.identity, routeList);
    endpoints.clear();
    routeList.clear();
    final trace =
        const SimulationEngine().simulate(level, plan) as SimulationTrace;
    expect(trace.outcome, SimulationOutcome.success);
    expect(trace.motions.length, 2);
    expect(
      () =>
          const MotionCompiler().compile(level, RoutePlan(level.identity, [])),
      throwsArgumentError,
    );
  });
  test(
    'Splitting changes time, so geometry-equivalent paths may change outcome',
    () {
      final level = pack.levels[5];
      expect(
        simulate(level, routes(certificates[5]['witness'])).outcome,
        SimulationOutcome.success,
      );
      expect(
        simulate(
          level,
          routes(certificates[5]['failureExample']['routes']),
        ).outcome,
        SimulationOutcome.collision,
      );
    },
  );
}
