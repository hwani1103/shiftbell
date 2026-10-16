import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/app_ui_color_math.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';

void main() {
  test('six choices share readable roles and complete Material colors', () {
    expect(AppUiTimeTheme.values.length, 6);
    expect(AppUiTimeTheme.night.palette.background, const Color(0xFF1A1F2E));
    expect(AppUiTimeTheme.originalWhite.palette.background, Colors.white);
    for (final theme in AppUiTimeTheme.values) {
      final p = theme.palette;
      final material = AppUiTheme.withPalette(ThemeData(), p).colorScheme;
      expect(material.surfaceVariant, p.soft);
      expect(material.surfaceContainerHighest, p.soft);
      expect(material.background, p.background);
      expect(material.onBackground, p.text);
      for (final pair in [
        (p.text, p.background),
        (p.secondaryText, p.soft),
        (p.chipText, p.chipSurface),
        (p.selectionOutline, p.chipSurface),
        (material.onError, material.error),
        (material.onErrorContainer, material.errorContainer),
        (material.onTertiary, material.tertiary),
        (material.onInverseSurface, material.inverseSurface),
      ]) {
        expect(AppUiColorMath.contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: theme.name);
      }
      expect(AppUiColorMath.contrast(p.chipBorder, p.chipSurface),
          greaterThanOrEqualTo(3),
          reason: theme.name);
      expect(AppUiColorMath.contrast(p.disabledText, p.disabledSurface),
          greaterThanOrEqualTo(3),
          reason: theme.name);
    }
  });

  test('changing only the seed adapts light, dark and mid-tone palettes', () {
    for (final hue in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]) {
      for (final lightness in [.08, .25, .42, .55, .75, .95]) {
        final seed = HSLColor.fromAHSL(1, hue, .35, lightness).toColor();
        final p = AppUiPalette.fromSeed(seed);
        expect(p.background, seed);
        for (final background in [p.background, p.surface, p.soft]) {
          for (final ink in [
            p.text,
            p.secondaryText,
            p.primary,
            p.selectionOutline
          ]) {
            expect(AppUiColorMath.contrast(ink, background),
                greaterThanOrEqualTo(4.5),
                reason: '$hue/$lightness');
          }
        }
      }
    }
    final before = AppUiPalette.blue;
    final after = AppUiPalette.fromSeed(const Color(0xFFECF8F7));
    expect(after.surface, isNot(before.surface));
    expect(after.primary, isNot(before.primary));
    expect(after.text, isNot(before.text));
    expect(after.border, isNot(before.border));
    expect(after.selectionOutline, isNot(before.selectionOutline));
  });
}
