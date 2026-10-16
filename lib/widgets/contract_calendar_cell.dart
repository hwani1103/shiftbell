import 'calendar_shift_change.dart';
import '../theme/calendar_overtime_layout.dart';
import 'calendar_overtime_label.dart';
import 'package:flutter/material.dart';
import '../theme/calendar_layout_contract.dart';
import '../theme/calendar_reading_palette.dart';
import 'complete_cell_memo_text.dart';
import 'shift_chip_label.dart';

/// Three reviewed designs share one geometry/typography contract. Theme colors
/// and gesture/date state are inputs; this renderer owns no saved user data.
class ContractCalendarCell extends StatelessWidget {
  const ContractCalendarCell(
      {super.key,
      required this.profile,
      required this.palette,
      required this.day,
      required this.shift,
      required this.shiftColor,
      required this.shiftTextColor,
      required this.memos,
      required this.isToday,
      required this.isOutside,
      required this.isRed,
      required this.flushTop,
      this.isSelected = false,
      this.isModified = false,
      this.holiday,
      this.lunar,
      this.overtimeMinutes = 0,
      this.overtimeSemanticLabel});
  final CalendarLayoutProfile profile;
  final CalendarReadingPalette palette;
  final int day;
  final String shift;
  final Color shiftColor, shiftTextColor;
  final List<String> memos;
  final bool isToday, isOutside, isRed, flushTop, isSelected, isModified;
  final String? holiday, lunar;
  final int overtimeMinutes;
  final String? overtimeSemanticLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final inherited = DefaultTextStyle.of(context).style;
        final g = CalendarCellGeometry.resolve(
            profile: profile,
            size: box.biggest,
            inherited: inherited,
            direction: Directionality.of(context),
            locale: Localizations.maybeLocaleOf(context),
            memoCount:
                overtimeMinutes > 0 && holiday != null ? 3 : memos.length,
            flushTop: flushTop,
            today: isToday);
        final u = g.unit;
        final layout = CalendarOvertimeLayout.resolve(
            theme: profile.theme,
            size: box.biggest,
            unit: u,
            chip: g.chip,
            date: g.date,
            annotation: g.annotation,
            rows: g.memoRows,
            lineHeight: g.info.lineHeight,
            memoCount: memos.length,
            hasOvertime: overtimeMinutes > 0,
            hasHoliday: holiday != null);
        final hasShift = shift.isNotEmpty && shift != '미설정';
        final card = profile.isSoft;
        final simple = profile.isSimple;
        final main = profile.isMain;
        final holidayInk =
            card ? palette.cardHoliday(isOutside) : palette.holiday;
        final lunarInk = card ? palette.cardLunar(isOutside) : palette.lunar;
        final normalInk = palette.text;
        final dateInk = isOutside
            ? palette.outside
            : isRed
                ? holidayInk
                : normalInk;
        Widget at(Rect rect, Widget child) =>
            Positioned.fromRect(rect: rect, child: child);
        Widget information(String text, Color color,
                {FontWeight weight = FontWeight.w600, double scale = 1}) =>
            CompleteCellMemoText(text,
                horizontalInset: 2 * u,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                    fontSize: g.info.fontSize * scale,
                    height: profile.infoLeading,
                    fontWeight: weight,
                    color: color));
        final shape = BorderRadius.circular((card ? 6 : 3) * u);
        final dateText = Text('$day',
            textScaler: TextScaler.noScaling,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: profile.date * u * layout.dateScale,
                height: profile.dateLeading,
                fontWeight: simple
                    ? (isToday ? FontWeight.bold : FontWeight.w500)
                    : main
                        ? FontWeight.w600
                        : FontWeight.w700,
                color: main && isToday
                    ? (isRed ? palette.todayHoliday : palette.onToday)
                    : dateInk));
        Widget date = Center(child: dateText);
        if (simple && isToday) {
          date = Center(
              child: Container(
                  width: 20 * u * layout.dateScale,
                  height: 20 * u * layout.dateScale,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.today, width: 1.4 * u)),
                  child: dateText));
        } else if (main && isToday) {
          date = Center(
              child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 6 * u, vertical: 2 * u * layout.dateScale),
                  decoration: BoxDecoration(
                      color: palette.today,
                      borderRadius: BorderRadius.circular(4 * u)),
                  child: dateText));
        }
        final children = <Widget>[
          if (hasShift)
            at(
                g.chip,
                CalendarShiftChange(
                    background:
                        simple ? shiftColor.withValues(alpha: .85) : shiftColor,
                    foreground: shiftTextColor,
                    surface:
                        card ? palette.cardSurface(isOutside) : palette.surface,
                    originalBackground: (color) =>
                        simple ? color.withValues(alpha: .85) : color,
                    builder: (bg, fg) => Container(
                        key: const ValueKey('contract-shift-background'),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                            color: bg, borderRadius: simple ? null : shape),
                        child: ShiftChipLabel(
                            label: shift,
                            color: fg,
                            proportions:
                                ShiftChipProportions.calendarReview)))),
          at(layout.date, date),
          if (holiday != null || (lunar != null && overtimeMinutes <= 0))
            at(
                layout.annotation,
                Center(
                    child: information(holiday ?? lunar!,
                        holiday != null ? holidayInk : lunarInk,
                        scale: layout.annotationScale,
                        weight: holiday != null
                            ? FontWeight.w700
                            : FontWeight.w600))),
          if (layout.overtime != null)
            at(
                layout.overtime!,
                CalendarOvertimeLabel(
                    minutes: overtimeMinutes,
                    semanticLabel: overtimeSemanticLabel,
                    style: TextStyle(
                        fontSize: g.info.fontSize * layout.annotationScale,
                        height: profile.infoLeading,
                        fontWeight: FontWeight.w600,
                        color: layout.inMemoSlot && !main
                            ? palette.memoText
                            : normalInk),
                    background:
                        layout.inMemoSlot && !main ? palette.memoSurface : null,
                    border: layout.inMemoSlot && !main ? palette.line : null)),
          for (var i = 0; i < layout.memos.length; i++)
            at(
                layout.memos[i],
                main
                    ? Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(
                            vertical: .5 * u * layout.memoScale),
                        decoration: BoxDecoration(
                            color: palette.memoSurface,
                            border:
                                Border.all(color: palette.line, width: .5 * u),
                            borderRadius: BorderRadius.circular(2 * u)),
                        child: information(memos[i], palette.memoText,
                            weight: FontWeight.w400, scale: layout.memoScale))
                    : Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: simple ? u : 0),
                        child: information(memos[i], normalInk,
                            weight: FontWeight.w400, scale: layout.memoScale))),
        ];
        final cell = Stack(clipBehavior: Clip.hardEdge, children: children);
        if (card) {
          final inset = profile.cellInset * u;
          return Padding(
              padding: EdgeInsets.all(inset),
              child: Container(
                  key: const ValueKey('contract-card'),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: palette.cardSurface(isOutside),
                      borderRadius: BorderRadius.circular(6 * u),
                      boxShadow: isOutside
                          ? null
                          : [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: .04),
                                  blurRadius: 2 * u,
                                  offset: Offset(0, u))
                            ]),
                  foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6 * u),
                      border: Border.all(
                          color: isSelected
                              ? palette.selection
                              : isToday
                                  ? palette.today
                                  : palette.cardLine(isOutside),
                          width: (isSelected
                                  ? 2
                                  : isToday
                                      ? 1.4
                                      : 1) *
                              u)),
                  // Geometry is in full-cell coordinates; translate only the origin,
                  // never scale the content or change its measured font size.
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    for (final child in children)
                      if (child is Positioned)
                        Positioned(
                            left:
                                child.left != null ? child.left! - inset : null,
                            top: child.top != null ? child.top! - inset : null,
                            width: child.width,
                            height: child.height,
                            child: child.child),
                  ])));
        }
        return ColoredBox(
            color: palette.surface,
            child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                    border: isSelected
                        ? Border.all(color: palette.selection, width: 2 * u)
                        : null),
                child: cell));
      });
}
