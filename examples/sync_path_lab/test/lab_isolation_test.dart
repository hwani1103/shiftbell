import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import '../lib/main.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Procedural host starts without atlas assets or the full font',
    () async {
      final visuals = BoardVisuals(unit: RollingBallVisual());
      expect(visuals.unit.animated, isTrue);
      final uiSpec = File(
        '../../packages/sync_path_ui/pubspec.yaml',
      ).readAsStringSync();
      expect(uiSpec, isNot(contains('assets/art/')));
      expect(uiSpec, isNot(contains('assets/fonts/NotoSansKR.ttf')));
      expect(uiSpec, contains('assets/fonts/GameSansSubset.ttf'));
      visuals.dispose();
    },
  );
  test(
    'only independent devDebug application ID and no app service dependencies',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('dev.shiftbell.experiments.sync_path_lab'));
      expect(gradle, contains('applicationIdSuffix = ".dev"'));
      expect(gradle, contains('variant.buildType == "debug"'));
      expect(
        gradle,
        contains('variant.productFlavors.any { it.second == "dev" }'),
      );
      expect(gradle, isNot(contains('create("prod")')));
      expect(LabProgressStore.key, startsWith('syncPathLab.dev.'));
      expect(allowedLab, isFalse);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('assets/pilot_copy.json')),
      );
      final runtime = Directory(
        'assets',
      ).listSync().whereType<File>().map((f) => f.path).toList();
      expect(runtime.length, 2);
      expect(
        runtime.any((p) => p.contains('certificate') || p.contains('fixture')),
        isFalse,
      );
      final pack = const LevelParser()
          .parsePack(File('assets/pilot_levels.json').readAsStringSync())
          .value!;
      expect(pack.levels.length, 100);
      final copy =
          jsonDecode(File('assets/pilot_copy.json').readAsStringSync()) as Map;
      expect(
        copy.keys.toSet(),
        pack.levels.map((l) => l.identity.levelId).toSet(),
      );
      for (final entry in copy.values) {
        expect(entry['hintsKo'].length, 3);
        expect(entry['hintsEn'].length, 3);
      }
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('uses-permission')));
      expect(manifest, isNot(contains('service')));
    },
  );
}
