import 'package:flutter/material.dart';
import 'app_ui_color_math.dart';

/// Typography geometry is independent of the palette. Changing a background
/// or theme replaces color roles, never individual screen TextStyle literals.
enum AppTextRole {
  title,
  toolbar,
  section,
  body,
  supporting,
  progress,
  button,
  chip,
  number,
  chipIndex,
  chipBadge
}

enum AppTextTone {
  normal,
  secondary,
  primary,
  selection,
  chip,
  onPrimary,
  danger,
  error,
  disabled
}

enum AppChipSize { compact, regular, large }

/// Shared size tiers. Semantic text roles select a tier; screens never tune it.
abstract final class AppFontSize {
  static const tiny = 8.0;
  static const meta = 12.0;
  static const body = 14.0;
  static const control = 15.0;
  static const section = 16.0;
  static const toolbar = 18.0;
  static const display = 24.0;
}

abstract final class AppTypography {
  static const _templates = <AppTextRole, TextStyle>{
    AppTextRole.title: TextStyle(
        fontSize: AppFontSize.display,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.35),
    AppTextRole.toolbar: TextStyle(
        fontSize: AppFontSize.toolbar,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.3),
    AppTextRole.section: TextStyle(
        fontSize: AppFontSize.section,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.4),
    AppTextRole.body: TextStyle(
        fontSize: AppFontSize.body,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5),
    AppTextRole.supporting: TextStyle(
        fontSize: AppFontSize.meta,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5),
    AppTextRole.progress: TextStyle(
        fontSize: AppFontSize.body,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.3),
    AppTextRole.button: TextStyle(
        fontSize: AppFontSize.control,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.35),
    AppTextRole.chip: TextStyle(
        fontSize: AppFontSize.body,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.3),
    AppTextRole.chipIndex: TextStyle(
        fontSize: AppFontSize.meta,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1),
    AppTextRole.chipBadge: TextStyle(
        fontSize: AppFontSize.tiny,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1),
    AppTextRole.number: TextStyle(
        fontSize: AppFontSize.display,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.2),
  };
  static TextStyle geometry(AppTextRole role) => _templates[role]!;

  static TextStyle style(BuildContext context, AppTextRole role,
          {AppTextTone tone = AppTextTone.normal}) =>
      _templates[role]!.copyWith(
          color: AppUiPalette.of(context).textColor(tone),
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily);

  static TextStyle chip(BuildContext context, AppChipSize size) =>
      style(context, AppTextRole.chip).copyWith(
          fontSize: switch (size) {
        AppChipSize.compact => 12,
        AppChipSize.regular => 14,
        AppChipSize.large => 16,
      });
}

/// All new UI colors, including ordinary text, belong to semantic roles.
/// Existing calendar/shift colors are separate; migration is screen by screen.
@immutable
class AppUiPalette extends ThemeExtension<AppUiPalette> {
  const AppUiPalette(
      {required this.background,
      required this.surface,
      required this.primary,
      required this.onPrimary,
      required this.soft,
      required this.text,
      required this.secondaryText,
      required this.border,
      required this.danger,
      required this.dangerSurface,
      required this.disabledSurface,
      required this.disabledText,
      required this.selectionOutline,
      required this.chipSurface,
      required this.chipBorder,
      required this.chipText});

  /// One background anchor generates every runtime role. White is an explicit
  /// neutral surface mode; its accent still comes from the same blue anchor.
  factory AppUiPalette.fromSeed(Color seed, {bool white = false}) {
    final background = white ? Colors.white : seed.withAlpha(255);
    final dark = AppUiColorMath.ink(background) == Colors.white;
    final hsl = HSLColor.fromColor(seed);
    Color tone(double lightness, {double hueOffset = 0}) => hsl
        .withHue((hsl.hue + hueOffset) % 360)
        .withSaturation(hsl.saturation.clamp(.38, .65))
        .withLightness(lightness)
        .toColor();
    Color mix(Color a, Color b, double amount) => Color.lerp(a, b, amount)!;
    final accent = tone(dark ? .80 : .36);
    // Mid-tone custom seeds must not push a surface across the text polarity.
    final surfaceTarget = dark && background.computeLuminance() > .14
        ? Colors.black
        : Colors.white;
    final surface = white
        ? Colors.white
        : mix(background, surfaceTarget, dark ? .055 : .72);
    final soft = white ? Colors.white : mix(background, surface, .65);
    final surfaces = [background, surface, soft];
    final text = AppUiColorMath.readable(
        hsl.withSaturation(.20).withLightness(dark ? .96 : .14).toColor(),
        surfaces);
    final primary = AppUiColorMath.readable(accent, surfaces);
    final secondary =
        AppUiColorMath.readable(mix(text, background, .24), surfaces);
    final border = AppUiColorMath.readable(mix(text, background, .55), surfaces,
        minimum: 3);
    final selection = AppUiColorMath.readable(
        tone(dark ? .82 : .38, hueOffset: 60), surfaces);
    // Error red conveys a fixed meaning. Only its tone/surface follow the seed.
    const errorSeed = Color(0xFFC23749);
    final dangerSurface = mix(background, errorSeed, .08);
    final danger = AppUiColorMath.readable(
        HSLColor.fromColor(errorSeed).withLightness(dark ? .82 : .36).toColor(),
        [...surfaces, dangerSurface]);
    final disabledSurface = mix(background, surface, .4);
    return AppUiPalette(
      background: background,
      surface: surface,
      primary: primary,
      onPrimary: AppUiColorMath.ink(primary),
      soft: soft,
      text: text,
      secondaryText: secondary,
      border: border,
      danger: danger,
      dangerSurface: dangerSurface,
      disabledSurface: disabledSurface,
      disabledText: AppUiColorMath.readable(
          mix(text, disabledSurface, .50), [disabledSurface],
          minimum: 3),
      selectionOutline: selection,
      chipSurface: soft,
      chipBorder: border,
      chipText: text,
    );
  }

  static const blueSeed = Color(0xFFDFEDFC);
  static final blue = AppUiPalette.fromSeed(blueSeed);
  final Color background,
      surface,
      primary,
      onPrimary,
      soft,
      text,
      secondaryText,
      border,
      danger,
      dangerSurface,
      disabledSurface,
      disabledText,
      selectionOutline,
      chipSurface,
      chipBorder,
      chipText;

  /// Foreground for a filled destructive-action surface in every palette.
  Color get onDanger => AppUiColorMath.ink(danger);
  Color get success => AppUiColorMath.readable(
      const Color(0xFF2E7D32), [background, surface, soft]);
  Color get warning => AppUiColorMath.readable(
      const Color(0xFFB26A00), [background, surface, soft]);

  /// Native splash branding is deliberately independent of runtime palettes.
  Brightness get brightness => ThemeData.estimateBrightnessForColor(background);

  static AppUiPalette of(BuildContext context) =>
      Theme.of(context).extension<AppUiPalette>() ?? blue;
  Color textColor(AppTextTone tone) => switch (tone) {
        AppTextTone.normal => text,
        AppTextTone.secondary => secondaryText,
        AppTextTone.primary => primary,
        AppTextTone.selection => selectionOutline,
        AppTextTone.chip => chipText,
        AppTextTone.onPrimary => onPrimary,
        AppTextTone.danger || AppTextTone.error => danger,
        AppTextTone.disabled => disabledText,
      };

  @override
  AppUiPalette copyWith(
          {Color? background,
          Color? surface,
          Color? primary,
          Color? onPrimary,
          Color? soft,
          Color? text,
          Color? secondaryText,
          Color? border,
          Color? danger,
          Color? dangerSurface,
          Color? disabledSurface,
          Color? disabledText,
          Color? selectionOutline,
          Color? chipSurface,
          Color? chipBorder,
          Color? chipText}) =>
      AppUiPalette(
        selectionOutline: selectionOutline ?? this.selectionOutline,
        chipSurface: chipSurface ?? soft ?? this.chipSurface,
        chipBorder: chipBorder ?? border ?? this.chipBorder,
        chipText: chipText ?? text ?? this.chipText,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        primary: primary ?? this.primary,
        onPrimary: onPrimary ?? this.onPrimary,
        soft: soft ?? this.soft,
        text: text ?? this.text,
        secondaryText: secondaryText ?? this.secondaryText,
        border: border ?? this.border,
        danger: danger ?? this.danger,
        dangerSurface: dangerSurface ?? this.dangerSurface,
        disabledSurface: disabledSurface ?? this.disabledSurface,
        disabledText: disabledText ?? this.disabledText,
      );
  @override
  AppUiPalette lerp(covariant AppUiPalette? other, double t) {
    if (other == null) return this;
    return AppUiPalette(
      chipSurface: Color.lerp(chipSurface, other.chipSurface, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      chipText: Color.lerp(chipText, other.chipText, t)!,
      selectionOutline:
          Color.lerp(selectionOutline, other.selectionOutline, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      text: Color.lerp(text, other.text, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      border: Color.lerp(border, other.border, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      disabledSurface: Color.lerp(disabledSurface, other.disabledSurface, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
    );
  }
}

abstract final class AppUiMotion {
  static const transition = Duration(milliseconds: 220);
  static const attentionCycle = Duration(milliseconds: 2400);
  static const attentionLowOpacity = .42;
  static const attentionLowScale = .97;
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration transitionDuration(BuildContext context) =>
      reduceMotion(context) ? Duration.zero : transition;
}

abstract final class AppUiMetrics {
  static const dialogInset = 16.0;
  static const dialogRadius = 16.0;
  static const dialogContentInset = 24.0;
  static const dialogContentGap = 20.0;
  static const dialogActionGap = 8.0;
  static const calendarHeaderHeight = 44.0;
  static const calendarHeaderActionExtent = 36.0;
  static const boldGridHeaderInset = 2.0;
  static const calendarIconSize = 18.0;
  static const calendarCompactIconSize = 16.0;
  static const calendarControlPadding = 4.0;
  static const calendarSummaryInset = 10.0;
  static const calendarOutlinedFooterActionHeight = 30.0;
  static const calendarOutlinedFooterGap = 2.0;
  static const calendarCardCellInset = 2.0;
  static const calendarFooterLabelInset = 8.0;
  static const calendarCardRadius = 6.0;
  static const calendarCardWeekdayFontSize = 12.0;
  static const calendarBorderWidth = 1.0;
  static const previewHeight = 60.0;
  static const previewDotSize = 16.0;
  static const previewGap = 6.0;
  static const pagePadding = 20.0;
  static const compactCardPadding = 12.0;
  static const compactButtonHeight = 36.0;
  static const cardRadius = 20.0;
  static const controlRadius = 12.0;
  static const gap = 16.0;
  static const buttonHeight = 48.0;
}

abstract final class AppUiTheme {
  static ThemeData withPalette(ThemeData base, AppUiPalette palette,
      {bool preserveTextGeometry = false}) {
    final templates = AppTypography._templates.map((role, style) => MapEntry(
        role,
        style.copyWith(fontFamily: base.textTheme.bodyMedium?.fontFamily)));
    final coloredText = base.textTheme
        .apply(bodyColor: palette.text, displayColor: palette.text);
    // Legacy calendar measurements inherit text geometry above their Scaffold.
    // A frame palette must not change those metrics or the bottom tab height.
    final textTheme = preserveTextGeometry
        ? coloredText
        : coloredText.copyWith(
            titleLarge:
                templates[AppTextRole.toolbar]!.copyWith(color: palette.text),
            titleMedium:
                templates[AppTextRole.section]!.copyWith(color: palette.text),
            bodyLarge:
                templates[AppTextRole.body]!.copyWith(color: palette.text),
            bodyMedium:
                templates[AppTextRole.body]!.copyWith(color: palette.text),
            bodySmall: templates[AppTextRole.supporting]!
                .copyWith(color: palette.secondaryText),
            labelLarge:
                templates[AppTextRole.button]!.copyWith(color: palette.text),
          );
    return base.copyWith(
      brightness: palette.brightness,
      scaffoldBackgroundColor: palette.background,
      colorScheme: base.colorScheme.copyWith(
          brightness: palette.brightness,
          primaryContainer: palette.soft,
          onPrimaryContainer: palette.text,
          secondaryContainer: palette.soft,
          onSecondaryContainer: palette.text,
          surfaceContainerLowest: palette.background,
          surfaceContainerLow: palette.surface,
          surfaceContainer: palette.surface,
          surfaceContainerHigh: palette.soft,
          surfaceContainerHighest: palette.soft,
          // Legacy controls still read these aliases. copyWith otherwise keeps
          // the original light scheme's explicit values in a dark palette.
          surfaceVariant: palette.soft,
          background: palette.background,
          onBackground: palette.text,
          surfaceTint: palette.primary,
          outlineVariant: palette.border,
          primary: palette.primary,
          onPrimary: palette.onPrimary,
          secondary: palette.primary,
          onSecondary: palette.onPrimary,
          tertiary: palette.selectionOutline,
          onTertiary: AppUiColorMath.ink(palette.selectionOutline),
          tertiaryContainer: palette.soft,
          onTertiaryContainer: palette.text,
          inverseSurface: palette.text,
          onInverseSurface: palette.surface,
          inversePrimary: palette.surface,
          errorContainer: palette.dangerSurface,
          onErrorContainer: palette.danger,
          surface: palette.surface,
          onSurface: palette.text,
          onSurfaceVariant: palette.secondaryText,
          outline: palette.border,
          error: palette.danger,
          onError: AppUiColorMath.ink(palette.danger)),
      extensions: [
        ...base.extensions.values.where((e) => e is! AppUiPalette),
        palette
      ],
      textTheme:
          textTheme.apply(fontFamily: base.textTheme.bodyMedium?.fontFamily),
      appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: palette.background,
          foregroundColor: palette.text,
          titleTextStyle: textTheme.titleLarge,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
          scrolledUnderElevation: 0),
      iconTheme: IconThemeData(color: palette.secondaryText),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
          backgroundColor: palette.background,
          selectedItemColor: palette.primary,
          unselectedItemColor: palette.secondaryText,
          elevation: 0),
      cardTheme: base.cardTheme.copyWith(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUiMetrics.cardRadius),
            side: BorderSide(color: palette.border)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppUiMetrics.cardRadius))),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        tileColor: palette.surface,
        iconColor: palette.primary,
        textColor: palette.text,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppUiMetrics.gap, vertical: 4),
        titleTextStyle:
            templates[AppTextRole.button]!.copyWith(color: palette.text),
        subtitleTextStyle: templates[AppTextRole.supporting]!
            .copyWith(color: palette.secondaryText),
      ),
      dividerTheme:
          base.dividerTheme.copyWith(color: palette.border, thickness: 1),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: palette.primary),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
              disabledBackgroundColor: palette.disabledSurface,
              disabledForegroundColor: palette.disabledText,
              minimumSize: const Size(0, AppUiMetrics.buttonHeight),
              textStyle: templates[AppTextRole.button],
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppUiMetrics.controlRadius)))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
              disabledBackgroundColor: palette.disabledSurface,
              disabledForegroundColor: palette.disabledText,
              elevation: 0,
              minimumSize: const Size(0, AppUiMetrics.buttonHeight),
              textStyle: templates[AppTextRole.button],
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppUiMetrics.controlRadius)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              side: BorderSide(color: palette.border),
              textStyle: templates[AppTextRole.button],
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppUiMetrics.controlRadius)))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: palette.primary,
              disabledForegroundColor: palette.disabledText,
              textStyle: templates[AppTextRole.button],
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppUiMetrics.controlRadius)))),
      datePickerTheme: DatePickerThemeData(
          backgroundColor: palette.surface,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: palette.soft,
          headerForegroundColor: palette.text,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppUiMetrics.cardRadius))),
      timePickerTheme: TimePickerThemeData(
          backgroundColor: palette.surface,
          hourMinuteColor: palette.soft,
          hourMinuteTextColor: palette.text,
          dialBackgroundColor: palette.soft,
          dialHandColor: palette.primary,
          entryModeIconColor: palette.primary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppUiMetrics.cardRadius))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        labelStyle: textTheme.bodyMedium,
        floatingLabelStyle:
            textTheme.bodyMedium?.copyWith(color: palette.primary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.secondaryText),
        helperStyle: textTheme.bodySmall,
        helperMaxLines: 3,
        errorStyle: textTheme.bodySmall?.copyWith(color: palette.danger),
        errorMaxLines: 3,
        counterStyle: textTheme.bodySmall,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppUiMetrics.controlRadius),
            borderSide: BorderSide(color: palette.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppUiMetrics.controlRadius),
            borderSide: BorderSide(color: palette.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppUiMetrics.controlRadius),
            borderSide: BorderSide(color: palette.primary, width: 2)),
      ),
      dialogTheme: DialogThemeData(
          backgroundColor: palette.surface,
          titleTextStyle: textTheme.titleMedium,
          contentTextStyle: textTheme.bodyMedium,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppUiMetrics.cardRadius))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppUiMetrics.controlRadius)),
          actionTextColor: palette.surface,
          backgroundColor: palette.text,
          contentTextStyle:
              templates[AppTextRole.body]!.copyWith(color: palette.surface)),
    );
  }
}
