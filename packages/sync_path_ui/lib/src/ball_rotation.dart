import 'dart:math' as math;
import 'package:sync_path_core/sync_path_core.dart';

/// Pure presentation orientation reconstructed from absolute replay time.
/// No integration from frame deltas: pause, seek and replay are deterministic.
final class BallRotation {
  final double w, x, y, z;
  const BallRotation(this.w, this.x, this.y, this.z);
  static const identity = BallRotation(1, 0, 0, 0);
  static const radiusCells = .255;

  factory BallRotation.at(
    Iterable<LinearPiece> motions,
    String id,
    double time,
  ) {
    var w = 1.0, x = 0.0, y = 0.0, z = 0.0;
    for (final piece in motions) {
      if (piece.unitId != id || piece.startTimeUnits.toDouble() > time)
        continue;
      final progress =
          ((time - piece.startTimeUnits.toDouble()) /
                  piece.durationUnits.toDouble())
              .clamp(0.0, 1.0);
      final dx = (piece.end.x - piece.start.x) * progress;
      final dy = (piece.end.y - piece.start.y) * progress;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance == 0) continue;
      final halfAngle = distance / radiusCells / 2;
      final a = math.cos(halfAngle), s = math.sin(halfAngle) / distance;
      final b = -dy * s, c = dx * s;
      // World rotation multiplied on the left retains orientation at turns.
      final nw = a * w - b * x - c * y;
      final nx = a * x + b * w + c * z;
      final ny = a * y - b * z + c * w;
      final nz = a * z + b * y - c * x;
      w = nw;
      x = nx;
      y = ny;
      z = nz;
    }
    return BallRotation(w, x, y, z);
  }

  (double, double, double) rotate(double vx, double vy, double vz) {
    final tx = 2 * (y * vz - z * vy);
    final ty = 2 * (z * vx - x * vz);
    final tz = 2 * (x * vy - y * vx);
    return (
      vx + w * tx + y * tz - z * ty,
      vy + w * ty + z * tx - x * tz,
      vz + w * tz + x * ty - y * tx,
    );
  }
}
