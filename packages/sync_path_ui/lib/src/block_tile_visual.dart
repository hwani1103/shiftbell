import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'skin.dart';
import 'visuals.dart';

/// Quiet beveled blocks; chapters change accent colors, never geometry/rules.
final class BlockTileVisual extends TileVisual {
  final _paint = Paint();
  final _shaders = <(int, int, double, double), Shader>{};
  @override
  void paint(Canvas canvas, Rect bounds, TileVisualFrame frame, GameSkin skin) {
    final accent = switch (frame.chapter % 6) {
      0 => skin.primary,
      1 => skin.goal,
      2 => skin.selection,
      3 => skin.unitColors[4 % skin.unitColors.length],
      4 => skin.unitColors[1 % skin.unitColors.length],
      _ => skin.unitColors[2 % skin.unitColors.length],
    };
    final tile = bounds.deflate(2);
    final depth = frame.blocked ? 3.0 : 1.5;
    final face = Rect.fromLTRB(
      tile.left,
      tile.top,
      tile.right,
      tile.bottom - depth,
    );
    final radius = Radius.circular(GameMetrics.cellRadius);
    final base = frame.blocked
        ? Color.lerp(skin.blocked, accent, .18)!
        : Color.lerp(
            skin.surface,
            frame.goal ? skin.goal : accent,
            frame.goal ? .12 : .06,
          )!;
    final top = Color.lerp(base, skin.surface, frame.blocked ? .18 : .3)!;
    final destination = frame.destinationColor ?? skin.selection;
    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = skin.text.withValues(alpha: frame.blocked ? .15 : .06);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile.shift(const Offset(0, 1)), radius),
      _paint,
    );
    _paint.color = Color.lerp(base, skin.text, frame.blocked ? .24 : .10)!;
    canvas.drawRRect(RRect.fromRectAndRadius(tile, radius), _paint);
    final local = Rect.fromLTWH(0, 0, face.width, face.height);
    _paint.shader = _shaders.putIfAbsent(
      (top.toARGB32(), base.toARGB32(), face.width, face.height),
      () => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [top, base],
      ).createShader(local),
    );
    _paint.color = Colors.white;
    canvas.save();
    canvas.translate(face.left, face.top);
    canvas.drawRRect(RRect.fromRectAndRadius(local, radius), _paint);
    canvas.restore();
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = frame.blocked
          ? skin.surface.withValues(alpha: .20)
          : Color.lerp(skin.border, accent, .16)!;
    canvas.drawRRect(RRect.fromRectAndRadius(face.deflate(.4), radius), _paint);
    _surfaceDetail(canvas, face, frame, skin);
    if (frame.blocked) {
      _paint.color = skin.surface.withValues(alpha: .20);
      canvas.drawLine(
        Offset(face.left + 8, face.top + 3),
        Offset(face.right - 8, face.top + 3),
        _paint,
      );
      return;
    }
    if (frame.goal) {
      final center = face.center, radius = bounds.width * .30;
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5;
        final r = i.isEven ? radius : radius * .46;
        final p = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          star.moveTo(p.dx, p.dy);
        } else {
          star.lineTo(p.dx, p.dy);
        }
      }
      star.close();
      _paint
        ..style = PaintingStyle.fill
        ..color = skin.goalStar;
      canvas.drawPath(star, _paint);
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = skin.goalStarOutline;
      canvas.drawPath(star, _paint);
    }
    if (frame.legalDestination) {
      _paint
        ..style = PaintingStyle.fill
        ..color = destination.withValues(alpha: .18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(face.deflate(1.5), radius),
        _paint,
      );
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = destination;
      canvas.drawRRect(
        RRect.fromRectAndRadius(face.deflate(1.5), radius),
        _paint,
      );
      if (!frame.goal) {
        _paint
          ..style = PaintingStyle.fill
          ..color = destination.withValues(alpha: .7);
        canvas.drawCircle(face.center, 3, _paint);
      }
    }
  }

  void _surfaceDetail(
    Canvas canvas,
    Rect face,
    TileVisualFrame frame,
    GameSkin skin,
  ) {
    if (frame.goal) return;
    final style = (frame.chapter ~/ 2) % 5;
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = (frame.blocked ? skin.surface : skin.border).withValues(
        alpha: frame.blocked ? .15 : .40,
      );
    switch (style) {
      case 0:
        break;
      case 1:
        final corner = Offset(face.right - 5, face.bottom - 5);
        canvas.drawLine(corner, corner - const Offset(5, 0), _paint);
        canvas.drawLine(corner, corner - const Offset(0, 5), _paint);
      case 2:
        canvas.drawLine(
          Offset(face.left + 6, face.bottom - 5),
          Offset(face.right - 6, face.bottom - 5),
          _paint,
        );
      case 3:
        final corner = Offset(face.right - 7, face.bottom - 7);
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx, corner.dy - 3)
            ..lineTo(corner.dx + 3, corner.dy)
            ..lineTo(corner.dx, corner.dy + 3)
            ..lineTo(corner.dx - 3, corner.dy)
            ..close(),
          _paint,
        );
      case 4:
        canvas.drawRRect(
          RRect.fromRectAndRadius(face.deflate(4), const Radius.circular(4)),
          _paint,
        );
    }
  }

  @override
  void dispose() {
    _shaders.clear();
  }
}
