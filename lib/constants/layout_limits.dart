import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Legacy phone breakpoint, not a limit on the application's painted width.
const double kAppMaxContentWidth = 500.0;

/// ScreenUtil scale only; UI MediaQuery keeps the actual window dimensions.
/// Ordinary phone size, textScaler and insets are preserved.
MediaQueryData appContentMediaQuery(MediaQueryData window) => window.copyWith(
      size: window.size.width <= kAppMaxContentWidth
          ? window.size
          : Size(400, math.min(window.size.height, 850)),
    );

enum AppLayoutKind { phone, shortCover, widePortrait, wideSquare }

/// Classify the window before keyboard/safe-area subtraction. A keyboard must
/// never turn an ordinary phone into a short fold cover.
class AppLayout {
  const AppLayout(this.window);
  final Size window;

  factory AppLayout.of(BuildContext context) =>
      AppLayout(MediaQuery.sizeOf(context));

  AppLayoutKind get kind {
    if (isWide) {
      return window.aspectRatio >= 0.85
          ? AppLayoutKind.wideSquare
          : AppLayoutKind.widePortrait;
    }
    // Excludes 320x568, 360x640 and 480x800 bar-phone reference sizes.
    // Actual Fold dp values still need confirmation on SRTL.
    if (window.width >= 380 &&
        window.height <= 800 &&
        window.height > window.width &&
        window.aspectRatio >= 0.61) {
      return AppLayoutKind.shortCover;
    }
    return AppLayoutKind.phone;
  }

  bool get isWide => window.width > kAppMaxContentWidth;
  // Long fold covers need the same bounded calendar and keyboard handling.
  // Use the full window, never the keyboard-reduced viewport or model name.
  bool get isTallCover =>
      window.width >= 320 &&
      window.width <= kAppMaxContentWidth &&
      window.aspectRatio <= 0.45;
  bool get usesBoundedCalendar => isWide || isShortCover || isTallCover;
  bool get isBalancedInner =>
      window.shortestSide > kAppMaxContentWidth &&
      window.shortestSide / window.longestSide >= 0.85;
  bool get isShortCover => kind == AppLayoutKind.shortCover;
  bool get isSquare => kind == AppLayoutKind.wideSquare;
  double get formWidth => math.min(window.width - 32, isSquare ? 840 : 720);
  double get dialogWidth => math.min(window.width - 48, isSquare ? 680 : 600);
  double get sheetWidth => math.min(window.width - 24, isSquare ? 840 : 720);
}
