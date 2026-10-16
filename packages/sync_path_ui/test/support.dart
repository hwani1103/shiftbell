import 'dart:convert';
import 'dart:io';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

const designPath = '../../docs/next_version_27이후/game_design_v1';
LevelPack pilot() => const LevelParser()
    .parsePack(File('$designPath/08_pilot_levels.json').readAsStringSync())
    .value!;
Map<String, dynamic> certificates() =>
    jsonDecode(
          File('$designPath/09_pilot_certificates.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
List<UnitRoute> fromJson(dynamic data) => [
  for (final r in data)
    UnitRoute(r['unitId'] as String, [
      for (final e in r['endpoints']) Cell(e[0] as int, e[1] as int),
    ]),
];
Future<GameSessionController> session(int i, {ProgressStore? store}) async {
  final all = pilot();
  final s = GameSessionController(
    LevelPack(all.id, all.revision, [all.levels[i]]),
    store ?? MemoryProgressStore(),
  );
  await s.initialize();
  s.openLevel(0);
  return s;
}

void enter(GameSessionController s, List<UnitRoute> routes) {
  for (final route in routes) {
    s.selectUnit(route.unitId);
    for (final end in route.endpoints) {
      if (!s.append(end)) throw StateError('Invalid fixture input');
    }
  }
}
