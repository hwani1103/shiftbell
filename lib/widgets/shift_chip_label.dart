import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_ui_theme.dart';

typedef _ChipFit = ({TextStyle style, Size size, Rect bounds});
typedef _ChipFitKey = ({
  String label,
  TextStyle style,
  Size available,
  TextDirection direction,
  Locale? locale
});

/// Screen-owned, bounded measurement reuse. No render objects or contexts are held.
class ShiftChipFitCache {
  static const capacity = 128;
  final _entries = <_ChipFitKey, _ChipFit>{};
  void clear() => _entries.clear();
  _ChipFit? _read(_ChipFitKey key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void _write(_ChipFitKey key, _ChipFit value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }
}

class ShiftChipFitCacheScope extends InheritedWidget {
  const ShiftChipFitCacheScope(
      {super.key, required this.cache, required super.child});
  final ShiftChipFitCache cache;
  static ShiftChipFitCache? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ShiftChipFitCacheScope>()
      ?.cache;
  @override
  bool updateShouldNotify(ShiftChipFitCacheScope oldWidget) =>
      cache != oldWidget.cache;
}

/// One sizing contract for every shift-name chip, including bounded calendar
/// cells. Containers reserve padding first; names use the remaining space.
abstract final class ShiftChipMetrics {
  static const regularMaxWidth = 112.0;
  static const compactMaxWidth = 88.0;
  static const regularHorizontalPadding = 12.0;
  static const compactHorizontalPadding = 6.0;
  static const verticalPadding = 6.0;
  static const teamSpacing = 6.0;
  static double indexInset(double chipHeight) => chipHeight * .34;
  static const lineHeight = 1.15;
  static double maxFontSize(AppChipSize size) => switch (size) {
        AppChipSize.compact => AppFontSize.body,
        AppChipSize.regular => AppFontSize.section,
        AppChipSize.large => AppFontSize.toolbar,
      };
  static double fitRatio(Size measured, Size available) => math.min(
      1.0,
      math.min(
          available.width.isFinite
              ? math.max(0, available.width) / math.max(1, measured.width)
              : 1.0,
          available.height.isFinite
              ? math.max(0, available.height) / math.max(1, measured.height)
              : 1.0));
}

/// Ratios refer to the complete colored chip, before any text-only padding.
class ShiftChipProportions {
  const ShiftChipProportions(
      {required this.heightFraction, required this.horizontalInsetFraction});
  final double heightFraction;
  final double horizontalInsetFraction;
  static const calendarReview =
      ShiftChipProportions(heightFraction: .80, horizontalInsetFraction: .05);
  static const eventCalendar =
      ShiftChipProportions(heightFraction: .90, horizontalInsetFraction: .05);
  static const diaryCalendar =
      ShiftChipProportions(heightFraction: .70, horizontalInsetFraction: .05);
}

/// Without an explicit ratio, short names use the preset maximum. Longer names shrink continuously using
/// actual glyph measurement, never character-count tiers or ellipsis.
class ShiftChipLabel extends StatelessWidget {
  const ShiftChipLabel(
      {super.key,
      required this.label,
      this.color,
      this.size = AppChipSize.regular,
      this.textKey,
      this.proportions,
      this.fontScale = 1});
  final String label;
  final Color? color;
  final AppChipSize size;
  final Key? textKey;
  final ShiftChipProportions? proportions;
  final double fontScale;
  static ({TextStyle style, Size size, Rect bounds}) fit(
      BuildContext context, String label,
      {required AppChipSize density,
      required Size available,
      ShiftChipProportions? proportions,
      double fontScale = 1}) {
    if (proportions != null) {
      available = Size(
          available.width * (1 - 2 * proportions.horizontalInsetFraction),
          available.height * proportions.heightFraction);
    }
    final style = DefaultTextStyle.of(context)
        .style
        .merge(AppTypography.style(context, AppTextRole.chip))
        .copyWith(
            fontSize: ShiftChipMetrics.maxFontSize(density) * fontScale,
            height: ShiftChipMetrics.lineHeight);
    final cache = ShiftChipFitCacheScope.of(context);
    final key = (
      label: label,
      style: style,
      available: available,
      direction: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context)
    );
    final cached = cache?._read(key);
    if (cached != null) return cached;
    final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        textScaler: TextScaler.noScaling,
        maxLines: 1)
      ..layout();
    var fontSize = style.fontSize!;
    if (proportions != null && available.height.isFinite) {
      fontSize *= math.max(0, available.height) / math.max(.01, painter.height);
      painter.text =
          TextSpan(text: label, style: style.copyWith(fontSize: fontSize));
      painter.layout();
    }
    bool fits() =>
        (!available.width.isFinite || painter.width <= available.width) &&
        (!available.height.isFinite || painter.height <= available.height);
    if (!fits()) {
      var low = .01;
      var high = fontSize;
      for (var i = 0; i < 14; i++) {
        final candidate = (low + high) / 2;
        painter.text =
            TextSpan(text: label, style: style.copyWith(fontSize: candidate));
        painter.layout();
        if (fits()) {
          low = candidate;
        } else {
          high = candidate;
        }
      }
      fontSize = low;
      painter.text =
          TextSpan(text: label, style: style.copyWith(fontSize: fontSize));
      painter.layout();
    }
    final measured = painter.size;
    final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length));
    final bounds = boxes.isEmpty
        ? Offset.zero & measured
        : boxes
            .map((box) => box.toRect())
            .reduce((a, b) => a.expandToInclude(b));
    painter.dispose();
    final result = (
      style: style.copyWith(fontSize: fontSize),
      size: measured,
      bounds: bounds
    );
    cache?._write(key, result);
    return result;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final fitted = fit(context, label,
            density: size,
            available: box.biggest,
            proportions: proportions,
            fontScale: fontScale);
        return Center(
            child: Text(label,
                key: textKey,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: fitted.style
                    .copyWith(color: color ?? AppUiPalette.of(context).text),
                maxLines: 1,
                softWrap: false));
      });
}

/// Uses the same measured name geometry as ShiftChipLabel. The index grows to
/// its semantic tier only when it fits beside or above the centred name.
class ShiftChipIndex extends StatelessWidget {
  const ShiftChipIndex(
      {super.key,
      required this.index,
      required this.name,
      required this.chipSize,
      required this.available,
      required this.color,
      this.team,
      this.hasDelete = false});
  final int index;
  final String name;
  final AppChipSize chipSize;
  final Size available;
  final Color color;
  final String? team;
  final bool hasDelete;
  static const topInset = 2.0;
  static const nameGap = .5;
  @override
  Widget build(BuildContext context) {
    final horizontal = chipSize == AppChipSize.compact
        ? ShiftChipMetrics.compactHorizontalPadding
        : ShiftChipMetrics.regularHorizontalPadding;
    final deleteWidth = hasDelete ? AppUiMetrics.buttonHeight : 0.0;
    var teamWidth = 0.0;
    var teamHeight = 0.0;
    if (team != null) {
      final painter = TextPainter(
          text: TextSpan(
              text: team,
              style: AppTypography.style(context, AppTextRole.chip)),
          textDirection: Directionality.of(context),
          locale: Localizations.maybeLocaleOf(context),
          textScaler: TextScaler.noScaling)
        ..layout();
      teamWidth = painter.width;
      teamHeight = painter.height;
      painter.dispose();
    }
    final teamSpace =
        team == null ? 0.0 : teamWidth + ShiftChipMetrics.teamSpacing;
    final labelWidth = math.max(
        0.0, available.width - horizontal * 2 - teamSpace - deleteWidth);
    final fitted = ShiftChipLabel.fit(context, name,
        density: chipSize,
        available: Size(
            labelWidth,
            math.max(
                0, available.height - ShiftChipMetrics.verticalPadding * 2)));
    final protected = [
      fitted.bounds
          .shift(Offset(
              horizontal + teamSpace + (labelWidth - fitted.size.width) / 2,
              (available.height - fitted.size.height) / 2))
          .inflate(nameGap),
      if (team != null)
        Rect.fromLTWH(horizontal, (available.height - teamHeight) / 2,
                teamWidth, teamHeight)
            .inflate(nameGap),
      if (hasDelete)
        Rect.fromLTWH(available.width - horizontal - deleteWidth, 0,
            deleteWidth, available.height),
    ];
    final left = ShiftChipMetrics.indexInset(available.height);
    final style = AppTypography.style(context, AppTextRole.chipIndex)
        .copyWith(color: color);
    final painter = TextPainter(
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        textScaler: TextScaler.noScaling,
        maxLines: 1);
    bool fits(double fontSize) {
      painter.text = TextSpan(
          text: index.toString(), style: style.copyWith(fontSize: fontSize));
      painter.layout();
      final rect = Rect.fromLTWH(left, topInset, painter.width, painter.height);
      return rect.right <= available.width &&
          rect.bottom <= available.height &&
          protected.every((area) => !rect.overlaps(area));
    }

    var low = .01;
    var high = style.fontSize!;
    if (fits(high)) {
      low = high;
    } else {
      for (var i = 0; i < 14; i++) {
        final candidate = (low + high) / 2;
        if (fits(candidate)) {
          low = candidate;
        } else {
          high = candidate;
        }
      }
    }
    painter.dispose();
    return Positioned(
        left: left,
        top: topInset,
        child: Text(index.toString(),
            textScaler: TextScaler.noScaling,
            style: style.copyWith(fontSize: low),
            maxLines: 1,
            softWrap: false));
  }
}
