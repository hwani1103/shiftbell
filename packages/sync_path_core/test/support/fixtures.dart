import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';

const designPath = '../../docs/next_version_27이후/game_design_v1';
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('$designPath/$name').readAsStringSync())
        as Map<String, dynamic>;
Cell cell(dynamic json) => Cell(json[0] as int, json[1] as int);
Rational fraction(dynamic json) => Rational(json[0] as int, json[1] as int);
RationalPoint point(dynamic json) =>
    RationalPoint(fraction(json[0]), fraction(json[1]));
List<UnitRoute> routes(dynamic json) => [
  for (final route in json)
    UnitRoute(route['unitId'] as String, [
      for (final end in route['endpoints']) cell(end),
    ]),
];
LevelPack pilotPack() => const LevelParser()
    .parsePack(File('$designPath/08_pilot_levels.json').readAsStringSync())
    .value!;
LevelSpec openLevel({
  Cell goal = const Cell(4, 4),
  List<UnitSpec>? units,
  int maxCommands = 3,
  List<String>? rows,
}) => LevelSpec(
  identity: const LevelIdentity('test-pack', 'test-level', 1, supportedRuleSet),
  map: GridMap(width: 5, height: 5, rows: rows ?? List.filled(5, '.....')),
  goal: goal,
  units: units ?? const [UnitSpec('A', Cell(0, 0)), UnitSpec('B', Cell(4, 0))],
  maxCommands: maxCommands,
);
Map<String, dynamic> levelJson() => {
  'schemaVersion': 1,
  'ruleSetId': supportedRuleSet,
  'id': 'test-level',
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
  'maxCommands': 3,
  'requiredMechanics': supportedMechanics.toList(),
};
