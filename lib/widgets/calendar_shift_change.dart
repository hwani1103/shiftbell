import 'package:flutter/material.dart';
import '../models/calendar_theme.dart';
import '../theme/calendar_reading_palette.dart';

/// Original means the pattern's shift, never the previous edit in an edit chain.
class CalendarShiftChangeScope extends InheritedWidget {
  const CalendarShiftChangeScope(
      {super.key,
      required this.originalColor,
      required this.originalInk,
      required super.child});
  final Color? originalColor, originalInk;
  static bool supports(CalendarThemeId theme) => !{
        CalendarThemeId.initialBadge,
        CalendarThemeId.underline,
        CalendarThemeId.editorial,
      }.contains(theme);
  static bool isChanged(String pattern, String actual) =>
      pattern.isNotEmpty &&
      pattern != '미설정' &&
      actual.isNotEmpty &&
      actual != '미설정' &&
      pattern != actual;
  static CalendarShiftChangeScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CalendarShiftChangeScope>();
  @override
  bool updateShouldNotify(CalendarShiftChangeScope oldWidget) =>
      originalColor != oldWidget.originalColor ||
      originalInk != oldWidget.originalInk;
}

/// Both full-size copies use identical layout; clipping changes paint only.
/// A glyph crossing the boundary therefore keeps its shape and gets two inks.
/// The original copy contributes neither semantics nor hit targets.
class CalendarShiftChange extends StatelessWidget {
  const CalendarShiftChange(
      {super.key,
      required this.background,
      required this.foreground,
      required this.builder,
      this.originalBackground,
      this.surface,
      this.deriveOriginalInk = false,
      this.enabled = true});
  static const originalFraction = .20;
  final Color background, foreground;
  final Color? surface;
  final bool enabled;
  final bool deriveOriginalInk;
  final Color Function(Color)? originalBackground;
  final Widget Function(Color background, Color foreground) builder;

  @override
  Widget build(BuildContext context) {
    final change = CalendarShiftChangeScope.of(context);
    final current = builder(background, foreground);
    if (!enabled || change == null || change.originalColor == null)
      return current;
    final oldBackground = originalBackground?.call(change.originalColor!) ??
        change.originalColor!;
    // Preserve each existing chip's ink exactly. Only designs that transform
    // their fill and already derive their own ink (Soft Mosaic) opt in.
    final oldInk = deriveOriginalInk
        ? CalendarContrast.chipInk(oldBackground,
            surface ?? Theme.of(context).colorScheme.surface)
        : change.originalInk!;
    return Stack(fit: StackFit.passthrough, children: [
      ClipRect(clipper: const _ChangeClipper(false), child: current),
      Positioned.fill(
          child: IgnorePointer(
              child: ExcludeSemantics(
                  child: ClipRect(
                      clipper: const _ChangeClipper(true),
                      child: builder(oldBackground, oldInk))))),
    ]);
  }
}

class _ChangeClipper extends CustomClipper<Rect> {
  const _ChangeClipper(this.original);
  final bool original;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
      original ? 0 : size.width * CalendarShiftChange.originalFraction,
      0,
      original ? size.width * CalendarShiftChange.originalFraction : size.width,
      size.height);
  @override
  bool shouldReclip(_ChangeClipper oldClipper) =>
      original != oldClipper.original;
}
