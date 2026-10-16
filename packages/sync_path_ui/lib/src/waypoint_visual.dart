import 'package:flutter/material.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'skin.dart';

/// Every explicit stop, including returns to the start, grouped by ball.
Map<Cell, Map<int, int>> waypointGroups(List<UnitRoute> routes) {
  final groups = <Cell, Map<int, int>>{};
  for (var i = 0; i < routes.length; i++) {
    for (final end in routes[i].endpoints) {
      groups
          .putIfAbsent(end, () => {})
          .update(i, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return groups;
}

/// Stable corner per ball, so overlapping stops never overwrite one another.
void paintWaypoints(
  Canvas canvas,
  List<UnitRoute> routes,
  double pitch,
  GameSkin skin,
) {
  final paint = Paint();
  for (final entry in waypointGroups(routes).entries) {
    final cell = entry.key;
    for (final visit in entry.value.entries) {
      final i = visit.key;
      final x = (cell.x + (i.isOdd ? .76 : .12)) * pitch;
      final y = (cell.y + (i >= 2 ? .65 : .08)) * pitch;
      final color = skin.unitColors[i % skin.unitColors.length];
      final pole = Offset(x, y), foot = Offset(x, y + pitch * .25);
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = skin.surface;
      canvas.drawLine(pole, foot, paint);
      paint
        ..strokeWidth = 1.7
        ..color = color;
      canvas.drawLine(pole, foot, paint);
      for (var n = 0; n < visit.value; n++) {
        final yy = y + pitch * .055 * n;
        if (n < 3) {
          final flag = Path()
            ..moveTo(x, yy)
            ..lineTo(x + pitch * .17, yy + pitch * .035)
            ..lineTo(x + pitch * .12, yy + pitch * .10)
            ..lineTo(x, yy + pitch * .08)
            ..close();
          canvas.drawPath(
            flag,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = skin.surface,
          );
          canvas.drawPath(
            flag,
            paint
              ..style = PaintingStyle.fill
              ..color = color,
          );
        } else {
          canvas.drawCircle(
            Offset(
              x + pitch * (.05 + .04 * ((n - 3) % 4)),
              y + pitch * (.23 + .035 * ((n - 3) ~/ 4)),
            ),
            pitch * .016,
            paint
              ..style = PaintingStyle.fill
              ..color = color,
          );
        }
      }
      final c = Offset(x + pitch * .067, y + pitch * .047), r = pitch * .022;
      paint
        ..color = skin.onPrimary
        ..style = PaintingStyle.fill
        ..strokeWidth = 1.3;
      switch (i % 4) {
        case 0:
          canvas.drawCircle(c, r, paint);
        case 1:
          canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), paint);
        case 2:
          canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), paint);
          canvas.drawLine(c - Offset(0, r), c + Offset(0, r), paint);
        case 3:
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - r)
              ..lineTo(c.dx + r, c.dy)
              ..lineTo(c.dx, c.dy + r)
              ..lineTo(c.dx - r, c.dy)
              ..close(),
            paint,
          );
      }
    }
  }
}
