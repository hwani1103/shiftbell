import 'package:sync_path_core/sync_path_core.dart';

final class DisplayPoint {
  final double x, y;
  const DisplayPoint(this.x, this.y);
}

/// Render-only cursor. Contacts and arrivals come exclusively from the trace.
final class ReplayCursor {
  final SimulationTrace trace;
  double _position = 0;
  double _clockAnchor = 0;
  int _elapsedMicroseconds = 0;
  int _clockStepMilliseconds = 650;
  double _clockRate = 1;
  ReplayCursor(this.trace);
  double get position => _position;
  double get end => trace.durationInSteps.toDouble();
  bool get isAtEnd => _position >= end;
  void seek(double value) {
    if (!value.isFinite) throw ArgumentError('Finite replay cursor required');
    _position = value.clamp(0.0, end);
    _clockAnchor = _position;
    _elapsedMicroseconds = 0;
  }

  void advance(
    Duration elapsed, {
    int stepMilliseconds = 650,
    double playbackRate = 1,
  }) {
    if (elapsed.isNegative ||
        stepMilliseconds <= 0 ||
        !playbackRate.isFinite ||
        playbackRate <= 0)
      throw ArgumentError('Positive replay timing required');
    if (_clockStepMilliseconds != stepMilliseconds ||
        _clockRate != playbackRate) {
      _clockAnchor = _position;
      _elapsedMicroseconds = 0;
      _clockStepMilliseconds = stepMilliseconds;
      _clockRate = playbackRate;
    }
    // Accumulate integer wall time, not rounded floating point frame deltas.
    // Identical elapsed time must show the same arrivals and portal transfer.
    _elapsedMicroseconds += elapsed.inMicroseconds;
    _position =
        (_clockAnchor +
                _elapsedMicroseconds * playbackRate / (stepMilliseconds * 1000))
            .clamp(0.0, end);
  }

  Set<String> get completed => {
    for (final event in trace.arrivals)
      if (event.globalTime.toDouble() <= _position) event.unitId,
  };
  Map<String, DisplayPoint> get centers {
    final result = <String, DisplayPoint>{};
    final done = completed;
    for (final piece in trace.motions) {
      if (done.contains(piece.unitId) || piece.startTimeUnits > _position)
        continue;
      final t = ((_position - piece.startTimeUnits) / piece.durationUnits)
          .clamp(0.0, 1.0);
      result[piece.unitId] = DisplayPoint(
        piece.start.x + (piece.end.x - piece.start.x) * t,
        piece.start.y + (piece.end.y - piece.start.y) * t,
      );
    }
    // At a failed transfer the incoming endpoint is the visible contact.
    // Never leave a collided ball at OUT when its contact was at IN.
    if (isAtEnd) {
      final located = <String>{};
      for (final contact in trace.earliestCollisions) {
        for (final id in contact.unitIds) {
          final incomingContact = trace.motions.any(
            (p) =>
                p.unitId == id &&
                Rational(p.endTimeUnits) == contact.globalTime &&
                RationalPoint.cell(p.end) == contact.position,
          );
          if (located.add(id) || incomingContact) {
            result[id] = DisplayPoint(
              contact.position.x.toDouble(),
              contact.position.y.toDouble(),
            );
          }
        }
      }
    }
    return Map.unmodifiable(result);
  }

  List<CollisionEvent> get collisions =>
      isAtEnd ? trace.earliestCollisions : const [];
}
