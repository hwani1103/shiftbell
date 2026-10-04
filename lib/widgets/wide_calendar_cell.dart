import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'english_calendar_label.dart';
import '../models/calendar_theme.dart';
import 'fold_calendar_text_scale.dart';

/// Fold inner cells: keep typography responsive without stacking every
/// field vertically. Cover screens never enter this renderer.
class WideCalendarCell extends StatelessWidget {
  const WideCalendarCell(
      {super.key,
      required this.theme,
      required this.day,
      required this.shift,
      required this.shiftColor,
      required this.shiftTextColor,
      required this.memos,
      required this.isToday,
      required this.isOutside,
      required this.isRed,
      this.annotation,
      this.isHoliday = false,
      this.isSelected = false});

  final CalendarThemeId theme;
  final int day;
  final String shift;
  final Color shiftColor, shiftTextColor;
  final List<String> memos;
  final bool isToday, isOutside, isRed, isHoliday, isSelected;
  final String? annotation;

  static bool appliesTo(Size size) =>
      size.shortestSide > 500 &&
      (size.aspectRatio > 1.2 || usesWrappedAnnotations(size));

  static bool usesWrappedAnnotations(Size size) =>
      size.shortestSide > 500 && size.shortestSide / size.longestSide >= .85;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wrapAnnotations = usesWrappedAnnotations(media.size);
    final scaler = media.textScaler.clamp(maxScaleFactor: 1.3);
    final shiftScaler = calendarShiftTextScaler(theme, scaler);
    final colors = Theme.of(context).colorScheme;
    final dark = theme == CalendarThemeId.mainDark;
    final diary = theme == CalendarThemeId.diary;
    final card = theme == CalendarThemeId.materialCard;
    final bold = theme == CalendarThemeId.boldGrid;
    final pill = theme == CalendarThemeId.eventChip;
    final initial = theme == CalendarThemeId.initialBadge;
    final underline = theme == CalendarThemeId.underline;
    final editorial = theme == CalendarThemeId.editorial;
    final plain = theme == CalendarThemeId.minimal;
    final ink = dark
        ? Colors.white
        : diary
            ? const Color(0xFF4A4038)
            : colors.onSurface;
    final muted = dark
        ? Colors.white70
        : diary
            ? const Color(0xFF766657)
            : colors.onSurfaceVariant;
    final red = dark ? Colors.red.shade200 : Colors.red.shade400;
    final frame = bold
        ? Colors.grey.shade600
        : diary
            ? const Color(0xFFE4D9C9)
            : dark
                ? Colors.white24
                : Colors.grey.shade200;
    final radius = BorderRadius.circular(pill
        ? 4
        : diary
            ? 8
            : card
                ? 5
                : 2);

    Widget label(String value, double size, Color color,
            {Key? key,
            FontWeight weight = FontWeight.w600,
            TextAlign align = TextAlign.center,
            bool fixed = false,
            int maxLines = 1}) =>
        key == const ValueKey('shift-badge-text')
        ? EnglishCalendarLabel(value, style: TextStyle(fontSize: size, height: 1.15, color: color, fontWeight: weight), textScaler: shiftScaler, textKey: key)
        : Text(value,
            key: key,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            textScaler: fixed
                ? TextScaler.noScaling
                : key == const ValueKey('shift-badge-text')
                    ? shiftScaler
                    : scaler,
            style: TextStyle(
                fontSize: size,
                height: 1.15,
                color: color,
                fontWeight: weight,
                leadingDistribution: TextLeadingDistribution.even));

    return MediaQuery(
      data: media.copyWith(textScaler: scaler),
      child: LayoutBuilder(builder: (context, bounds) {
        // Measured glyph line height, including fallback fonts and Samsung's
        // font scaling. Reserve the fixed annotation and all three memo rows
        // at the maximum supported scale before allocating the shift band.
        double lineHeight(double size,
            {bool fixed = false, bool shift = false}) {
          final painter = TextPainter(
              text: TextSpan(
                  text: '가9',
                  style: DefaultTextStyle.of(context).style.merge(TextStyle(
                      fontSize: size,
                      height: 1.15,
                      fontWeight: FontWeight.w600))),
              textScaler: fixed
                  ? TextScaler.noScaling
                  : shift
                      ? shiftScaler
                      : scaler,
              textDirection: TextDirection.ltr,
              maxLines: 1)
            ..layout();
          final value = painter.height;
          painter.dispose();
          return value;
        }

        final height = math.max(1.0, bounds.maxHeight - 2);
        final annotationSize = wrapAnnotations ? 9.2 : 8.8;
        final annotationHeight =
            lineHeight(annotationSize, fixed: true) * (wrapAnnotations ? 2 : 1);
        String? annotationText = annotation;
        if (wrapAnnotations && isHoliday && annotation != null) {
          final columnWidth =
              (bounds.maxWidth - (card || diary || pill ? 4 : 0)) * .4;
          final glyphs = annotation!.characters.toList();
          double widthOf(String value) {
            final painter = TextPainter(
                text: TextSpan(
                    text: value,
                    style: DefaultTextStyle.of(context).style.merge(TextStyle(
                        fontSize: annotationSize,
                        height: 1.15,
                        fontWeight: FontWeight.w600))),
                textScaler: TextScaler.noScaling,
                textDirection: TextDirection.ltr)
              ..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          final fitsThree = List.generate((glyphs.length / 3).ceil(),
                  (i) => glyphs.skip(i * 3).take(3).join())
              .every((s) => widthOf(s) <= columnWidth);
          final perLine = fitsThree ? 3 : 2;
          if (fitsThree && glyphs.length >= 4 && glyphs.length <= 6) {
            // Keep both lines at least two characters: 2+2, 2+3, or 3+3.
            final firstLine = glyphs.length ~/ 2;
            annotationText =
                '${glyphs.take(firstLine).join()}\n${glyphs.skip(firstLine).join()}';
          } else {
            annotationText = List.generate((glyphs.length / perLine).ceil(),
                    (i) => glyphs.skip(i * perLine).take(perLine).join())
                .join('\n');
          }
        }
        var shiftSize = 13.5;
        var dateSize = 14.0;
        var memoThreeSize = 8.4;
        // A height-only fit handles unusually short windows. Never shrink a
        // memo because its text is long: the right column uses ellipsis.
        final topInset = initial ? 2.0 : 0.0;
        double headerHeight() => diary
            ? math.max(lineHeight(shiftSize, shift: true) + 3,
                lineHeight(dateSize, fixed: wrapAnnotations) + 2)
            : lineHeight(shiftSize, shift: true) + 3;
        double requiredHeight() =>
            topInset +
            headerHeight() +
            math.max(
                diary
                    ? annotationHeight
                    : lineHeight(dateSize, fixed: wrapAnnotations) +
                        3 +
                        annotationHeight,
                3 * lineHeight(memoThreeSize, fixed: wrapAnnotations)) +
            6;
        for (var i = 0; i < 30 && requiredHeight() > height; i++) {
          shiftSize *= .97;
          if (!wrapAnnotations) {
            dateSize *= .97;
            memoThreeSize *= .97;
          }
        }
        final bandHeight = headerHeight();
        final bodyHeight = math.max(1.0, height - topInset - bandHeight - 4);
        final visibleMemos = memos.take(3).toList();
        final count = visibleMemos.length;
        var memoSize = wrapAnnotations && count <= 2
            ? 10.5
            : count == 1
                ? 11.5
                : count == 2
                    ? 10.5
                    : memoThreeSize;
        // On short wide cells the shift band may need to shrink. Memos must
        // never become more prominent than the shift name in that case.
        memoSize = math.min(memoSize, shiftSize);
        for (var i = 0;
            i < 30 &&
                lineHeight(memoSize, fixed: wrapAnnotations) *
                        math.max(1, count) >
                    bodyHeight;
            i++) {
          memoSize *= .97;
        }
        final outlined = underline || editorial;
        final bandColor = shift.isEmpty
            ? Colors.transparent
            : outlined
                ? shiftColor.withValues(alpha: dark ? .2 : .10)
                : plain
                    ? shiftColor.withValues(alpha: .85)
                    : shiftColor;
        final bandInk = outlined ? ink : shiftTextColor;
        final outsideInk = ink.withValues(alpha: .45);
        final dateInk = isOutside
            ? outsideInk
            : isRed
                ? red
                : ink;
        final todayColor = diary
            ? const Color(0xFFCD8A4A)
            : bold
                ? const Color(0xFF263238)
                : Colors.indigo.shade400;
        final solidToday = !plain && !underline && !editorial && !initial;

        final band = Container(
          key: const ValueKey('wide-shift-band'),
          height: bandHeight,
          padding: EdgeInsets.symmetric(horizontal: editorial ? 0 : 3),
          decoration: BoxDecoration(
              color: initial ? Colors.transparent : bandColor,
              borderRadius: diary
                  ? const BorderRadius.only(topRight: Radius.circular(6))
                  : pill || card || initial
                      ? radius
                      : null),
          foregroundDecoration: BoxDecoration(
              border: underline
                  ? Border(
                      bottom: BorderSide(
                          color: shiftColor, width: shift.isEmpty ? 0 : 2))
                  : null),
          child: shift.isEmpty
              ? null
              : Stack(alignment: Alignment.center, children: [
                  if (editorial)
                    Positioned(
                        left: 0,
                        top: 0,
                        child: ClipPath(
                            key: const ValueKey('wide-editorial-corner'),
                            clipper: _CornerClipper(),
                            child: SizedBox(
                                width: bandHeight,
                                height: bandHeight,
                                child: ColoredBox(color: shiftColor)))),
                  Center(
                      key: const ValueKey('shift-badge-content'),
                      child: initial
                          ? Container(
                              key: const ValueKey('wide-initial-circle'),
                              width: bandHeight,
                              height: bandHeight,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: shiftColor, shape: BoxShape.circle),
                              child: label(shift.characters.first, shiftSize,
                                  shiftTextColor,
                                  key: const ValueKey('shift-badge-text'),
                                  weight: FontWeight.bold))
                          : Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: editorial ? bandHeight : 0),
                              child: label(shift, shiftSize, bandInk,
                                  key: const ValueKey('shift-badge-text'),
                                  weight: FontWeight.bold))),
                ]),
        );
        final dateDiameter = lineHeight(dateSize, fixed: wrapAnnotations) + 2;
        final dateLabel = Container(
            key: const ValueKey('wide-date-label'),
            width: underline ? dateDiameter : null,
            height: underline ? dateDiameter : null,
            alignment: underline ? Alignment.center : null,
            padding: EdgeInsets.symmetric(horizontal: underline ? 0 : 3, vertical: 1),
            decoration: isToday && !initial
                ? BoxDecoration(
                    color: solidToday ? todayColor : null,
                    borderRadius: BorderRadius.circular(bold ? 2 : 20))
                : null,
            foregroundDecoration: isToday && !initial
                ? BoxDecoration(
                    shape: underline ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: underline ? null : BorderRadius.circular(bold ? 2 : 20),
                    border: underline
                        ? Border.all(color: todayColor, width: 1.4)
                        : solidToday
                            ? null
                            : Border.all(color: todayColor, width: 1.2))
                : null,
            child: label('$day', dateSize,
                isToday && solidToday ? Colors.white : dateInk,
                fixed: wrapAnnotations,
                weight: isToday || bold ? FontWeight.bold : FontWeight.w600));
        final annotationLabel = SizedBox(
            height: annotationHeight,
            child: Center(
                child: annotation == null
                    ? null
                    : label(annotationText!, annotationSize,
                        isHoliday ? red : muted,
                        key: const ValueKey('wide-annotation'),
                        fixed: true,
                        maxLines: wrapAnnotations && isHoliday ? 2 : 1)));
        final dateColumn = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [dateLabel, const SizedBox(height: 1), annotationLabel]);
        return Container(
          key: const ValueKey('wide-cell-frame'),
          clipBehavior: diary ? Clip.antiAlias : Clip.none,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding:
              EdgeInsets.symmetric(horizontal: card || diary || pill ? 2 : 0),
          decoration: BoxDecoration(
              color: bold
                  ? (isOutside
                      ? colors.surfaceContainerHighest.withValues(alpha: .3)
                      : Colors.white)
                  : dark
                      ? const Color(0xFF20232B)
                      : diary
                          ? const Color(0xFFFFFBF4)
                          : card
                              ? const Color(0xFFF0F7FF)
                              : null,
              borderRadius: card || diary || initial ? radius : null),
          foregroundDecoration: BoxDecoration(
              borderRadius: card || diary || initial ? radius : null,
              border: initial && isToday
                  ? Border.all(color: Colors.indigo.shade400, width: 1.4)
                  : isSelected
                      ? Border.all(color: colors.secondary, width: 1)
                      : card || diary || bold || initial
                          ? Border.all(color: frame, width: .6)
                          : plain
                              ? Border(left: BorderSide(color: frame))
                              : null),
          // Draw borders over content: decoration padding must not steal the
          // measured body height at the largest font setting.
          child: Column(children: [
            if (initial) SizedBox(height: topInset),
            if (diary)
              SizedBox(
                key: const ValueKey('wide-diary-header'),
                height: bandHeight,
                child: Row(children: [
                  Expanded(flex: 4, child: Center(child: dateLabel)),
                  Expanded(flex: 6, child: band),
                ]),
              )
            else
              band,
            Expanded(
                child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                    flex: 4,
                    child: diary ? Center(child: annotationLabel) : dateColumn),
                Expanded(
                    flex: 6,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: visibleMemos
                                .map((memo) => Expanded(
                                        child: Center(
                                      child: Container(
                                          width: double.infinity,
                                          decoration: pill
                                              ? BoxDecoration(
                                                  color: colors
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(3))
                                              : null,
                                          child: label(memo, memoSize, muted,
                                              fixed: wrapAnnotations,
                                              align: diary || bold || editorial
                                                  ? TextAlign.left
                                                  : TextAlign.center)),
                                    )))
                                .toList()))),
              ]),
            )),
          ]),
        );
      }),
    );
  }
}

class _CornerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_CornerClipper oldClipper) => false;
}
