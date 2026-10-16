import 'package:flutter/material.dart';

/// The final row keeps two date cells and merges the remaining five columns.
/// Its outer outline belongs to this table, including below the summary.
class CalendarMergedSummaryBorder extends TableBorder {
  const CalendarMergedSummaryBorder({required BorderSide side})
      : super(
          top: side,
          right: side,
          bottom: side,
          left: side,
          horizontalInside: side,
          verticalInside: side,
        );

  @override
  void paint(Canvas canvas, Rect rect,
      {required Iterable<double> rows, required Iterable<double> columns}) {
    final rowOffsets = rows.toList(growable: false);
    if (rowOffsets.isEmpty) {
      super.paint(canvas, rect, rows: rowOffsets, columns: columns);
      return;
    }
    if (verticalInside.style == BorderStyle.solid) {
      final paint = Paint()
        ..color = verticalInside.color
        ..strokeWidth = verticalInside.width
        ..style = PaintingStyle.stroke;
      final path = Path();
      var index = 0;
      for (final x in columns) {
        final bottom = index < 2 ? rect.bottom : rect.top + rowOffsets.last;
        path.moveTo(rect.left + x, rect.top);
        path.lineTo(rect.left + x, bottom);
        index++;
      }
      canvas.drawPath(path, paint);
    }
    // Horizontal separators and the complete outer border are painted once,
    // after the vertical strokes, just as in a regular Flutter table.
    super.paint(canvas, rect, rows: rowOffsets, columns: const []);
  }
}
