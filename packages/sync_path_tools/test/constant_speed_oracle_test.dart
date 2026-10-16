import 'dart:math';
import 'package:test/test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/src/independent_oracle.dart';

void main() {
  test(
    '4000 seeded v2 trajectories: exact whole-segment contacts equal independent cell-edge oracle',
    () {
      final rng = Random(20261013);
      for (var trial = 0; trial < 4000; trial++) {
        final starts = [
          Cell(rng.nextInt(6), rng.nextInt(6)),
          Cell(rng.nextInt(6), rng.nextInt(6)),
          Cell(rng.nextInt(6), rng.nextInt(6)),
        ];
        final units = [
          for (var i = 0; i < 3; i++)
            UnitSpec(String.fromCharCode(65 + i), starts[i]),
        ];
        final level = LevelSpec(
          identity: const LevelIdentity(
            'oracle',
            'random',
            1,
            constantSpeedRuleSet,
          ),
          map: GridMap(width: 8, height: 8, rows: List.filled(8, '........')),
          goal: const Cell(7, 7),
          units: units,
          maxCommands: 4,
        );
        final routes = <UnitRoute>[], pieces = <LinearPiece>[];
        for (final u in units) {
          var cell = u.start, time = 0;
          final ends = <Cell>[];
          final count = 1 + rng.nextInt(4);
          for (var n = 0; n < count; n++) {
            final horizontal = rng.nextBool();
            var coordinate = rng.nextInt(6);
            if (coordinate == (horizontal ? cell.x : cell.y))
              coordinate = (coordinate + 1) % 6;
            final end = horizontal
                ? Cell(coordinate, cell.y)
                : Cell(cell.x, coordinate);
            final distance = (end.x - cell.x).abs() + (end.y - cell.y).abs();
            pieces.add(
              LinearPiece(
                u.id,
                n + 1,
                cell,
                end,
                startTimeUnits: time,
                endTimeUnits: time + distance,
              ),
            );
            time += distance;
            cell = end;
            ends.add(end);
          }
          routes.add(UnitRoute(u.id, ends));
        }
        String key(List<CollisionEvent> e) => e
            .map((c) => '${c.globalTime}|${c.position.toJson()}|${c.unitIds}')
            .join(';');
        expect(
          key(earliestTemporalCollisions(pieces, level.goal)),
          key(oracleCollisions(level, routes)),
          reason: 'trial=$trial',
        );
      }
    },
  );
}
