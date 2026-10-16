import 'dart:convert';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:test/test.dart';
import 'support/fixtures.dart';

void main() {
  test(
    'Sixteen commands round-trip through parser, validator and constant-speed engine',
    () {
      final data = levelJson();
      data['ruleSetId'] = constantSpeedRuleSet;
      data['maxCommands'] = 16;
      final parsed = const LevelParser().parseLevel(
        jsonEncode(data),
        packId: 'test-pack',
      );
      expect(parsed.isValid, true);
      final l = parsed.value!;
      final r = UnitRoute('A', [
        for (var i = 0; i < 14; i++) Cell(i.isEven ? 1 : 0, 0),
        const Cell(0, 4),
        const Cell(4, 4),
      ]);
      final plan = RoutePlan(l.identity, [
        r,
        UnitRoute('B', const [Cell(4, 4)]),
      ]);
      final restored = const LevelParser().parsePlan(
        jsonEncode({
          'levelIdentity': l.identity.toJson(),
          'routeRevision': 0,
          'routes': plan.routes.map((r) => r.toJson()).toList(),
        }),
      );
      expect(restored.isValid, true);
      expect(restored.value!.routes.first.endpoints.length, 16);
      expect(
        const RouteValidator().validateRoute(l, l.units.first, r).isValid,
        true,
      );
      expect(
        const SimulationEngine().simulate(l, plan),
        isA<SimulationTrace>(),
      );
    },
  );
  test('Above sixteen commands remains bounded at both JSON boundaries', () {
    final data = levelJson()..['maxCommands'] = 17;
    expect(
      const LevelParser().parseLevel(jsonEncode(data), packId: 'p').isValid,
      false,
    );
    final l = pilotPack().levels.first;
    expect(
      const LevelParser()
          .parsePlan(
            jsonEncode({
              'levelIdentity': l.identity.toJson(),
              'routeRevision': 0,
              'routes': [
                {
                  'unitId': 'A',
                  'endpoints': List.filled(17, [0, 1]),
                },
              ],
            }),
          )
          .isValid,
      false,
    );
  });
}
