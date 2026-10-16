import 'dart:math' as math;
import 'presentation.dart';

enum UnitAnimationState { idle, start, walk, run, stop, collision }

final class UnitPose {
  final UnitAnimationState state;
  final double stride, bob, lean, scale, opacity;
  const UnitPose(
    this.state,
    this.stride,
    this.bob,
    this.lean,
    this.scale,
    this.opacity,
  );
}

/// Presentation only: gait follows distance already traveled, never moves the
/// simulation cursor. All four facings can use another atlas or sprite player.
final class UnitAnimationController {
  const UnitAnimationController();
  UnitPose pose(UnitVisualFrame f) {
    final seconds = f.visualTime.inMicroseconds / 1000000;
    final selection = f.selected ? 1.13 : 1.0;
    if (f.reducedMotion)
      return UnitPose(UnitAnimationState.idle, 0, 0, 0, selection, 1);
    if (f.state == UnitVisualState.collision) {
      final t = (f.reactionTime.inMicroseconds / 850000).clamp(0.0, 1.0);
      return UnitPose(
        UnitAnimationState.collision,
        0,
        t * 3,
        t * 0.7,
        selection * (1 - t * .16),
        1 - t * .45,
      );
    }
    if (f.state == UnitVisualState.moving && f.playing) {
      final traveled = f.distanceCells * f.moveProgress;
      final remaining = f.distanceCells - traveled;
      final start = (1 - traveled / .22).clamp(0.0, 1.0);
      final stop = (1 - remaining / .22).clamp(0.0, 1.0);
      final speed = f.distanceCells / f.durationUnits * f.playbackRate;
      final running = speed >= 1.5;
      final stride = math.sin(traveled * math.pi * 2);
      return UnitPose(
        start > 0
            ? UnitAnimationState.start
            : stop > 0
            ? UnitAnimationState.stop
            : running
            ? UnitAnimationState.run
            : UnitAnimationState.walk,
        stride,
        math.sin(traveled * math.pi * 4).abs() * (running ? 2.0 : 1.1),
        (start - stop) * .08,
        selection,
        1,
      );
    }
    return UnitPose(
      UnitAnimationState.idle,
      math.sin(seconds * 1.8) * .08,
      math.sin(seconds * 2) * .65,
      0,
      selection * (1 + math.sin(seconds * 2) * .014),
      1,
    );
  }
}
