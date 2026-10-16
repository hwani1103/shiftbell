import 'package:flutter/material.dart';
import 'presentation.dart';
import 'skin.dart';

/// Replace the temporary shape without changing a logical Unit or simulation.
/// Sprites may bob/jump around center; the board retains the true center marker.
abstract class UnitVisual {
  const UnitVisual();
  bool get animated => false;
  IconData legendIcon(int index) => switch (index % 3) {
    0 => Icons.circle,
    1 => Icons.square,
    _ => Icons.change_history,
  };
  void paint(
    Canvas canvas,
    Offset center,
    double pitch,
    UnitVisualFrame frame,
    GameSkin skin,
  );

  /// Optional decorative reactions to exact trace events. Arrived characters
  /// may remain visually here while already absent from the logical world.
  /// This is a render snapshot, not a callback for playing audio every frame.
  void paintCue(
    Canvas canvas,
    Offset center,
    double pitch,
    VisualCue cue,
    Duration visualTime,
    bool reducedMotion,
    GameSkin skin,
  ) {}
  void dispose() {}
}

final class BasicUnitVisual extends UnitVisual {
  const BasicUnitVisual();
  @override
  void paint(
    Canvas canvas,
    Offset center,
    double pitch,
    UnitVisualFrame frame,
    GameSkin skin,
  ) {
    final paint = Paint()
      ..color = skin.unitColors[frame.paletteIndex % skin.unitColors.length];
    switch (frame.paletteIndex % 3) {
      case 0:
        canvas.drawCircle(center, GameMetrics.markerRadius, paint);
      case 1:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: GameMetrics.markerRadius * 2,
              height: GameMetrics.markerRadius * 2,
            ),
            const Radius.circular(4),
          ),
          paint,
        );
      case 2:
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - GameMetrics.markerRadius - 3)
            ..lineTo(
              center.dx + GameMetrics.markerRadius + 2,
              center.dy + GameMetrics.markerRadius,
            )
            ..lineTo(
              center.dx - GameMetrics.markerRadius - 2,
              center.dy + GameMetrics.markerRadius,
            )
            ..close(),
          paint,
        );
    }
  }
}

final class TileVisualFrame {
  final bool blocked, goal, legalDestination;
  final int chapter;
  final Color? destinationColor;
  const TileVisualFrame({
    required this.blocked,
    required this.goal,
    required this.legalDestination,
    this.chapter = 0,
    this.destinationColor,
  });
}

abstract class TileVisual {
  const TileVisual();
  void paint(Canvas canvas, Rect bounds, TileVisualFrame frame, GameSkin skin);
  void dispose() {}
}

final class BasicTileVisual extends TileVisual {
  const BasicTileVisual();
  @override
  void paint(Canvas canvas, Rect bounds, TileVisualFrame frame, GameSkin skin) {
    final rect = bounds.deflate(GameMetrics.cellInset), pitch = bounds.width;
    final shape = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(GameMetrics.cellRadius),
    );
    canvas.drawRRect(
      shape,
      Paint()..color = frame.blocked ? skin.blocked : skin.surface,
    );
    if (frame.blocked) {
      canvas.save();
      canvas.clipRRect(shape);
      for (double d = -pitch; d < pitch * 2; d += GameMetrics.gap) {
        canvas.drawLine(
          Offset(rect.left + d, rect.top),
          Offset(rect.left + d + pitch, rect.bottom),
          Paint()
            ..color = skin.surface.withValues(alpha: 0.18)
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
      return;
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = frame.legalDestination ? skin.selection : skin.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = frame.legalDestination ? 2 : 1,
    );
    if (frame.legalDestination)
      canvas.drawCircle(
        bounds.center,
        GameMetrics.coreRadius,
        Paint()..color = skin.selection.withValues(alpha: 0.55),
      );
    if (frame.goal) {
      final door = Rect.fromCenter(
        center: bounds.center,
        width: pitch * 0.48,
        height: pitch * 0.56,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          door,
          const Radius.circular(GameMetrics.cellRadius),
        ),
        Paint()
          ..color = skin.goal
          ..style = PaintingStyle.stroke
          ..strokeWidth = GameMetrics.routeWidth,
      );
      canvas.drawCircle(
        Offset(door.right - pitch * 0.1, bounds.center.dy),
        GameMetrics.coreRadius,
        Paint()..color = skin.goal,
      );
    }
  }
}

/// The app owns injected renderers and releases their eventual image caches on
/// replacement/disposal. Current defaults own no external resources.
final class BoardVisuals {
  final UnitVisual unit;
  final TileVisual tile;
  const BoardVisuals({
    this.unit = const BasicUnitVisual(),
    this.tile = const BasicTileVisual(),
  });
  void dispose() {
    unit.dispose();
    tile.dispose();
  }
}
