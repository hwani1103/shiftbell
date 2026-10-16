import 'package:flutter/material.dart';
import 'presentation.dart';
import 'replay.dart';
import 'skin.dart';
import 'visuals.dart';

/// A still miniature of the board renderer, with no separate symbol vocabulary.
final class UnitThumbnail extends StatelessWidget {
  final UnitVisual visual;
  final String unitId;
  final int paletteIndex;
  final GameSkin skin;
  const UnitThumbnail({
    super.key,
    required this.visual,
    required this.unitId,
    required this.paletteIndex,
    required this.skin,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: GameMetrics.unitChipPreview,
    child: CustomPaint(painter: _UnitThumbnailPainter(this)),
  );
}

final class _UnitThumbnailPainter extends CustomPainter {
  final UnitThumbnail thumbnail;
  const _UnitThumbnailPainter(this.thumbnail);

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = GameMetrics.minCell;
    const center = Offset(pitch / 2, pitch / 2);
    canvas.save();
    canvas.scale(size.shortestSide / pitch);
    thumbnail.visual.paint(
      canvas,
      center,
      pitch,
      UnitVisualFrame(
        unitId: thumbnail.unitId,
        paletteIndex: thumbnail.paletteIndex,
        position: const DisplayPoint(0, 0),
        facing: UnitFacing.down,
        state: UnitVisualState.idle,
        moveProgress: 0,
        distanceCells: 0,
        visualTime: Duration.zero,
        playing: false,
        reducedMotion: true,
      ),
      thumbnail.skin,
    );
    canvas.drawCircle(
      center,
      GameMetrics.coreRadius,
      Paint()..color = thumbnail.skin.onPrimary,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnitThumbnailPainter oldDelegate) =>
      oldDelegate.thumbnail.visual != thumbnail.visual ||
      oldDelegate.thumbnail.unitId != thumbnail.unitId ||
      oldDelegate.thumbnail.paletteIndex != thumbnail.paletteIndex ||
      oldDelegate.thumbnail.skin != thumbnail.skin;
}
