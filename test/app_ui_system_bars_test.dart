import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/providers/app_ui_system_bars_provider.dart';
import 'package:shiftbell/theme/app_ui_system_bars.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all screen colors keep black system navigation with light icons',
      () {
    for (final theme in AppUiTimeTheme.values) {
      final p = theme.palette;
      final modern =
          AppUiSystemBars.forPalette(p, supportsDarkNavigationIcons: true);
      expect(modern.systemNavigationBarColor, Colors.black);
      expect(modern.systemNavigationBarDividerColor, Colors.black);
      expect(modern.systemNavigationBarIconBrightness, Brightness.light);
      expect(modern.systemNavigationBarContrastEnforced, false);
      final old =
          AppUiSystemBars.forPalette(p, supportsDarkNavigationIcons: false);
      expect(old.systemNavigationBarIconBrightness, Brightness.light);
      expect(
          old.systemNavigationBarColor,
          AppUiSystemBars.legacyNavigationBackground);
    }
  });
  test(
      'Android UI capability is read-only and cached, unknown stays conservative',
      () async {
    final original = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = original);
    var calls = 0;
    int? sdk = 36;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, (call) async {
      expect(call.method, 'getPlatformSdkInt');
      calls++;
      return sdk;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, null));
    final container = ProviderContainer();
    expect(
        await container.read(appUiDarkNavigationIconsProvider.future), isTrue);
    expect(
        await container.read(appUiDarkNavigationIconsProvider.future), isTrue);
    expect(calls, 1);
    container.dispose();
    for (final version in <int?>[25, null]) {
      sdk = version;
      final legacy = ProviderContainer();
      expect(
          await legacy.read(appUiDarkNavigationIconsProvider.future), isFalse);
      legacy.dispose();
    }
  });
}
