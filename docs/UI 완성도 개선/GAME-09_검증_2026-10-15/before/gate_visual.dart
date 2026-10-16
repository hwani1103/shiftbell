import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'skin.dart';

String gateCellLabel(LevelSpec level, Cell cell, GameStrings words) {
  for (var i = 0; i < level.gates.length; i++) {
    final g = level.gates[i];
    final pair = i == 0
        ? words.pick('금색', 'Gold')
        : words.pick('자홍색', 'Magenta');
    if (cell == g.trigger)
      return words.pick(
        '$pair 열쇠, ${g.openFor}칸 이동 시간 동안 열림',
        '$pair key, opens for ${g.openFor} cell-times',
      );
    if (cell == g.door) return words.pick('$pair 문', '$pair door');
  }
  return '';
}

/// Matching key/keyhole and segmented clock, driven by the engine timeline.
final class GateVisual {
  void dispose() {}
  void paint(
    Canvas canvas,
    LevelSpec level,
    GateTimeline? timeline,
    double time,
    double pitch,
    GameSkin skin,
  ) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < level.gates.length; i++) {
      final g = level.gates[i];
      final color = skin.gateColors[i];
      final remaining = timeline?.remaining(g.id, time) ?? 0;
      final open = remaining > 0;
      for (final key in [true, false]) {
        final cell = key ? g.trigger : g.door;
        final c = Offset((cell.x + .5) * pitch, (cell.y + .48) * pitch);
        final rect = Rect.fromCenter(
          center: c,
          width: pitch * .64,
          height: pitch * .62,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(pitch * .10)),
          paint
            ..style = PaintingStyle.fill
            ..color = skin.surface.withValues(alpha: .94),
        );
        if (key) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = pitch * .065
            ..color = color;
          canvas.drawCircle(
            c + Offset(-pitch * .12, -pitch * .10),
            pitch * .105,
            paint,
          );
          canvas.drawLine(
            c + Offset(-pitch * .05, -pitch * .03),
            c + Offset(pitch * .18, pitch * .20),
            paint,
          );
          canvas.drawLine(
            c + Offset(pitch * .11, pitch * .13),
            c + Offset(pitch * .19, pitch * .05),
            paint,
          );
          canvas.drawLine(
            c + Offset(pitch * .17, pitch * .19),
            c + Offset(pitch * .25, pitch * .11),
            paint,
          );
        } else {
          final doorway = Rect.fromCenter(
            center: c,
            width: pitch * .42,
            height: pitch * .53,
          );
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = pitch * .045
            ..color = color;
          canvas.drawRRect(
            RRect.fromRectAndRadius(doorway, Radius.circular(pitch * .06)),
            paint,
          );
          if (open) {
            canvas.drawPath(
              Path()
                ..moveTo(doorway.left, doorway.top)
                ..lineTo(doorway.left + pitch * .12, doorway.top + pitch * .07)
                ..lineTo(
                  doorway.left + pitch * .12,
                  doorway.bottom - pitch * .03,
                )
                ..lineTo(doorway.left, doorway.bottom),
              paint,
            );
          } else {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                doorway.deflate(2),
                Radius.circular(pitch * .035),
              ),
              paint
                ..style = PaintingStyle.fill
                ..color = color.withValues(alpha: .20),
            );
            canvas.drawCircle(
              c - Offset(0, pitch * .045),
              pitch * .06,
              paint..color = color,
            );
            canvas.drawPath(
              Path()
                ..moveTo(c.dx - pitch * .027, c.dy)
                ..lineTo(c.dx + pitch * .027, c.dy)
                ..lineTo(c.dx + pitch * .045, c.dy + pitch * .11)
                ..lineTo(c.dx - pitch * .045, c.dy + pitch * .11)
                ..close(),
              paint,
            );
          }
        }
        // Each segment is one cell of travel time. Planning previews the full
        // duration; playback drains these segments using exact gate events.
        final clockRect = Rect.fromCircle(center: c, radius: pitch * .37);
        for (var n = 0; n < g.openFor; n++) {
          final angle = 2 * math.pi / g.openFor, sweep = angle * .72;
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = pitch * .045
            ..color = color.withValues(alpha: .18);
          canvas.drawArc(
            clockRect,
            -math.pi / 2 + n * angle,
            sweep,
            false,
            paint,
          );
          final fraction = timeline == null
              ? 1.0
              : (remaining - n).clamp(0.0, 1.0);
          if (fraction > 0)
            canvas.drawArc(
              clockRect,
              -math.pi / 2 + n * angle,
              sweep * fraction,
              false,
              paint..color = color,
            );
        }
      }
    }
  }
}
