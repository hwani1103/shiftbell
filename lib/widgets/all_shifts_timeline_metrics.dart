import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_ui_theme.dart';
import 'app_shift_chip.dart';
import 'shift_chip_label.dart';
import 'shift_label_layout.dart';

/// Two bounded sizes for the restored rounded timeline. Long labels can only
/// expand to the previous short-label cell size, then shrink to fit that size.
abstract final class AllShiftsTimelineMetrics {
  static const compactScale = .94;
  static const labelFontScale = 1.08;
  static const minimumCompactLabelScale = .92;
  static const cellPadding = 2.0;
  static const cellGap = 1.3;

  /// Fill the viewport with complete dates, keeping the preferred chip size
  /// separate from the distance between columns. Rounding avoids dropping an
  /// almost complete eighth column because of padding or fractional pixels.
  static double fittedColumnWidth(double viewportWidth, double preferredWidth) {
    final count = (viewportWidth / preferredWidth).round().clamp(1, 31);
    return viewportWidth / count;
  }

  static ShiftCellMetrics measure(BuildContext context, Iterable<String> names,
      TextStyle style, TextScaler scaler) {
    final expanded = ShiftCellMetrics.forNames(const ['가나'], style, scaler,
        minWidth: 40.w, minHeight: 36.h);
    final compactWidth = expanded.width * compactScale;
    final compactHeight = expanded.height * compactScale;
    final inset = 2 * (cellGap.w + cellPadding + AppShiftChip.denseBorderWidth);
    final available = Size(compactWidth - inset, compactHeight - inset);
    final large = names.toSet().any((name) {
      final measured = ShiftChipLabel.fit(context, name,
              density: AppChipSize.compact,
              available: Size.infinite,
              fontScale: labelFontScale)
          .size;
      return ShiftChipMetrics.fitRatio(measured, available) <
          minimumCompactLabelScale;
    });
    return ShiftCellMetrics(large ? expanded.width : compactWidth,
        large ? expanded.height : compactHeight, large);
  }
}
