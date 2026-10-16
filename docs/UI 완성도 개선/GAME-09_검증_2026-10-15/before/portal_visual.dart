import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'skin.dart';

String portalCellLabel(LevelSpec level, Cell cell, GameStrings words) {
  for (var i = 0; i < level.portals.length; i++) {
    final p = level.portals[i];
    final color = i == 0
        ? words.pick('청록색', 'Teal')
        : words.pick('보라색', 'Purple');
    if (cell == p.entry)
      return words.pick(
        '$color 포탈 입구, 여러 번 사용',
        '$color portal entrance, reusable',
      );
    if (cell == p.exit) return words.pick('$color 포탈 출구', '$color portal exit');
  }
  return '';
}

/// Pure presentation: rings and transfer feedback never delay the logical clock.
final class PortalVisual {
  final _paint = Paint();
  void dispose() {}

  void paint(
    Canvas canvas,
    LevelSpec level,
    SimulationTrace? trace,
    double time,
    double pitch,
    GameSkin skin,
    bool reducedMotion,
  ) {
    for (var i = 0; i < level.portals.length; i++) {
      final p = level.portals[i];
      final color = i == 0 ? skin.portal : skin.selection;
      for (final isEntry in [true, false]) {
        final cell = isEntry ? p.entry : p.exit;
        final center = Offset((cell.x + .5) * pitch, (cell.y + .5) * pitch);
        final rect = Rect.fromCircle(center: center, radius: pitch * .32);
        _paint
          ..style = PaintingStyle.fill
          ..color = skin.surface.withValues(alpha: .95);
        canvas.drawCircle(center, pitch * .34, _paint);
        _paint..color = color.withValues(alpha: .14);
        canvas.drawCircle(center, pitch * .32, _paint);
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color;
        if (isEntry) {
          canvas.drawCircle(center, pitch * .32, _paint);
          canvas.drawCircle(center, pitch * .24, _paint..strokeWidth = 1);
        } else {
          for (var k = 0; k < 4; k++) {
            canvas.drawArc(
              rect,
              k * math.pi / 2 + .13,
              math.pi / 2 - .26,
              false,
              _paint,
            );
          }
        }
        // Inward/outward chevrons distinguish endpoints without color alone.
        final sign = isEntry ? 1.0 : -1.0;
        for (final side in [-1.0, 1.0]) {
          final x = center.dx + side * pitch * .23;
          final tip = x - side * sign * pitch * .065;
          final path = Path()
            ..moveTo(x, center.dy - pitch * .05)
            ..lineTo(tip, center.dy)
            ..lineTo(x, center.dy + pitch * .05);
          canvas.drawPath(path, _paint..strokeWidth = 1.8);
        }
        if (!reducedMotion && trace != null) {
          for (final e in trace.portals) {
            final age = time - e.timeUnits;
            if (e.portalId != p.id || age < 0 || age > .65) continue;
            _paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = color.withValues(alpha: (1 - age / .65) * .8);
            canvas.drawCircle(center, pitch * (.23 + .20 * age / .65), _paint);
          }
        }
      }
    }
  }
}
