import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/calendar_theme.dart';
import '../constants/layout_limits.dart';
import 'complete_cell_memo_text.dart';
import 'wide_calendar_cell.dart';

const periwinkleBackground = Color(0xFFC8D9F5);
const conceptInk = Color(0xFF273653);

/// A run is bounded by the displayed week. Calendar arithmetic avoids
/// DST-dependent 24-hour offsets. Equal colours alone never merge two shifts.
({int index, int length}) calendarShiftRun(
    DateTime day, int firstWeekday, String Function(DateTime) shiftForDate) {
  final name = shiftForDate(day);
  if (name.isEmpty || name == '미설정') return (index: 0, length: 1);
  final column = (day.weekday - firstWeekday + 7) % 7;
  DateTime at(int offset) => DateTime(day.year, day.month, day.day + offset);
  bool matches(int offset) => shiftForDate(at(offset)) == name;
  var before = 0;
  var after = 0;
  while (before < column && matches(-before - 1)) {
    before++;
  }
  while (after < 6 - column && matches(after + 1)) {
    after++;
  }
  return (index: before, length: before + after + 1);
}

/// Uses actual cell constraints on bar, cover, unfolded and landscape screens.
/// Dates/shift/memos keep identical slots even when neighbouring cells are empty.
class GlobalConceptCalendarCell extends StatelessWidget {
  const GlobalConceptCalendarCell(
      {super.key,
      required this.theme,
      required this.date,
      required this.shift,
      required this.shiftColor,
      required this.shiftTextColor,
      required this.memos,
      required this.today,
      required this.outside,
      required this.red,
      required this.selected,
      this.coverMemoSize = 9.3,
      this.runIndex = 0,
      this.runLength = 1});
  final CalendarThemeId theme;
  final DateTime date;
  final String shift;
  final Color shiftColor, shiftTextColor;
  final List<String> memos;
  final bool today, outside, red, selected;
  final int runIndex, runLength;
  final double coverMemoSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final mosaic = theme == CalendarThemeId.softMosaic;
        final phoneLabel = !AppLayout.of(context).usesBoundedCalendar;
        final split = WideCalendarCell.appliesTo(MediaQuery.sizeOf(context));
        final width = box.maxWidth;
        final height = box.maxHeight;
        final unit = math.min(width / 56, height / 103).clamp(0.45, 1.45);
        final gap = 3 * unit;
        final dateHeight = 24 * unit;
        final shiftHeight = (split ? 22.5 : 19) * unit;
        final memoGap = phoneLabel ? gap : .5 * unit;
        final targetMemoSize = split ? 10.5 : coverMemoSize;
        final memoBudget = math.max(
            1.0,
            (height -
                    (split ? 0 : dateHeight) -
                    shiftHeight -
                    gap * (split ? 3 : 4) -
                    3 * memoGap) /
                3);
        double memoLineHeight(double size) {
          final probe = TextPainter(
              text: TextSpan(
                  text: 'Ag',
                  style: DefaultTextStyle.of(context).style.merge(TextStyle(
                      fontSize: size,
                      height: 1.0,
                      fontWeight: FontWeight.w500))),
              textDirection: Directionality.of(context),
              textScaler: TextScaler.noScaling)
            ..layout();
          final result = probe.height;
          probe.dispose();
          return result;
        }

        final memoHeight = phoneLabel
            ? math.min(
                18 * unit,
                math.max(
                    1.0, (height - dateHeight - shiftHeight - gap * 7) / 3))
            : math.min(memoLineHeight(targetMemoSize) + 1.7, memoBudget);
        var fittedMemoSize = targetMemoSize;
        if (!phoneLabel) {
          for (var i = 0;
              i < 40 && memoLineHeight(fittedMemoSize) > memoHeight - 1.3;
              i++) {
            fittedMemoSize *= .97;
          }
        }
        final inset = mosaic ? 2 * unit : 0.0;
        const memoColors = [
          Color(0xFFFFE5D3),
          Color(0xFFDEF2CF),
          Color(0xFFF3DDF0)
        ];
        final cellTint = shift.isEmpty
            ? const Color(0xFFF0F3F7)
            : Color.lerp(Colors.white, shiftColor, .33)!;
        // Same hue as the cell, with enough saturation to separate the badge.
        final chipColor = Color.lerp(Colors.white, shiftColor, .80)!;
        final luminance = chipColor.computeLuminance();
        final chipInk = (luminance + .05) / .05 >= 1.05 / (luminance + .05)
            ? Colors.black
            : Colors.white;
        Widget label(String text, double fontSize, Color color,
                [bool shiftLabel = false]) =>
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text,
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        inherit: !shiftLabel,
                        fontSize: fontSize,
                        leadingDistribution: shiftLabel
                            ? TextLeadingDistribution.proportional
                            : null,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: color)));
        final dateSlot = KeyedSubtree(
            key: const ValueKey('concept-date'),
            child: SizedBox(
                height: dateHeight,
                child: Center(
                    child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6 * unit, vertical: 2 * unit),
                        decoration: today
                            ? BoxDecoration(
                                color: const Color(0xFF526BAB),
                                borderRadius: BorderRadius.circular(8 * unit),
                                boxShadow: [
                                    BoxShadow(
                                        color: const Color(0xFF526BAB)
                                            .withValues(alpha: .2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ])
                            : null,
                        child: label(
                            '${date.day}',
                            (split ? 18 : 16.5) * unit,
                            today
                                ? Colors.white
                                : red
                                    ? const Color(0xFFC43D4D)
                                    : conceptInk.withValues(
                                        alpha: outside ? .4 : 1))))));
        final shiftSlot = KeyedSubtree(
            key: const ValueKey('concept-shift'),
            child: SizedBox(
                height: shiftHeight,
                width: double.infinity,
                child: shift.isEmpty
                    ? null
                    : mosaic
                        ? Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3 * unit),
                            child: Container(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 2 * unit),
                                decoration: BoxDecoration(
                                    color: chipColor,
                                    borderRadius:
                                        BorderRadius.circular(5 * unit),
                                    boxShadow: [
                                      BoxShadow(
                                          color:
                                              chipColor.withValues(alpha: .16),
                                          blurRadius: 3,
                                          offset: const Offset(0, 1))
                                    ]),
                                child: label(shift, shiftHeight * 15 / 19,
                                    chipInk, true)))
                        : Semantics(
                            label: runIndex == 0 ? shift : null,
                            child: CustomPaint(
                                painter: _RunPainter(
                                    text: shift,
                                    background: shiftColor,
                                    foreground: shiftTextColor,
                                    index: runIndex,
                                    length: runLength,
                                    unit: unit,
                                    phoneLabel: phoneLabel)))));
        final memoSlots = memos
            .take(3)
            .toList()
            .asMap()
            .entries
            .map((entry) => Container(
                height: memoHeight,
                width: double.infinity,
                margin: EdgeInsets.fromLTRB((mosaic ? 3 : 2) * unit, 0,
                    (mosaic ? 3 : 2) * unit, memoGap),
                padding: EdgeInsets.symmetric(horizontal: 1.5 * unit),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: mosaic
                            ? [const Color(0xFFFCFDFE), const Color(0xFFEFF2F7)]
                            : [
                                memoColors[entry.key].withValues(alpha: .92),
                                memoColors[entry.key].withValues(alpha: .72)
                              ]),
                    borderRadius: BorderRadius.circular(5 * unit),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .55), width: .6),
                    boxShadow: [
                      BoxShadow(
                          color: conceptInk.withValues(alpha: .10),
                          blurRadius: 3 * unit,
                          offset: Offset(0, 1.5 * unit))
                    ]),
                child: Center(
                    child: CompleteCellMemoText(entry.value,
                        horizontalInset: .75,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                            color: const Color(0xFF17202D),
                            fontSize: phoneLabel
                                ? math.min(11 * unit, (memoHeight - 1.2) / 1.15)
                                : fittedMemoSize,
                            height: phoneLabel ? 1.05 : 1.0,
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center))))
            .toList();
        return Opacity(
            opacity: outside && mosaic ? .38 : 1,
            child: Container(
                margin: EdgeInsets.symmetric(horizontal: inset, vertical: gap),
                foregroundDecoration: selected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(10 * unit),
                        border: Border.all(
                            color: const Color(0xFF5168AB), width: 1.5))
                    : null,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10 * unit),
                    gradient: mosaic
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                                Color.lerp(cellTint, Colors.white, .3)!,
                                cellTint
                              ])
                        : null,
                    boxShadow: mosaic
                        ? [
                            BoxShadow(
                                color: shiftColor.withValues(alpha: .13),
                                blurRadius: 5 * unit,
                                offset: Offset(0, 2 * unit))
                          ]
                        : null),
                child: split
                    ? Column(children: [
                        shiftSlot,
                        SizedBox(height: gap),
                        Expanded(
                            child: Row(children: [
                          Expanded(flex: 3, child: Center(child: dateSlot)),
                          Expanded(
                              flex: 7,
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: memoSlots)),
                        ])),
                      ])
                    : Column(children: [
                        dateSlot,
                        shiftSlot,
                        SizedBox(height: gap * 2),
                        ...memoSlots,
                      ])));
      });
}

/// Each cell paints a clipped slice of the same run. No overflow widget steals
/// the adjacent date's hit target, and the label stays centred for even runs.
class _RunPainter extends CustomPainter {
  _RunPainter(
      {required this.text,
      required this.background,
      required this.foreground,
      required this.index,
      required this.length,
      required this.unit,
      required this.phoneLabel});
  final String text;
  final Color background, foreground;
  final int index, length;
  final double unit;
  final bool phoneLabel;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final runWidth = size.width * length;
    final left = -size.width * index;
    final rect =
        Rect.fromLTWH(left + 1.5 * unit, 0, runWidth - 3 * unit, size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(5 * unit)),
        Paint()..color = background);
    final painter = TextPainter(
        textDirection: TextDirection.ltr,
        maxLines: 1,
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: foreground,
                fontSize: size.height * 15 / 19,
                height: 1.05,
                fontWeight: FontWeight.w700)))
      ..layout();
    final scale = math.min(
        1.0,
        math.min((rect.width - 6 * unit) / painter.width,
            (size.height - 2 * unit) / painter.height));
    canvas.translate(left + (runWidth - painter.width * scale) / 2,
        (size.height - painter.height * scale) / 2);
    canvas.scale(scale);
    painter.paint(canvas, Offset.zero);
    painter.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RunPainter old) =>
      text != old.text ||
      background != old.background ||
      foreground != old.foreground ||
      index != old.index ||
      length != old.length ||
      unit != old.unit ||
      phoneLabel != old.phoneLabel;
}
