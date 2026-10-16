import 'package:flutter/material.dart';
import '../models/shift_schedule.dart';
import '../theme/app_ui_theme.dart';
import '../utils/weekday_util.dart';
import 'shift_chip_label.dart';

/// Full-roster geometry only; calendar cell layouts are intentionally independent.
abstract final class AllShiftsMetrics {
  static const teamWidth = 26.0;
  static const trailingInset = 2.0;
  static const headerHeight = 42.0;
  static const dateTextScale = 1.06;
  static const weekdayTextScale = 1.06;
  static const overviewLabel =
      ShiftChipProportions(heightFraction: .77, horizontalInsetFraction: .065);
  static const cellGap = 1.0;
  static const cellRadius = 5.0;
  static const blockGap = 12.0;
  static const rowAspect = .9;
  static const maxRowHeight = 40.0;
  static double rowHeight(double width) =>
      (width * rowAspect).clamp(0, maxRowHeight);
}

class AllShiftsShiftChip extends StatelessWidget {
  const AllShiftsShiftChip(
      {super.key,
      required this.label,
      required this.color,
      this.proportions = AllShiftsMetrics.overviewLabel});
  final String label;
  final Color color;
  final ShiftChipProportions proportions;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AllShiftsMetrics.cellRadius),
        ),
        child: ShiftChipLabel(
          label: label,
          color: ShiftSchedule.getTextColor(color),
          proportions: proportions,
        ),
      );
}

class AllShiftsOverview extends StatelessWidget {
  const AllShiftsOverview(
      {super.key,
      required this.year,
      required this.month,
      required this.lastDay,
      required this.teams,
      required this.myTeam,
      required this.shiftFor,
      required this.shiftColors,
      this.today});
  final int year, month, lastDay;
  final List<String> teams;
  final String? myTeam;
  final DateTime? today;
  final String Function(String, DateTime) shiftFor;
  final Map<String, Color> shiftColors;

  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
              key: const ValueKey('roster-overview-scroll'),
              child: Padding(
                  padding: const EdgeInsets.only(
                      right: AllShiftsMetrics.trailingInset),
                  child: Column(children: [
                    for (final start in [1, 11, 21]) ...[
                      if (start > 1)
                        const SizedBox(height: AllShiftsMetrics.blockGap),
                      _block(
                          context,
                          p,
                          box.maxWidth - AllShiftsMetrics.trailingInset,
                          start,
                          start == 21 && lastDay == 31 ? 11 : 10),
                    ],
                  ])),
            ));
  }

  Widget _block(BuildContext context, AppUiPalette p, double width, int start,
      int columns) {
    final cellWidth =
        (width - AllShiftsMetrics.teamWidth).clamp(0, width) / columns;
    final rowHeight = AllShiftsMetrics.rowHeight(cellWidth);
    Widget cell(Widget child, double height, {double? width, Key? key}) =>
        SizedBox(
          key: key,
          width: width ?? cellWidth,
          height: height,
          child: Padding(
              padding: const EdgeInsets.all(AllShiftsMetrics.cellGap),
              child: child),
        );
    return Column(key: ValueKey('roster-block-$start'), children: [
      Row(children: [
        const SizedBox(width: AllShiftsMetrics.teamWidth),
        for (var day = start; day < start + columns; day++)
          cell(
              day > lastDay
                  ? const SizedBox.shrink()
                  : Builder(builder: (context) {
                      final date = DateTime(year, month, day);
                      final current = today?.year == year &&
                          today?.month == month &&
                          today?.day == day;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                            color: current ? p.primary : p.soft,
                            borderRadius: BorderRadius.circular(
                                AllShiftsMetrics.cellRadius)),
                        child: Center(
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('$day',
                                        textScaler: TextScaler.noScaling,
                                        style: AppTypography.style(
                                                context, AppTextRole.body)
                                            .copyWith(
                                                fontSize: AppTypography.style(
                                                            context,
                                                            AppTextRole.body)
                                                        .fontSize! *
                                                    AllShiftsMetrics
                                                        .dateTextScale,
                                                fontWeight: FontWeight.w600,
                                                color: current
                                                    ? p.onPrimary
                                                    : p.text)),
                                    Text(
                                        weekdayLabel(
                                            context, weekdayIndexOf(date),
                                            narrow: true),
                                        textScaler: TextScaler.noScaling,
                                        style: AppTypography.style(
                                                context, AppTextRole.supporting)
                                            .copyWith(
                                                fontSize: AppTypography.style(
                                                            context,
                                                            AppTextRole
                                                                .supporting)
                                                        .fontSize! *
                                                    AllShiftsMetrics
                                                        .weekdayTextScale,
                                                color: current
                                                    ? p.onPrimary
                                                    : p.secondaryText)),
                                  ],
                                ))),
                      );
                    }),
              AllShiftsMetrics.headerHeight,
              key: ValueKey('roster-date-$day')),
      ]),
      for (final team in teams)
        Row(children: [
          cell(
              Semantics(
                  selected: team == myTeam,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: team == myTeam ? p.primary : p.soft,
                        borderRadius:
                            BorderRadius.circular(AllShiftsMetrics.cellRadius)),
                    child: Center(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(team,
                                textScaler: TextScaler.noScaling,
                                style: AppTypography.style(
                                        context, AppTextRole.chip)
                                    .copyWith(
                                        color: team == myTeam
                                            ? p.onPrimary
                                            : p.text)))),
                  )),
              rowHeight,
              width: AllShiftsMetrics.teamWidth,
              key: ValueKey('roster-team-$start-$team')),
          for (var day = start; day < start + columns; day++)
            cell(
                day > lastDay
                    ? const SizedBox.shrink()
                    : Builder(builder: (context) {
                        final shift =
                            shiftFor(team, DateTime(year, month, day));
                        return AllShiftsShiftChip(
                            label: shift, color: shiftColors[shift] ?? p.soft);
                      }),
                rowHeight,
                key: ValueKey('roster-shift-$team-$day')),
        ]),
    ]);
  }
}
