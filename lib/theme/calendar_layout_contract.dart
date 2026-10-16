import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/calendar_theme.dart';

/// Design ratios, not a captured phone size. One cell is 1/7 of the existing
/// 360-unit design canvas. All lengths below are multiples of that cell width.
class CalendarLayoutProfile {
  const CalendarLayoutProfile(
      {required this.theme,
      required this.chip,
      required this.date,
      required this.info,
      required this.infoLeading,
      required this.dateLeading,
      required this.cellInset,
      required this.memoGap});
  final CalendarThemeId theme;
  final double chip, date, info, infoLeading, dateLeading, cellInset, memoGap;
  static const main = CalendarLayoutProfile(
      theme: CalendarThemeId.mainWhite,
      chip: 18,
      date: 16,
      info: 9.3,
      infoLeading: 1,
      dateLeading: 1,
      cellInset: 2,
      memoGap: .5);
  static const simple = CalendarLayoutProfile(
      theme: CalendarThemeId.minimal,
      chip: 16.5,
      date: 12.2,
      info: 9,
      infoLeading: 1.15,
      dateLeading: 1.43,
      cellInset: 0,
      memoGap: .15);
  static const soft = CalendarLayoutProfile(
      theme: CalendarThemeId.materialCard,
      chip: 15.4,
      date: 11.7,
      info: 8,
      infoLeading: 1,
      dateLeading: 1.43,
      cellInset: 2,
      memoGap: 1.5);
  static CalendarLayoutProfile? forTheme(CalendarThemeId theme) =>
      switch (theme) {
        CalendarThemeId.mainWhite => main,
        CalendarThemeId.minimal => simple,
        CalendarThemeId.materialCard => soft,
        _ => null,
      };
  static const designWidth = 360.0;
  static const columns = 7;
  static const rows = 6;
  static double unitForWidth(double width) => width * columns / designWidth;
  bool get isMain => theme == CalendarThemeId.mainWhite;
  bool get isSimple => theme == CalendarThemeId.minimal;
  bool get isSoft => theme == CalendarThemeId.materialCard;
}

/// A single pre-layout measurement shared by annotation and all memo rows.
/// Counts and actual strings never choose a different information font size.
class CalendarInformationMetrics {
  const CalendarInformationMetrics(this.fontSize, this.lineHeight);
  final double fontSize, lineHeight;
  static final _cache = <(
    TextStyle,
    TextDirection,
    Locale?,
    double,
    double,
    double
  ),
      CalendarInformationMetrics>{};
  static CalendarInformationMetrics resolve(
      {required TextStyle inherited,
      required TextDirection direction,
      required Locale? locale,
      required double preferredSize,
      required double leading,
      required double safeWidth}) {
    final key = (
      inherited.copyWith(color: const Color(0xFF000000)),
      direction,
      locale,
      preferredSize,
      leading,
      safeWidth
    );
    final cached = _cache[key];
    if (cached != null) return cached;
    double widest(double size) {
      var result = 0.0;
      for (final weight in [
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700
      ]) {
        for (final sample in ['가가가가가가', '근근근근근근', '부처님오신날']) {
          final painter = TextPainter(
              text: TextSpan(
                  text: sample,
                  style: inherited.copyWith(
                      fontSize: size, height: leading, fontWeight: weight)),
              textDirection: direction,
              locale: locale,
              textScaler: TextScaler.noScaling,
              maxLines: 1)
            ..layout();
          result = math.max(result, painter.width);
          painter.dispose();
        }
      }
      return result;
    }

    var low = 0.0, high = preferredSize;
    if (widest(high) > safeWidth) {
      for (var i = 0; i < 16; i++) {
        final mid = (low + high) / 2;
        if (widest(mid) <= safeWidth) {
          low = mid;
        } else {
          high = mid;
        }
      }
    } else {
      low = high;
    }
    final painter = TextPainter(
        text: TextSpan(
            text: '가9',
            style: inherited.copyWith(fontSize: low, height: leading)),
        textDirection: direction,
        locale: locale,
        textScaler: TextScaler.noScaling,
        maxLines: 1)
      ..layout();
    final result = CalendarInformationMetrics(low, painter.height);
    painter.dispose();
    if (_cache.length >= 256) _cache.clear();
    _cache[key] = result;
    return result;
  }
}

/// Explicit content budget: compress optional space first. Only a genuinely
/// short cell reduces the common drawing unit. No whole-cell transform exists.
class CalendarCellGeometry {
  const CalendarCellGeometry(
      {required this.size,
      required this.unit,
      required this.density,
      required this.chip,
      required this.date,
      required this.annotation,
      required this.memoRows,
      required this.info,
      required this.minimumHeight});
  final Size size;
  final double unit, density, minimumHeight;
  final Rect chip, date, annotation;
  final List<Rect> memoRows;
  final CalendarInformationMetrics info;

  static CalendarCellGeometry resolve(
      {required CalendarLayoutProfile profile,
      required Size size,
      required TextStyle inherited,
      required TextDirection direction,
      required Locale? locale,
      required int memoCount,
      required bool flushTop,
      required bool today}) {
    final widthUnit = CalendarLayoutProfile.unitForWidth(size.width);
    CalendarInformationMetrics information(double u) {
      final inset = profile.isSimple ? 7 : 8;
      return CalendarInformationMetrics.resolve(
          inherited: inherited,
          direction: direction,
          locale: locale,
          preferredSize: profile.info * u,
          leading: profile.infoLeading,
          safeWidth: math.max(.01, size.width - inset * u - .5 * u));
    }

    double dateLine(double u) {
      if (profile.isSimple) return 20 * u;
      final p = TextPainter(
          text: TextSpan(
              text: '가9',
              style: inherited.copyWith(
                  fontSize: profile.date * u, height: profile.dateLeading)),
          textDirection: direction,
          locale: locale,
          textScaler: TextScaler.noScaling)
        ..layout();
      final height = p.height;
      p.dispose();
      return height;
    }

    double requiredHeight(double u, CalendarInformationMetrics info) {
      // Reserve the same worst-case three-line content for every date, including
      // empty dates and today. These are the very same rect terms drawn below.
      final memo = 3 * (info.lineHeight + (profile.isMain ? 2 * u : 0)) +
          2 * profile.memoGap * u;
      if (profile.isMain) {
        return 2 * u +
            profile.chip * u +
            1.2 * u +
            11 * u +
            u +
            dateLine(u) +
            4 * u +
            2 * u +
            memo +
            2 * u;
      }
      return 3 * u +
          profile.chip * u +
          (profile.isSimple ? .3 : 1) * u +
          dateLine(u) +
          info.lineHeight +
          (profile.isSimple ? 2 : 3.5) * u +
          memo +
          2 * u;
    }

    final preferredInfo = information(widthUnit);
    final minimum = requiredHeight(widthUnit, preferredInfo);
    var density = 1.0;
    if (minimum > size.height) {
      var low = 0.0, high = 1.0;
      for (var i = 0; i < 16; i++) {
        final mid = (low + high) / 2;
        final u = widthUnit * mid;
        if (requiredHeight(u, information(u)) <= size.height) {
          low = mid;
        } else {
          high = mid;
        }
      }
      density = low;
    }
    final u = widthUnit * density;
    final info = density == 1 ? preferredInfo : information(u);
    final count = memoCount.clamp(0, 3);
    final left = profile.isSimple ? u : profile.cellInset * u;
    final right = profile.cellInset * u;
    final width = math.max(0.0, size.width - left - right);
    final top = profile.isMain
        ? 2 * u
        : profile.isSimple
            ? (flushTop ? 0.0 : 3 * u)
            : (today ? 2 : 3) * u;
    final chip = Rect.fromLTWH(left, top, width, profile.chip * u);
    final rows = <Rect>[];
    late Rect date, annotation;
    final dateHeight = dateLine(u) + (profile.isMain && today ? 4 * u : 0);
    final memoRow = info.lineHeight + (profile.isMain ? 2 * u : 0);
    final memoBlock =
        count * memoRow + math.max(0, count - 1) * profile.memoGap * u;
    if (profile.isMain) {
      final bodyTop = chip.bottom;
      final bodyHeight = size.height - bodyTop;
      annotation = Rect.fromLTWH(left, bodyTop + 1.2 * u, width, 11 * u);
      final memoBottom = size.height - 2 * u;
      final memoTop = memoBottom - memoBlock;
      final preferred =
          bodyTop + (bodyHeight - dateHeight) / 2 - (count >= 3 ? 10 * u : 0);
      final minTop = annotation.bottom + u;
      final maxTop =
          (count > 0 ? memoTop - 2 * u : size.height - u) - dateHeight;
      final y =
          preferred.clamp(math.min(minTop, maxTop), math.max(minTop, maxTop));
      date = Rect.fromLTWH(left, y.toDouble(), width, dateHeight);
      for (var i = 0; i < count; i++) {
        rows.add(Rect.fromLTWH(left,
            memoTop + i * (memoRow + profile.memoGap * u), width, memoRow));
      }
    } else {
      date = Rect.fromLTWH(left, chip.bottom + (profile.isSimple ? .3 : 1) * u,
          width, dateHeight);
      annotation = Rect.fromLTWH(left, date.bottom, width, info.lineHeight);
      final gap = (profile.isSimple ? 2 : 3.5) * u;
      final bottom = size.height - (profile.isSimple ? 2 : 2) * u;
      final available =
          math.max(0.0, bottom - annotation.bottom - gap - memoBlock);
      final memoTop =
          annotation.bottom + gap + (profile.isSimple ? available / 2 : 0);
      for (var i = 0; i < count; i++) {
        rows.add(Rect.fromLTWH(left,
            memoTop + i * (memoRow + profile.memoGap * u), width, memoRow));
      }
    }
    return CalendarCellGeometry(
        size: size,
        unit: u,
        density: density,
        chip: chip,
        date: date,
        annotation: annotation,
        memoRows: List.unmodifiable(rows),
        info: info,
        minimumHeight: minimum);
  }
}

/// The available tab width, excluding system safe insets, is the sole frame
/// scale input. Calendar height comes from the parent after ad/navigation space.
class CalendarViewportScope extends InheritedWidget {
  const CalendarViewportScope(
      {super.key, required this.unit, required super.child});
  final double unit;
  static double unitOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CalendarViewportScope>()!.unit;
  @override
  bool updateShouldNotify(CalendarViewportScope oldWidget) =>
      unit != oldWidget.unit;
}

/// Frame coefficients share the same design unit as cells. Values are design
/// proportions; they never depend on a device identifier or captured pixels.
abstract final class CalendarFrameRatios {
  static const titleFont = 16.0;
  static const supportingFont = 10.5;
  static const actionInset = 3.5;
  static const actionRadius = 10.5;
  static const icon = 15.75;
  static const compactIcon = 14.0;
  static const summaryInset = 8.75;
  static const summaryGap = 5.25;
  static const footerGap = 14.0;
}
