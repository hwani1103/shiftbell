import 'package:flutter/material.dart';
import '../models/calendar_theme.dart';
import 'app_ui_theme.dart';
import 'app_ui_color_math.dart';

/// Rebuild with frame to restore UI30, or legacy to restore the original
/// calendar presentation. Neither option changes saved schedules or colors.
abstract final class CalendarThemeRollout {
  static const mode =
      String.fromEnvironment('CALENDAR_THEME_MODE', defaultValue: 'reading');
  static bool get frameEnabled => mode != 'legacy';
  // Main dark always keeps its original colors, regardless of screen colors.
  // Keep its original backdrop, ink and controls independent of screen colors.
  static bool preservesOriginalAppearance(CalendarThemeId theme) {
    return theme == CalendarThemeId.mainDark;
  }

  static bool usesReading(CalendarThemeId theme, {bool preview = false}) =>
      mode == 'reading' && !preview && !preservesOriginalAppearance(theme);
}

/// All contrast decisions use the final painted background, including alpha.
abstract final class CalendarContrast {
  static const textMinimum = 4.5;
  static const boundaryMinimum = 3.0;
  static const outlineWidth = 1.0;
  static double ratio(Color a, Color b) => AppUiColorMath.contrast(a, b);
  static Color ink(Color background) => AppUiColorMath.ink(background);
  static Color ensure(Color preferred, Color background,
          [double minimum = textMinimum]) =>
      AppUiColorMath.readable(
          Color.alphaBlend(preferred, background), [background],
          minimum: minimum);

  // Secondary date information stays softer than the normal date numeral.
  static Color lunarInk(Color dateInk, Color surface) =>
      ensure(Color.lerp(dateInk, surface, .25)!, surface);

  static Color chipInk(Color chip, Color surface) =>
      ink(Color.alphaBlend(chip, surface));
  static Border? chipOutline(Color chip, Color surface) {
    final painted = Color.alphaBlend(chip, surface);
    if (ratio(painted, surface) >= boundaryMinimum) return null;
    // Pick an edge visible on BOTH sides, rather than against the cell alone.
    double score(Color c) {
      final a = ratio(c, painted), b = ratio(c, surface);
      return a < b ? a : b;
    }

    final color = score(Colors.black) >= score(Colors.white)
        ? Colors.black
        : Colors.white;
    return _PaintOnlyChipBorder(color, outlineWidth);
  }
}

/// An adaptive edge must never steal label space or change the fitted font.
class _PaintOnlyChipBorder extends Border {
  _PaintOnlyChipBorder(Color color, double width)
      : super.fromBorderSide(BorderSide(color: color, width: width));
  @override
  EdgeInsets get dimensions => EdgeInsets.zero;
}

/// One calendar backdrop with conservative text roles. Design geometry and
/// saved shift chip appearance stay independent of the runtime background.
class CalendarReadingPalette {
  CalendarReadingPalette(AppUiPalette palette,
      {required bool dark, CalendarThemeId? design}) {
    surface = palette.background;
    text = CalendarContrast.ink(surface);
    today = text;
    onToday = CalendarContrast.ink(today);
    todayHoliday = redOn(today);
    selection = text;
    selectedSurface = surface;
    muted = text;
    lunar = CalendarContrast.lunarInk(text, surface);
    outside = CalendarContrast.ensure(Color.lerp(text, surface, .38)!, surface);
    holiday = redOn(surface);
    memoSurface = surface;
    memoText = text;
    outsideSurface = Color.lerp(surface, text, .07)!;
    darkBand = Color.lerp(surface, Colors.black, .65)!;
    onDarkBand = CalendarContrast.ink(darkBand);
    detailMemoSurface = Color.lerp(surface, text, .09)!;
    detailMemoText = CalendarContrast.ink(detailMemoSurface);
    detailLine =
        CalendarContrast.ensure(text.withValues(alpha: .32), surface, 2.0);
    line = design == CalendarThemeId.boldGrid
        ? CalendarContrast.ensure(text.withValues(alpha: .45), surface, 3)
        : design == CalendarThemeId.editorial
            ? detailLine
            : text.withValues(alpha: .28);
    currentMonthCard = text == Colors.black
        ? Color.lerp(surface, Colors.white, .85)!
        : Color.lerp(surface, text, .08)!;
    outsideMonthCard = Color.lerp(surface, text, .025)!;
    currentMonthCardLine = text.withValues(alpha: .22);
    outsideMonthCardLine = text.withValues(alpha: .12);
  }
  late final Color outsideSurface,
      darkBand,
      onDarkBand,
      detailMemoSurface,
      detailMemoText,
      detailLine;
  Color detailSurface(bool outside) => outside ? outsideSurface : surface;
  Color detailInk(bool outside) => CalendarContrast.ensure(
      outside ? this.outside : text, detailSurface(outside));
  late final Color surface,
      text,
      muted,
      lunar,
      outside,
      holiday,
      today,
      onToday,
      todayHoliday,
      selection,
      selectedSurface,
      memoSurface,
      memoText,
      line,
      currentMonthCard,
      outsideMonthCard,
      currentMonthCardLine,
      outsideMonthCardLine;

  Color cardSurface(bool outside) =>
      outside ? outsideMonthCard : currentMonthCard;
  Color cardLine(bool outside) =>
      outside ? outsideMonthCardLine : currentMonthCardLine;
  Color cardHoliday(bool outside) => redOn(cardSurface(outside));
  Color cardLunar(bool outside) =>
      CalendarContrast.lunarInk(text, cardSurface(outside));

  ColorScheme scheme(ColorScheme original) => original.copyWith(
      brightness: ThemeData.estimateBrightnessForColor(surface),
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceContainerHighest: memoSurface,
      outline: line,
      primary: today,
      onPrimary: onToday,
      secondary: selection);
  Color mosaicSurface(Color shift, {bool outside = false}) {
    final light = text == Colors.black;
    return Color.lerp(outside ? outsideSurface : surface, shift,
        outside ? .07 : (light ? .20 : .25))!;
  }

  Color mosaicChip(Color shift) => Color.lerp(surface, shift, .78)!;

  /// Never blend holiday red towards black/white or a theme accent hue.
  static Color redOn(Color background) {
    const reds = [
      Color(0xFFC62828),
      Color(0xFFD32F2F),
      Color(0xFFEF5350),
      Color(0xFFFF8A80),
      Color(0xFFFFCDD2),
      Color(0xFFB71C1C),
      Color(0xFF100000),
      Color(0xFFFFFDFD)
    ];
    for (final red in reds) {
      if (CalendarContrast.ratio(red, background) >=
          CalendarContrast.textMinimum) {
        return red;
      }
    }
    return reds.reduce((a, b) => CalendarContrast.ratio(a, background) >=
            CalendarContrast.ratio(b, background)
        ? a
        : b);
  }

  static AppUiPalette framePalette(AppUiPalette source) {
    final roles = CalendarReadingPalette(source, dark: false);
    return source.copyWith(
        surface: roles.surface,
        soft: roles.surface,
        text: roles.text,
        secondaryText: roles.text,
        primary: roles.text,
        onPrimary: roles.onToday,
        selectionOutline: roles.selection,
        border: roles.line,
        danger: roles.holiday);
  }

  static CalendarReadingPalette? maybeOf(
          BuildContext context, CalendarThemeId theme,
          {bool preview = false}) =>
      CalendarThemeRollout.usesReading(theme, preview: preview)
          ? CalendarReadingPalette(AppUiPalette.of(context),
              dark: theme == CalendarThemeId.mainDark, design: theme)
          : null;
}
