import '../theme/calendar_layout_contract.dart';
import 'package:flutter/material.dart';
import '../models/calendar_theme.dart';
import '../theme/app_theme.dart';
import '../theme/calendar_reading_palette.dart';
import '../theme/app_ui_theme.dart';

/// Legend themes and design-picker previews keep their existing appearance.
bool calendarUsesAppFrame(CalendarThemeId theme,
        {bool preview = false, bool includeLegend = false}) =>
    CalendarThemeRollout.frameEnabled &&
    !CalendarThemeRollout.preservesOriginalAppearance(theme) &&
    !preview &&
    (!theme.hasLegend ||
        (includeLegend && CalendarThemeRollout.mode == 'reading'));

/// Preserve every calendar ColorScheme/style while passing only app color roles
/// through to its header and reclaimed action cells.
class CalendarDesignTheme extends StatelessWidget {
  const CalendarDesignTheme(
      {super.key, required this.theme, required this.child});
  final CalendarThemeId theme;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final calendar = AppTheme.forCalendar(theme);
    return Theme(
        data: calendar.copyWith(extensions: [
          ...calendar.extensions.values.where((e) => e is! AppUiPalette),
          CalendarThemeRollout.usesReading(theme)
              ? CalendarReadingPalette.framePalette(AppUiPalette.of(context))
              : AppUiPalette.of(context),
        ]),
        child: child);
  }
}

/// Bounded calendar actions share typography and state colors with app controls.
class CalendarAppAction extends StatelessWidget {
  const CalendarAppAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.iconOnly = false,
      this.padding,
      this.layoutUnit,
      this.integratedGrid = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool iconOnly;
  final bool integratedGrid;
  final EdgeInsetsGeometry? padding;
  final double? layoutUnit;
  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    final radius = integratedGrid
        ? BorderRadius.zero
        : BorderRadius.circular(layoutUnit == null
            ? AppUiMetrics.controlRadius
            : CalendarFrameRatios.actionRadius * layoutUnit!);
    return Padding(
        padding: integratedGrid
            ? EdgeInsets.zero
            : padding ??
                EdgeInsets.all(layoutUnit == null
                    ? AppUiMetrics.calendarControlPadding
                    : CalendarFrameRatios.actionInset * layoutUnit!),
        child: Semantics(
            button: true,
            label: label,
            child: Tooltip(
                message: label,
                child: Material(
                    color: integratedGrid ? p.surface : p.soft,
                    shape: RoundedRectangleBorder(
                        borderRadius: radius,
                        side: integratedGrid
                            ? BorderSide.none
                            : BorderSide(
                                color: p.border,
                                width: AppUiMetrics.calendarBorderWidth)),
                    child: InkWell(
                        onTap: onTap,
                        borderRadius: radius,
                        child: LayoutBuilder(
                            builder: (_, box) => Center(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: SizedBox(
                                        width: box.maxWidth,
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(icon,
                                                  color: p.primary,
                                                  size: layoutUnit != null
                                                      ? (iconOnly &&
                                                                  !integratedGrid
                                                              ? CalendarFrameRatios
                                                                  .compactIcon
                                                              : CalendarFrameRatios
                                                                  .icon) *
                                                          layoutUnit!
                                                      : iconOnly &&
                                                              !integratedGrid
                                                          ? AppUiMetrics
                                                              .calendarCompactIconSize
                                                          : AppUiMetrics
                                                              .calendarIconSize),
                                              if (!iconOnly)
                                                Text(label,
                                                    textScaler:
                                                        TextScaler.noScaling,
                                                    style: AppTypography.style(
                                                            context,
                                                            AppTextRole
                                                                .supporting)
                                                        .copyWith(
                                                            fontSize: layoutUnit ==
                                                                    null
                                                                ? null
                                                                : 10.5 *
                                                                    layoutUnit!),
                                                    textAlign:
                                                        TextAlign.center),
                                            ]))))))))));
  }
}

class CalendarWorkSummary extends StatelessWidget {
  const CalendarWorkSummary(
      {super.key,
      required this.otLabel,
      required this.otValue,
      required this.weeklyLabel,
      required this.onOt,
      required this.onWeekly,
      required this.actions,
      this.gridSide,
      this.layoutUnit});
  final String otLabel, otValue, weeklyLabel;
  final VoidCallback onOt, onWeekly;
  final List<Widget> actions;

  /// When embedded in a table, leave the existing grid stroke visible and
  /// only paint the two internal horizontal separators.
  final BorderSide? gridSide;
  final double? layoutUnit;
  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    Widget line(VoidCallback onTap, String label, {String? value}) => Material(
        color: p.surface,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: layoutUnit == null
                        ? AppUiMetrics.calendarSummaryInset
                        : CalendarFrameRatios.summaryInset * layoutUnit!),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(label,
                              textScaler: TextScaler.noScaling,
                              style: AppTypography.style(
                                      context, AppTextRole.supporting,
                                      tone: AppTextTone.secondary)
                                  .copyWith(
                                      fontSize: layoutUnit == null
                                          ? null
                                          : CalendarFrameRatios.supportingFont *
                                              layoutUnit!)),
                          SizedBox(
                              width: layoutUnit == null
                                  ? AppUiMetrics.previewGap
                                  : CalendarFrameRatios.summaryGap *
                                      layoutUnit!),
                          if (value != null)
                            Text(value,
                                textScaler: TextScaler.noScaling,
                                style: AppTypography.style(
                                        context, AppTextRole.supporting)
                                    .copyWith(
                                        fontSize: layoutUnit == null
                                            ? null
                                            : CalendarFrameRatios
                                                    .supportingFont *
                                                layoutUnit!))
                          else
                            Icon(Icons.chevron_right,
                                color: p.secondaryText,
                                size: layoutUnit == null
                                    ? AppUiMetrics.calendarCompactIconSize
                                    : CalendarFrameRatios.compactIcon *
                                        layoutUnit!),
                        ]))))));
    final side = gridSide ??
        BorderSide(color: p.border, width: AppUiMetrics.calendarBorderWidth);
    final content = DecoratedBox(
        key: const ValueKey('calendar-app-work-summary'),
        decoration: BoxDecoration(
            color: p.surface,
            border: gridSide == null ? Border.fromBorderSide(side) : null),
        child: Column(children: [
          Expanded(flex: 3, child: line(onOt, otLabel, value: otValue)),
          SizedBox(
              height: side.width,
              child: ColoredBox(
                  color: side.color, child: const SizedBox.expand())),
          Expanded(flex: 3, child: line(onWeekly, weeklyLabel)),
          SizedBox(
              height: side.width,
              child: ColoredBox(
                  color: side.color, child: const SizedBox.expand())),
          Expanded(
              flex: 4,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: actions)),
        ]));
    return gridSide == null
        ? content
        : Padding(
            // Internal grid strokes are centered on their boundary, while
            // the table's outer right/bottom strokes are entirely inside it.
            padding: EdgeInsets.fromLTRB(
                side.width / 2, side.width / 2, side.width, side.width),
            child: content);
  }
}
