import 'calendar_shift_change.dart';
import '../theme/calendar_overtime_layout.dart';
import 'calendar_overtime_label.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/calendar_theme.dart';
import '../theme/calendar_layout_contract.dart';
import '../theme/calendar_reading_palette.dart';
import 'complete_cell_memo_text.dart';
import 'shift_chip_label.dart';

/// The remaining Korean designs retain their visual order while sharing one
/// measured information font and a three-memo height budget, independent of data.
class CalendarDetailProfile {
  const CalendarDetailProfile(this.theme, this.date, this.chip, this.info,
      {this.leading = 1.12, this.inset = 2, this.memoGap = 1.2});
  final CalendarThemeId theme;
  final double date, chip, info, leading, inset, memoGap;
  static const values = [
    CalendarDetailProfile(CalendarThemeId.diary, 13, 19, 8.6),
    CalendarDetailProfile(CalendarThemeId.boldGrid, 11.2, 17, 8.5, inset: 1),
    CalendarDetailProfile(CalendarThemeId.initialBadge, 13, 19, 8.5),
    CalendarDetailProfile(CalendarThemeId.eventChip, 13.2, 17, 8.5),
    CalendarDetailProfile(CalendarThemeId.underline, 12, 3, 8.5, inset: 3),
    CalendarDetailProfile(CalendarThemeId.editorial, 12, 3, 8.5, inset: 3),
  ];
  static CalendarDetailProfile? forTheme(CalendarThemeId theme) {
    for (final value in values) {
      if (value.theme == theme) return value;
    }
    return null;
  }

  bool get diary => theme == CalendarThemeId.diary;
  bool get grid => theme == CalendarThemeId.boldGrid;
  bool get badge => theme == CalendarThemeId.initialBadge;
  bool get event => theme == CalendarThemeId.eventChip;
  bool get underline => theme == CalendarThemeId.underline;
  bool get editorial => theme == CalendarThemeId.editorial;
}

class CalendarDetailGeometry {
  CalendarDetailGeometry._(this.unit, this.date, this.chip, this.annotation,
      this.memos, this.information);
  final double unit;
  final Rect date, chip, annotation;
  final List<Rect> memos;
  final CalendarInformationMetrics information;
  static CalendarDetailGeometry resolve(
      {required CalendarDetailProfile profile,
      required Size size,
      required TextStyle inherited,
      required TextDirection direction,
      required Locale? locale,
      int day = 28,
      bool hasOvertime = false,
      bool phoneDecorations = false}) {
    final base = CalendarLayoutProfile.unitForWidth(size.width);
    CalendarInformationMetrics measure(double u) =>
        CalendarInformationMetrics.resolve(
            inherited: inherited,
            direction: direction,
            locale: locale,
            preferredSize: profile.info * u,
            leading: profile.leading,
            safeWidth: math.max(.01, size.width - (2 * profile.inset + 4) * u));
    double header(double u) =>
        (profile.diary
            ? profile.chip
            : profile.editorial
                ? 20
                : profile.badge
                    ? profile.chip + 20
                    : profile.underline
                        ? 26
                        : profile.grid
                            ? 16 + profile.chip
                            : 22 + profile.chip) *
        u;
    double minimum(double u) {
      final info = measure(u);
      return header(u) +
          (profile.grid ? 3 : 4) * info.lineHeight +
          (10 + 2 * profile.memoGap + (profile.event ? 6 : 0)) * u;
    }

    var scale = 1.0;
    if (minimum(base) > size.height) {
      var low = 0.0, high = 1.0;
      for (var i = 0; i < 16; i++) {
        final mid = (low + high) / 2;
        if (minimum(base * mid) <= size.height) {
          low = mid;
        } else {
          high = mid;
        }
      }
      scale = low;
    }
    final u = base * scale, info = measure(base * scale);
    final x = profile.inset * u, width = math.max(0.0, size.width - 2 * x);
    late Rect date, chip, annotation;
    final top = 2 * u;
    if (profile.diary) {
      date = Rect.fromLTWH(x, top, width * .30, profile.chip * u);
      chip = Rect.fromLTWH(date.right, top, width * .70, profile.chip * u);
      annotation =
          Rect.fromLTWH(x, chip.bottom + 2 * u, width, info.lineHeight);
    } else if (profile.grid) {
      final datePainter = TextPainter(
          text: TextSpan(
              text: '$day',
              style: inherited.merge(TextStyle(
                  fontSize: profile.date * u,
                  height: 1.1,
                  fontWeight: FontWeight.w700))),
          textDirection: direction,
          locale: locale,
          textScaler: TextScaler.noScaling,
          maxLines: 1)
        ..layout();
      final dateWidth = math.min(width, datePainter.width + u);
      datePainter.dispose();
      date = Rect.fromLTWH(x, 0, dateWidth, 16 * u);
      final annotationLeft = date.right + .5 * u;
      annotation = Rect.fromLTWH(
          annotationLeft, 0, math.max(0.0, x + width - annotationLeft), 16 * u);
      chip = Rect.fromLTWH(x, date.bottom, width, profile.chip * u);
    } else if (profile.badge) {
      chip = Rect.fromLTWH((size.width - profile.chip * u) / 2, top,
          profile.chip * u, profile.chip * u);
      date = Rect.fromLTWH(x, chip.bottom + 2 * u, width, 18 * u);
      annotation = Rect.fromLTWH(x, date.bottom + u, width, info.lineHeight);
    } else if (profile.editorial && phoneDecorations) {
      date =
          Rect.fromLTWH(x + 16 * u, top, math.max(0.0, width - 16 * u), 20 * u);
      chip = Rect.fromLTWH(0, 0, 16 * u, 16 * u);
      annotation = Rect.fromLTWH(x, date.bottom, width, info.lineHeight);
    } else if (profile.editorial) {
      date =
          Rect.fromLTWH(x + 4 * u, top, math.max(0.0, width - 4 * u), 20 * u);
      chip = Rect.fromLTWH(x, top, 2.5 * u, math.max(0.0, size.height - 4 * u));
      annotation = Rect.fromLTWH(x + 4 * u, date.bottom,
          math.max(0.0, width - 4 * u), info.lineHeight);
    } else {
      date = Rect.fromLTWH(x, top, width, profile.underline ? 20 * u : 22 * u);
      chip = Rect.fromLTWH(profile.underline ? (size.width - 22 * u) / 2 : x,
          date.bottom, profile.underline ? 22 * u : width, profile.chip * u);
      annotation =
          Rect.fromLTWH(x, chip.bottom + 2 * u, width, info.lineHeight);
    }
    if (profile.event && hasOvertime) {
      final painter = TextPainter(
          text: TextSpan(
              text: '$day',
              style: inherited.merge(TextStyle(
                  fontSize: profile.date * u,
                  height: 1.1,
                  fontWeight: FontWeight.w700))),
          textDirection: direction,
          locale: locale,
          textScaler: TextScaler.noScaling,
          maxLines: 1)
        ..layout();
      date = Rect.fromLTWH(date.left, date.top,
          math.min(date.width, painter.width + 4 * u), date.height);
      painter.dispose();
    }
    final bodyTop =
        profile.grid ? chip.bottom + 4 * u : annotation.bottom + 3 * u;
    final rowH = info.lineHeight + (profile.event ? 2 * u : 0);
    final block = rowH * 3 + 2 * profile.memoGap * u;
    final slack = math.max(0.0, size.height - 2 * u - bodyTop - block);
    final memoTop = bodyTop +
        ((profile.grid || profile.badge || profile.underline) ? slack / 2 : 0);
    final memoLeft = profile.editorial && !phoneDecorations ? x + 4 * u : x;
    final memoWidth = profile.editorial && !phoneDecorations
        ? math.max(0.0, width - 4 * u)
        : width;
    return CalendarDetailGeometry._(
        u,
        date,
        chip,
        annotation,
        List.generate(
            3,
            (i) => Rect.fromLTWH(memoLeft,
                memoTop + i * (rowH + profile.memoGap * u), memoWidth, rowH)),
        info);
  }
}

class DetailCalendarCell extends StatelessWidget {
  const DetailCalendarCell(
      {super.key,
      required this.profile,
      required this.palette,
      required this.day,
      required this.shift,
      required this.shiftColor,
      required this.shiftTextColor,
      required this.memos,
      required this.today,
      required this.outside,
      required this.red,
      required this.selected,
      this.holiday,
      this.lunar,
      this.overtimeMinutes = 0,
      this.overtimeSemanticLabel,
      this.phoneDecorations = false});
  final CalendarDetailProfile profile;
  final CalendarReadingPalette palette;
  final int day;
  final String shift;
  final Color shiftColor, shiftTextColor;
  final List<String> memos;
  final bool today, outside, red, selected;
  final String? holiday, lunar;
  final int overtimeMinutes;
  final String? overtimeSemanticLabel;
  final bool phoneDecorations;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final g = CalendarDetailGeometry.resolve(
            profile: profile,
            size: box.biggest,
            inherited: DefaultTextStyle.of(context).style,
            direction: Directionality.of(context),
            locale: Localizations.maybeLocaleOf(context),
            day: day,
            hasOvertime: overtimeMinutes > 0,
            phoneDecorations: phoneDecorations);
        final u = g.unit, fill = palette.detailSurface(outside);
        final layout = CalendarOvertimeLayout.resolve(
            theme: profile.theme,
            size: box.biggest,
            unit: u,
            chip: g.chip,
            date: g.date,
            annotation: g.annotation,
            rows: g.memos,
            lineHeight: g.information.lineHeight,
            memoCount: memos.length,
            hasOvertime: overtimeMinutes > 0,
            hasHoliday: holiday != null);
        final ink = palette.detailInk(outside);
        final redInk = CalendarReadingPalette.redOn(fill);
        final annotationInk =
            holiday != null ? redInk : CalendarContrast.lunarInk(ink, fill);
        final memoFill =
            profile.event || profile.diary ? palette.detailMemoSurface : fill;
        final memoInk = CalendarContrast.ensure(ink, memoFill);
        Widget at(Rect r, Widget child) =>
            Positioned.fromRect(rect: r, child: child);
        Widget information(String value, Color color,
                {TextAlign align = TextAlign.center,
                FontWeight weight = FontWeight.w500,
                double scale = 1}) =>
            CompleteCellMemoText(value,
                horizontalInset: 1.5 * u,
                textScaler: TextScaler.noScaling,
                textAlign: align,
                style: TextStyle(
                    fontSize: g.information.fontSize * scale,
                    height: profile.leading,
                    color: color,
                    fontWeight: weight));
        final dateFill = profile.grid ? palette.darkBand : palette.today;
        final outlinedDate =
            phoneDecorations && (profile.diary || profile.editorial);
        final dateInk = today && !profile.underline && !outlinedDate
            ? (red
                ? CalendarReadingPalette.redOn(dateFill)
                : CalendarContrast.ink(dateFill))
            : (red ? redInk : ink);
        Widget date = Container(
            alignment: profile.editorial && phoneDecorations
                ? Alignment.centerRight
                : profile.grid || profile.editorial || profile.event
                    ? Alignment.centerLeft
                    : Alignment.center,
            child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: (profile.grid || profile.diary ? .5 : 2) * u),
                decoration: today && !profile.underline && !outlinedDate
                    ? BoxDecoration(
                        color: dateFill,
                        borderRadius:
                            BorderRadius.circular((profile.event ? 10 : 2) * u))
                    : null,
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$day',
                        maxLines: 1,
                        softWrap: false,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                            fontSize: profile.date * u * layout.dateScale,
                            height: 1.1,
                            fontWeight: today || profile.grid
                                ? FontWeight.w700
                                : FontWeight.w600,
                            decoration: today &&
                                    (profile.underline ||
                                        (profile.editorial && phoneDecorations))
                                ? TextDecoration.underline
                                : null,
                            decorationColor: dateInk,
                            color: dateInk)))));
        if (phoneDecorations && profile.diary && today) {
          date = Container(
              key: const ValueKey('diary-today-outline'),
              decoration: BoxDecoration(
                  color: fill,
                  border: Border.all(color: ink, width: 1.2 * u),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(5.2 * u),
                      topRight: Radius.circular(3 * u),
                      bottomRight: Radius.circular(3 * u))),
              child: date);
        }
        final hasShift = shift.isNotEmpty && shift != '미설정';
        final chip = CalendarShiftChange(
            background: shiftColor,
            foreground: shiftTextColor,
            enabled: !profile.badge && !profile.underline && !profile.editorial,
            surface: fill,
            builder: (bg, fg) => Container(
                key: const ValueKey('detail-shift-background'),
                decoration: BoxDecoration(
                    color: bg,
                    shape: profile.badge ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius:
                        profile.badge || profile.grid || profile.editorial
                            ? null
                            : BorderRadius.circular(2 * u)),
                child: profile.underline || profile.editorial
                    ? null
                    : profile.badge
                        ? Center(
                            child: Text(
                                shift.isEmpty ? '' : shift.characters.first,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                    fontSize: 14 * u,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    color: CalendarContrast.ink(bg))))
                        : ShiftChipLabel(
                            label: shift,
                            color: profile.grid
                                ? fg
                                : CalendarContrast.ensure(fg, bg),
                            proportions: profile.diary
                                ? ShiftChipProportions.diaryCalendar
                                : profile.event
                                    ? ShiftChipProportions.eventCalendar
                                    : ShiftChipProportions.calendarReview)));
        final border = selected
            ? palette.selection
            : today && profile.badge
                ? palette.today
                : palette.detailLine;
        return DecoratedBox(
            decoration: BoxDecoration(color: fill),
            position: DecorationPosition.background,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              if (profile.diary || profile.badge)
                Positioned.fill(
                    child: Padding(
                        padding: EdgeInsets.all(u),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: border, width: today ? 1.4 : .6),
                                borderRadius: BorderRadius.circular(
                                    (profile.badge ? 5 : 2) * u))))),
              at(layout.date, date),
              if (hasShift)
                at(
                    g.chip,
                    profile.editorial && phoneDecorations
                        ? ClipPath(
                            key: const ValueKey('editorial-phone-corner'),
                            clipper: _EditorialCornerClipper(),
                            child: chip)
                        : chip),
              if (holiday != null ||
                  (lunar != null && (overtimeMinutes <= 0 || profile.event)))
                at(
                    layout.annotation,
                    profile.grid
                        ? Padding(
                            padding: EdgeInsets.symmetric(horizontal: .5 * u),
                            child: FittedBox(
                                key: const ValueKey('grid-date-annotation'),
                                alignment: Alignment.centerRight,
                                fit: BoxFit.scaleDown,
                                child: Text(holiday ?? lunar!,
                                    textAlign: TextAlign.right,
                                    textScaler: TextScaler.noScaling,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                        fontSize: g.information.fontSize,
                                        height: profile.leading,
                                        color: annotationInk,
                                        fontWeight: holiday != null
                                            ? FontWeight.w700
                                            : FontWeight.w500))))
                        : Center(
                            child: information(holiday ?? lunar!, annotationInk,
                                scale: layout.annotationScale,
                                align: profile.grid
                                    ? TextAlign.right
                                    : TextAlign.center,
                                weight: holiday != null
                                    ? FontWeight.w700
                                    : FontWeight.w500))),
              if (layout.overtime != null)
                at(
                    layout.overtime!,
                    CalendarOvertimeLabel(
                        minutes: overtimeMinutes,
                        semanticLabel: overtimeSemanticLabel,
                        compactSpaces: profile.event,
                        alignment: profile.event
                            ? Alignment.centerRight
                            : Alignment.center,
                        style: TextStyle(
                            fontSize:
                                g.information.fontSize * layout.annotationScale,
                            height: profile.leading,
                            color: layout.inMemoSlot
                                ? palette.detailMemoText
                                : ink,
                            fontWeight: FontWeight.w600),
                        background: layout.inMemoSlot
                            ? palette.detailMemoSurface
                            : null,
                        border: layout.inMemoSlot ? palette.detailLine : null)),
              for (var i = 0; i < layout.memos.length; i++)
                at(
                    layout.memos[i],
                    Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: memoFill,
                            borderRadius: BorderRadius.circular(2 * u),
                            border: profile.event
                                ? Border.all(
                                    color: palette.detailLine, width: .5)
                                : null),
                        child: information(memos[i], memoInk,
                            scale: layout.memoScale,
                            align: profile.editorial
                                ? TextAlign.left
                                : TextAlign.center))),
              if (selected)
                Positioned.fill(
                    child: IgnorePointer(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: palette.selection, width: 2 * u))))),
            ]));
      });
}

class _EditorialCornerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_EditorialCornerClipper oldClipper) => false;
}
