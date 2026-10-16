import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/calendar_theme.dart';

/// OT changes only the day's information budget. Shift chips keep their size.
class CalendarOvertimeLayout {
  const CalendarOvertimeLayout(this.date, this.annotation, this.memos,
      {this.overtime,
      this.dateScale = 1,
      this.memoScale = 1,
      this.annotationScale = 1,
      this.inMemoSlot = false});
  final Rect date, annotation;
  final List<Rect> memos;
  final Rect? overtime;
  final double dateScale, memoScale, annotationScale;
  final bool inMemoSlot;

  static CalendarOvertimeLayout resolve(
      {required CalendarThemeId theme,
      required Size size,
      required double unit,
      required Rect chip,
      required Rect date,
      required Rect annotation,
      required List<Rect> rows,
      required double lineHeight,
      required int memoCount,
      required bool hasOvertime,
      required bool hasHoliday}) {
    final count = memoCount.clamp(0, 3);
    if (!hasOvertime)
      return CalendarOvertimeLayout(
          date, annotation, rows.take(count).toList());
    if (theme == CalendarThemeId.eventChip) {
      return CalendarOvertimeLayout(date, annotation, rows.take(count).toList(),
          overtime: Rect.fromLTRB(
              date.right + unit, date.top, size.width - 2 * unit, date.bottom));
    }
    if (!hasHoliday)
      return CalendarOvertimeLayout(date, annotation, rows.take(count).toList(),
          overtime: annotation);
    final roomy = {
      CalendarThemeId.boldGrid,
      CalendarThemeId.diary,
      CalendarThemeId.underline,
      CalendarThemeId.editorial
    }.contains(theme);
    if (!roomy && count < 3) {
      return CalendarOvertimeLayout(
          date, annotation, rows.skip(1).take(count).toList(),
          overtime: rows.first, inMemoSlot: true);
    }
    final gap = unit;
    final bottom = size.height - 2 * unit;
    if (roomy) {
      final top = (theme == CalendarThemeId.boldGrid
              ? chip.bottom
              : annotation.bottom) +
          gap;
      final row = rows.first;
      final needed =
          lineHeight + gap + count * row.height + math.max(0, count - 1) * gap;
      final scale = needed <= bottom - top
          ? 1.0
          : math.min(1.0, math.max(.01, bottom - top - count - 1) / needed);
      final pixelRoom = scale < 1 ? 1.0 : 0.0;
      final ot = Rect.fromLTWH(
          row.left, top, row.width, lineHeight * scale + pixelRoom);
      final preferredTop = math.max(row.top, ot.bottom + gap * scale);
      final block = count * (row.height * scale + pixelRoom) +
          math.max(0, count - 1) * gap * scale;
      final memoTop = math.min(preferredTop, bottom - block);
      return CalendarOvertimeLayout(
          date,
          annotation,
          List.generate(
              count,
              (i) => Rect.fromLTWH(
                  row.left,
                  memoTop + i * ((row.height + gap) * scale + pixelRoom),
                  row.width,
                  row.height * scale + pixelRoom)),
          overtime: ot,
          memoScale: scale,
          annotationScale: scale);
    }
    // Only holiday + OT + three memos invokes this compact hierarchy.
    // Date/memos lose less size than holiday/OT; all four values remain separate.
    final main = theme == CalendarThemeId.mainWhite;
    final top = chip.bottom + .5 * unit;
    final dateHeight = date.height * .96;
    final annotationHeight = lineHeight * .82;
    final rowHeight = rows.first.height * .96;
    final needed =
        dateHeight + 2 * annotationHeight + 3 * rowHeight + 6 * .5 * unit;
    // TextPainter rounds line metrics to physical font pixels. Reserve one
    // logical pixel per compressed line instead of multiplying rounded heights.
    final scale = math.min(1.0, math.max(.01, bottom - top - 6) / needed);
    final spacing = .5 * unit * scale;
    var y = top;
    Rect take(double height) {
      final result = Rect.fromLTWH(
          annotation.left, y, annotation.width, height * scale + 1);
      y = result.bottom + spacing;
      return result;
    }

    late Rect d, a, ot;
    if (main) {
      a = take(annotationHeight);
      ot = take(annotationHeight);
      d = take(dateHeight);
    } else {
      d = take(dateHeight);
      a = take(annotationHeight);
      ot = take(annotationHeight);
    }
    final remaining =
        math.max(0.0, bottom - (y + 3 * (rowHeight * scale + 1) + 2 * spacing));
    y += remaining / 2;
    return CalendarOvertimeLayout(
        d, a, List.generate(3, (_) => take(rowHeight)),
        overtime: ot,
        dateScale: .96 * scale,
        memoScale: .96 * scale,
        annotationScale: .82 * scale);
  }
}
