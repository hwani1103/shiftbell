import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_lab/game_audio.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sync_paths/effects');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('Host forwards all six effects and stop after initialization', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final audio = GameAudio();
    audio.play(GameSound.route);
    expect(calls, isEmpty);
    await audio.initialize();
    for (final sound in GameSound.values) {
      audio.play(sound);
    }
    audio.stop();
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), [
      'initialize',
      ...List.filled(6, 'play'),
      'stop',
    ]);
    expect(
      calls.skip(1).take(6).map((c) => c.arguments),
      GameSound.values.map((s) => s.name),
    );
  });
  test('Unavailable audio does not interrupt the game', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'audio_unavailable');
    });
    final audio = GameAudio();
    await audio.initialize();
    audio.play(GameSound.start);
    audio.stop();
  });
}
