import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_ui_theme.dart';

abstract final class AppUiSystemBars {
  static const legacyNavigationBackground = Color(0xFF000000);
  static SystemUiOverlayStyle forPalette(AppUiPalette palette,
      {required bool supportsDarkNavigationIcons}) {
    final dark = palette.brightness == Brightness.dark;
    return withBlackNavigation(
        (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: palette.background));
  }

  /// Android system controls remain distinct from the app's bottom tabs.
  static SystemUiOverlayStyle withBlackNavigation(SystemUiOverlayStyle style) =>
      style.copyWith(
          systemNavigationBarColor: legacyNavigationBackground,
          systemNavigationBarDividerColor: legacyNavigationBackground,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false);
}
