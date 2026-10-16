import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

/// Android host adapter. The reusable game emits events without platform code.
final class GameAudio {
  static const _channel = MethodChannel('sync_paths/effects');
  bool _ready = false;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('initialize');
      _ready = true;
    } on PlatformException catch (_) {
      // Sound failure must never prevent play.
    } on MissingPluginException catch (_) {}
  }

  void play(GameSound sound) {
    if (_ready) _invoke('play', sound.name);
  }

  void stop() {
    if (_ready) _invoke('stop');
  }

  Future<void> _invoke(String method, [String? value]) async {
    try {
      await _channel.invokeMethod<void>(method, value);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}
