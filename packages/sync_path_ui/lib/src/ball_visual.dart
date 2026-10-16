import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'ball_rotation.dart';
import 'presentation.dart';
import 'skin.dart';
import 'unit_animation.dart';
import 'visuals.dart';

/// Sphere markings rotate in 3D and project onto a 2D board. No bitmap assets.
final class RollingBallVisual extends UnitVisual {
  final _paint = Paint();
  final _shaders = <(int, int, int, double), Shader>{};
  final _clips = <double, Path>{};
  final _matrix = Float64List(16)
    ..[10] = 1
    ..[15] = 1;
  final _animation = const UnitAnimationController();
  static final _normals = <(double, double, double)>[
    (1, 0, 0),
    (-1, 0, 0),
    (0, 1, 0),
    (0, -1, 0),
    (0, 0, 1),
    (0, 0, -1),
    for (final x in [-1.0, 1.0])
      for (final y in [-1.0, 1.0])
        for (final z in [-1.0, 1.0])
          (x / math.sqrt(3), y / math.sqrt(3), z / math.sqrt(3)),
  ];
  static final _motifs = <Path>[
    Path()..addOval(const Rect.fromLTWH(-1, -1, 2, 2)),
    Path()..addRect(const Rect.fromLTWH(-1, -.28, 2, .56)),
    Path()
      ..addRect(const Rect.fromLTWH(-1, -.28, 2, .56))
      ..addRect(const Rect.fromLTWH(-.28, -1, .56, 2)),
    Path()
      ..moveTo(0, -1)
      ..lineTo(1, 0)
      ..lineTo(0, 1)
      ..lineTo(-1, 0)
      ..close(),
    _star(),
  ];
  static Path _star() {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? 1.0 : .43;
      final x = math.cos(angle) * r, y = math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool get animated => true;
  @override
  IconData legendIcon(int index) => switch (index % 5) {
    0 => Icons.circle,
    1 => Icons.remove_rounded,
    2 => Icons.add_rounded,
    3 => Icons.diamond_rounded,
    _ => Icons.star_rounded,
  };

  void _body(
    Canvas canvas,
    Offset center,
    double pitch,
    int index,
    BallRotation rotation,
    GameSkin skin, {
    double scale = 1,
    double jump = 0,
    double opacity = 1,
  }) {
    final radius = pitch * BallRotation.radiusCells;
    final color = skin.unitColors[index % skin.unitColors.length];
    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = skin.text.withValues(alpha: .12 * opacity);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, radius * .8),
        width: radius * 1.8,
        height: radius * .5,
      ),
      _paint,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy - jump);
    canvas.scale(scale);
    _paint.shader = _shaders.putIfAbsent(
      (color.toARGB32(), skin.surface.toARGB32(), skin.text.toARGB32(), radius),
      () => RadialGradient(
        center: const Alignment(-.4, -.45),
        radius: 1,
        colors: [
          Color.lerp(color, skin.surface, .35)!,
          color,
          Color.lerp(color, skin.text, .28)!,
        ],
        stops: const [0, .55, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    _paint.color = Colors.white.withValues(alpha: opacity);
    canvas.drawCircle(Offset.zero, radius, _paint);
    _paint
      ..shader = null
      ..color = skin.onPrimary.withValues(alpha: .9 * opacity);
    canvas.clipPath(
      _clips.putIfAbsent(
        radius,
        () =>
            Path()
              ..addOval(Rect.fromCircle(center: Offset.zero, radius: radius)),
      ),
    );
    // The tangent plane shrinks at the edge; markings disappear behind the ball.
    // Reuse the transform buffer and static motifs rather than frame assets.
    for (final normal in _normals) {
      final (nx, ny, nz) = normal;
      final (px, py, pz) = rotation.rotate(nx, ny, nz);
      if (pz <= .015) continue;
      final length = math.sqrt(nx * nx + nz * nz);
      final (ux, uy, uz) = length < .01
          ? (1.0, 0.0, 0.0)
          : (nz / length, 0.0, -nx / length);
      final vx = ny * uz - nz * uy;
      final vy = nz * ux - nx * uz;
      final vz = nx * uy - ny * ux;
      final (ax, ay, _) = rotation.rotate(ux, uy, uz);
      final (bx, by, _) = rotation.rotate(vx, vy, vz);
      final size = radius * .26;
      _matrix[0] = ax * size;
      _matrix[1] = ay * size;
      _matrix[4] = bx * size;
      _matrix[5] = by * size;
      _matrix[12] = px * radius;
      _matrix[13] = py * radius;
      canvas.save();
      canvas.transform(_matrix);
      canvas.drawPath(_motifs[index % _motifs.length], _paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  void paint(
    Canvas canvas,
    Offset center,
    double pitch,
    UnitVisualFrame frame,
    GameSkin skin,
  ) {
    final pose = _animation.pose(frame);
    final selectedColor =
        skin.unitColors[frame.paletteIndex % skin.unitColors.length];
    if (frame.selected) {
      _paint
        ..shader = null
        ..color = selectedColor.withValues(alpha: .20)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, pitch * .38, _paint);
      _paint
        ..color = selectedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(center, pitch * .35, _paint);
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - 4, center.dy - pitch * .45)
          ..lineTo(center.dx + 4, center.dy - pitch * .45)
          ..lineTo(center.dx, center.dy - pitch * .38)
          ..close(),
        _paint..style = PaintingStyle.fill,
      );
    }
    // No gait bob during travel: the ball rolls along its logical ground path.
    _body(
      canvas,
      center,
      pitch,
      frame.paletteIndex,
      frame.ballRotation,
      skin,
      scale: pose.scale * (frame.selected ? 1.08 : 1),
      opacity: pose.opacity * (frame.planning && !frame.selected ? .65 : 1),
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
      final index = (id.codeUnitAt(0) - 65).clamp(
        0,
        skin.unitColors.length - 1,
      );
      _body(
        canvas,
        center,
        pitch,
        index,
        cue.ballRotation,
        skin,
        opacity: fade,
        jump: math.sin((t / .7).clamp(0.0, 1.0) * math.pi) * pitch * .2,
      );
    } else {
      _paint
        ..shader = null
        ..style = PaintingStyle.fill
        ..color =
            (cue.kind == VisualCueKind.collision ? skin.collision : skin.goal)
                .withValues(alpha: fade);
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3;
        final radius = pitch * (.14 + t * .4);
        canvas.drawCircle(
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
          2 * fade,
          _paint,
        );
      }
    }
  }

  @override
  void dispose() {
    _shaders.clear();
    _clips.clear();
  }
}
