import 'package:flutter/material.dart';
import 'app_ui_theme.dart';

/// Device-local time slots; manual selection bypasses the clock entirely.
enum AppUiTimeTheme {
  dawn,
  morning,
  daytime,
  evening,
  night,
  originalWhite;

  static const clockCheckInterval = Duration(minutes: 1);
  static AppUiTimeTheme forLocalTime(DateTime time) {
    final hour = time.toLocal().hour;
    if (hour >= 5 && hour < 8) return dawn;
    if (hour >= 8 && hour < 11) return morning;
    if (hour >= 11 && hour < 17) return daytime;
    if (hour >= 17 && hour < 21) return evening;
    return night;
  }

  AppUiPalette get palette => switch (this) {
        dawn => AppUiTimePalettes.dawn,
        morning => AppUiTimePalettes.morning,
        daytime => AppUiPalette.blue,
        evening => AppUiTimePalettes.evening,
        night => AppUiTimePalettes.night,
        originalWhite => AppUiTimePalettes.originalWhite,
      };
}

/// Change one anchor per period; all role colors use the shared generator.
abstract final class AppUiTimePalettes {
  static final dawn = AppUiPalette.fromSeed(const Color(0xFFEDEDF8));
  static final morning = AppUiPalette.fromSeed(const Color(0xFFECF8F7));
  static final evening = AppUiPalette.fromSeed(const Color(0xFF354B67));
  // The fifth automatic period is also the fixed Dark choice.
  static final night = AppUiPalette.fromSeed(const Color(0xFF1A1F2E));
  static final originalWhite =
      AppUiPalette.fromSeed(AppUiPalette.blueSeed, white: true);
}
