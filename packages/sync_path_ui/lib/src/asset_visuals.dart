import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'presentation.dart';
import 'skin.dart';
import 'visuals.dart';
import 'unit_animation.dart';

// Optional atlas renderers: a future host supplies decoded images.
// The lightweight lab does not bundle or load the archived prototype atlases.
final class PrototypeUnitVisual extends UnitVisual {
  final ui.Image atlas;
  final _paint = Paint()..filterQuality = FilterQuality.medium;
  final _shape = Paint();
  final animation = const UnitAnimationController();
  bool _disposed = false;
  PrototypeUnitVisual(this.atlas);
  @override
  bool get animated => true;
  // Explicit source rectangles retain common body anchors despite imperfect
  // generated sheet spacing. A future asset only replaces these and the atlas.
  Rect source(int color, UnitFacing facing) {
    final column = switch (facing) {
      UnitFacing.down => 0,
      UnitFacing.up => 1,
      UnitFacing.left => 2,
      UnitFacing.right => 3,
    };
    final x = const [100.0, 440.0, 775.0, 1110.0][column];
    final y = const [70.0, 385.0, 695.0][color % 3];
    return Rect.fromLTWH(x, y, column < 2 ? 255 : 220, 290);
  }

  void body(
    Canvas c,
    Offset center,
    double pitch,
    int index,
    UnitFacing facing, {
    double opacity = 1,
    double scale = 1,
    double bob = 0,
    double lean = 0,
    double stride = 0,
    bool happy = false,
    Color? tint,
  }) {
    c.save();
    c.translate(center.dx, center.dy);
    c.scale(scale);
    _shape.color = const Color(0xff172d42).withValues(alpha: .12 * opacity);
    c.drawOval(
      Rect.fromCenter(
        center: Offset(0, pitch * .22),
        width: pitch * .46,
        height: pitch * .12,
      ),
      _shape,
    );
    c.translate(0, -bob);
    c.rotate(lean * (facing == UnitFacing.left ? -1 : 1));
    _shape.color = const Color(0xff34526a).withValues(alpha: opacity);
    for (final sign in [-1, 1]) {
      final walk = stride * sign * pitch * .055;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(sign * pitch * .105 + walk, pitch * .20),
            width: pitch * .13,
            height: pitch * .095,
          ),
          const Radius.circular(4),
        ),
        _shape,
      );
      final handY = happy ? -pitch * .15 : pitch * .075 + walk * .5;
      c.drawCircle(Offset(sign * pitch * .235, handY), pitch * .042, _shape);
    }
    _paint.color = Colors.white.withValues(alpha: opacity);
    _paint.colorFilter = tint == null
        ? null
        : ColorFilter.mode(tint, BlendMode.hue);
    c.drawImageRect(
      atlas,
      source(index, facing),
      Rect.fromCenter(
        center: Offset(0, -pitch * .045),
        width:
            pitch *
            ((facing == UnitFacing.up || facing == UnitFacing.down)
                ? .49
                : .43),
        height: pitch * .56,
      ),
      _paint,
    );
    c.restore();
  }

  @override
  void paint(
    Canvas canvas,
    Offset center,
    double pitch,
    UnitVisualFrame frame,
    GameSkin skin,
  ) {
    final pose = animation.pose(frame);
    if (frame.selected) {
      _shape
        ..color = skin.selection.withValues(alpha: .13)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, pitch * .36, _shape);
      _shape
        ..color = skin.selection
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3;
      canvas.drawCircle(center, pitch * .34, _shape);
      _shape.style = PaintingStyle.fill;
      final top = center + Offset(0, -pitch * .43);
      canvas.drawPath(
        Path()
          ..moveTo(top.dx - 4, top.dy)
          ..lineTo(top.dx + 4, top.dy)
          ..lineTo(top.dx, top.dy + 5)
          ..close(),
        _shape,
      );
    }
    body(
      canvas,
      center,
      pitch,
      frame.paletteIndex,
      frame.facing,
      opacity: pose.opacity,
      scale: pose.scale,
      bob: pose.bob,
      lean: pose.lean,
      stride: pose.stride,
      tint: frame.paletteIndex >= 3
          ? skin.unitColors[frame.paletteIndex % skin.unitColors.length]
          : null,
    );
  }

  @override
  void paintCue(
    Canvas canvas,
    Offset center,
    double pitch,
    VisualCue cue,
    Duration visualTime,
    bool reducedMotion,
    GameSkin skin,
  ) {
    final t = cue.age.inMicroseconds / 1000000;
    if (reducedMotion || t > 1.15) return;
    final fade = (1 - t / 1.15).clamp(0.0, 1.0);
    if (cue.kind == VisualCueKind.goal) {
      final id = cue.unitIds.single;
      final index = (id.codeUnitAt(0) - 65).clamp(0, 4);
      body(
        canvas,
        center,
        pitch,
        index,
        UnitFacing.down,
        opacity: fade,
        bob: math.sin((t / .7).clamp(0.0, 1.0) * math.pi) * pitch * .20,
        happy: true,
        tint: index >= 3
            ? skin.unitColors[index % skin.unitColors.length]
            : null,
      );
    } else {
      final color = cue.kind == VisualCueKind.collision
          ? skin.collision
          : skin.goal;
      _shape
        ..color = color.withValues(alpha: fade)
        ..style = PaintingStyle.fill;
      final n = cue.kind == VisualCueKind.collision ? 6 : 10;
      for (var i = 0; i < n; i++) {
        final angle = i * math.pi * 2 / n;
        final radius = pitch * (.14 + t * .4);
        final p =
            center +
            Offset(
              math.cos(angle) * radius,
              math.sin(angle) * radius - t * pitch * .12,
            );
        canvas.drawCircle(p, 2.2 * fade, _shape);
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    atlas.dispose();
  }
}

final class PrototypeTileVisual extends TileVisual {
  final ui.Image atlas;
  final _paint = Paint()..filterQuality = FilterQuality.medium;
  final _outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  bool _disposed = false;
  PrototypeTileVisual(this.atlas);
  static const sources = [
    Rect.fromLTRB(120, 82, 644, 590),
    Rect.fromLTRB(768, 82, 1287, 590),
    Rect.fromLTRB(1408, 25, 1936, 590),
  ];
  @override
  void paint(Canvas canvas, Rect bounds, TileVisualFrame frame, GameSkin skin) {
    final source =
        sources[frame.blocked
            ? 1
            : frame.goal
            ? 2
            : 0];
    final rect = bounds.deflate(1.5);
    canvas.drawImageRect(atlas, source, rect, _paint);
    if (frame.legalDestination) {
      _outline.color = skin.selection.withValues(alpha: .7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(6)),
        _outline,
      );
      canvas.drawCircle(bounds.center, 2.6, Paint()..color = skin.selection);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    atlas.dispose();
  }
}
