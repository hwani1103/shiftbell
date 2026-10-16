import 'package:flutter/material.dart';
import '../theme/calendar_reading_palette.dart';

/// Preserve the semantic color and silhouette, including the triangle's
/// diagonal edge. Paint-only protection does not consume the cell's layout.
class CalendarShiftMarker extends StatelessWidget {
  const CalendarShiftMarker(
      {super.key,
      required this.color,
      required this.surface,
      required this.width,
      required this.height,
      this.triangle = false});
  final Color color, surface;
  final double width, height;
  final bool triangle;
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size(width, height),
      painter: _MarkerPainter(color, surface, triangle));
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.color, this.surface, this.triangle);
  final Color color, surface;
  final bool triangle;
  @override
  void paint(Canvas canvas, Size size) {
    final path = triangle
        ? (Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(0, size.height)
          ..close())
        : (Path()..addRect(Offset.zero & size));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(path, Paint()..color = color);
    final edge = CalendarContrast.chipOutline(color, surface)?.top;
    if (edge != null)
      canvas.drawPath(
          path,
          Paint()
            ..color = edge.color
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                edge.width.clamp(0.0, size.shortestSide / 4).toDouble() * 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter old) =>
      color != old.color || surface != old.surface || triangle != old.triangle;
}
