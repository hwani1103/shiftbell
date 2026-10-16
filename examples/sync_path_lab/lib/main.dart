import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'launch_splash.dart';
import 'game_audio.dart';

const labEnvironment = String.fromEnvironment('SYNC_PATH_LAB_ENV');
bool get allowedLab =>
    kDebugMode && (kIsWeb ? labEnvironment == 'dev' : appFlavor == 'dev');

final class LabProgressStore implements ProgressStore {
  static const key = 'syncPathLab.dev.v6.campaign50gates.progress';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value))
      throw StateError('Game save failed');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!allowedLab) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('DEV debug lab only'))),
      ),
    );
    return;
  }
  final parsed = const LevelParser().parsePack(
    await rootBundle.loadString('assets/pilot_levels.json'),
  );
  if (!parsed.isValid) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Level data could not be loaded')),
        ),
      ),
    );
    return;
  }
  final audio = GameAudio();
  await audio.initialize();
  final controller = GameSessionController(
    parsed.value!,
    LabProgressStore(),
    unlockAllForTesting: false,
    playbackRate: 1.5,
    onSound: audio.play,
    onSilence: audio.stop,
  );
  final visuals = BoardVisuals(
    unit: RollingBallVisual(),
    tile: BlockTileVisual(),
  );
  await controller.initialize();
  final korean = PlatformDispatcher.instance.locale.languageCode == 'ko';
  runApp(
    GameLaunchSplash(
      child: SyncPathGameApp(
        session: controller,
        ownsSession: true,
        showIntro: true,
        visuals: visuals,
        strings: GameStrings(korean: korean),
        onExit: () => SystemNavigator.pop(),
      ),
    ),
  );
}
