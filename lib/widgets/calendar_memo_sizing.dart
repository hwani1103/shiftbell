import 'package:flutter/widgets.dart';

/// Use the unoccluded window, so opening a keyboard cannot enable this policy.
/// Narrow bar/cover screens retain their original memo typography.
abstract final class CalendarMemoSizing {
  /// A compact main cell has two date baselines, never one per memo count.
  /// Reserve the highlighted date's height for every day to keep alignment.
  static double mainDateBottomPadding(
      {required int count,
      required double bodyHeight,
      required double dateHeight,
      required double memoRowHeight,
      required double bottomInset,
      required double gap}) {
    final centeredBottom = (bodyHeight + dateHeight) / 2;
    final twoMemoTop = bodyHeight - bottomInset - 2 * memoRowHeight;
    final threshold = centeredBottom + gap <= twoMemoTop ? 3 : 2;
    if (count < threshold) return 0;
    final threeMemoTop = bodyHeight - bottomInset - 3 * memoRowHeight;
    final lift = centeredBottom + gap - threeMemoTop;
    return lift > 0 ? 2 * lift : 0;
  }

  static bool appliesTo(Size window) =>
      window.width >= 380 && window.aspectRatio >= 0.61;

  /// Balanced inner windows (Ultra, in either orientation). Keep the already
  /// reviewed short Fold cover and wide landscape Fold layout unchanged.
  static bool capsAtShiftSize(Size window) =>
      window.shortestSide > 500 &&
      window.shortestSide / window.longestSide >= 0.85;

  /// Fold cover: one memo uses the old two-memo size; two memos use the
  /// midpoint between the old two- and three-memo sizes. Inner windows retain
  /// their existing policy.
  static double scaleFor(Size window, int count) {
    if (!appliesTo(window)) return 1;
    if (window.width < 600 && window.height > window.width) {
      return switch (count) { 1 => 1.5, 2 => 1.25, _ => 1 };
    }
    return switch (count) { 1 => 2.25, 2 => 1.5, _ => 1 };
  }
}
