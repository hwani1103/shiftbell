import 'package:sync_path_core/sync_path_core.dart';

void main() {
  final level = LevelSpec(
    identity: const LevelIdentity('smoke', 'L08', 2, constantSpeedRuleSet),
    map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
    goal: const Cell(2, 2),
    units: const [
      UnitSpec('A', Cell(0, 4)),
      UnitSpec('B', Cell(0, 0)),
      UnitSpec('C', Cell(0, 3)),
    ],
    maxCommands: 3,
  );
  final result =
      const SimulationEngine().simulate(
            level,
            RoutePlan(level.identity, [
              UnitRoute('A', [const Cell(3, 4), const Cell(3, 2), level.goal]),
              UnitRoute('B', [const Cell(4, 0), const Cell(4, 2), level.goal]),
              UnitRoute('C', [const Cell(1, 3), const Cell(1, 2), level.goal]),
            ]),
          )
          as SimulationTrace;
  final times = {
    for (final a in result.arrivals) a.unitId: a.globalTime.toDouble(),
  };
  if (result.outcome != SimulationOutcome.success ||
      times['A'] != 6 ||
      times['B'] != 8 ||
      times['C'] != 3)
    throw StateError('Constant speed arrival mismatch');
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
    2,
    Cell(3, 0),
    Cell(0, 0),
    startTimeUnits: 0,
    endTimeUnits: 3,
  );
  final c = const TemporalCollisionResolver().resolve(a, b) as InstantContact;
  if (c.time != Rational(3, 2) || c.position.x != Rational(3, 2))
    throw StateError('Half-cell contact mismatch');
  print('PASS: constant-cell-speed-v2 A=6 B=8 C=3, exact half-cell collision');
}
