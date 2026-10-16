import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

class SyncPathsProgressStore implements ProgressStore {
  static const key = 'shiftbell.syncPaths.progress.v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Game progress could not be saved');
    }
  }
}

class SyncPathsAudio {
  static const channel = MethodChannel('sync_paths/effects');
  bool _ready = false, _disposed = false;
  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('initialize');
      if (!_disposed) _ready = true;
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  void play(GameSound sound) {
    if (_ready && !_disposed) unawaited(_invoke('play', sound.name));
  }

  void stop() {
    if (_ready && !_disposed) unawaited(_invoke('stop'));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_invoke('release'));
    }
  }

  Future<void> _invoke(String method, [String? value]) async {
    try {
      await channel.invokeMethod<void>(method, value);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}
