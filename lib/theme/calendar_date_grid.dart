import 'package:flutter/material.dart';

/// Owns date-grid strokes independently of fitted cell contents. The trailing
/// action/legend area is outside this outline; card themes keep their own edges.
class CalendarDateGrid extends CustomPainter {
  const CalendarDateGrid({
    required this.side,
    required this.headerHeight,
    required this.rowHeight,
    required this.lastRowColumns,
    this.horizontalRows = true,
  });
  final BorderSide side;
  final double headerHeight, rowHeight;
  final int lastRowColumns;
  final bool horizontalRows;

  @override
  void paint(Canvas canvas, Size size) {
    if (side.style == BorderStyle.none || rowHeight <= 0) return;
    final half = side.width / 2;
    final top = headerHeight;
    final split = top + rowHeight * 5;
    final bottom = top + rowHeight * 6 - half;
    final end = size.width * lastRowColumns / 7;
    final path = Path();
    void line(double x1, double y1, double x2, double y2) {
      path.moveTo(x1, y1);
      path.lineTo(x2, y2);
    }

    // Keep outside strokes inside the available paint bounds.
    line(half, top, size.width - half, top);
    for (var col = 0; col <= 7; col++) {
      final x = col == 0
          ? half
          : col == 7
              ? size.width - half
              : size.width * col / 7;
      line(x, top, x, col <= lastRowColumns ? bottom : split);
    }
    if (horizontalRows) {
      for (var row = 1; row <= 5; row++) {
        line(half, top + rowHeight * row, size.width - half,
            top + rowHeight * row);
      }
    } else {
      // Minimal lines stay vertical; only close the exposed fifth-row edge.
      line(end, split, size.width - half, split);
    }
    line(half, bottom, end, bottom);
    canvas.drawPath(
        path,
        Paint()
          ..color = side.color
          ..strokeWidth = side.width
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(CalendarDateGrid oldDelegate) =>
      side != oldDelegate.side ||
      headerHeight != oldDelegate.headerHeight ||
      rowHeight != oldDelegate.rowHeight ||
      lastRowColumns != oldDelegate.lastRowColumns ||
      horizontalRows != oldDelegate.horizontalRows;
}

/// Date strokes belong to each scrolling month table, never the viewport.
/// The existing painter keeps the UI52 outline and leaves actions unboxed.
class CalendarDateGridBorder extends TableBorder {
  const CalendarDateGridBorder({
    required this.side,
    required this.lastRowColumns,
    this.horizontalRows = true,
  });

  final BorderSide side;
  final int lastRowColumns;
  final bool horizontalRows;

  @override
  bool get isUniform => false;

  @override
  void paint(Canvas canvas, Rect rect,
      {required Iterable<double> rows, required Iterable<double> columns}) {
    final offsets = rows.toList(growable: false);
    if (offsets.length != 6) return; // weekday header and six date rows
    canvas.save();
    canvas.translate(rect.left, rect.top);
    CalendarDateGrid(
      side: side,
      headerHeight: offsets.first,
      rowHeight: (rect.height - offsets.first) / 6,
      lastRowColumns: lastRowColumns,
      horizontalRows: horizontalRows,
    ).paint(canvas, rect.size);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDateGridBorder &&
      side == other.side &&
      lastRowColumns == other.lastRowColumns &&
      horizontalRows == other.horizontalRows;

  @override
  int get hashCode => Object.hash(side, lastRowColumns, horizontalRows);
}
