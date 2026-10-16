import 'package:sync_path_core/sync_path_core.dart';
import 'session.dart';
import 'replay.dart';
import 'ball_rotation.dart';

enum UnitFacing { up, down, left, right }

enum UnitVisualState { idle, moving, collision }

enum VisualCueKind { goal, collision, success }

/// Immutable presentation data. Animation clocks/poses never feed back into
/// engine coordinates, command duration, routes or collision policy.
final class UnitVisualFrame {
  final String unitId;
  final int paletteIndex;
  final DisplayPoint position;
  final UnitFacing facing;
  final UnitVisualState state;
  final double moveProgress;
  final double distanceCells;
  final Duration visualTime;
  final bool playing;
  final bool reducedMotion;
  final bool selected;
  final double durationUnits;
  final Duration reactionTime;
  final double playbackRate;
  final BallRotation ballRotation;
  final bool planning;
  const UnitVisualFrame({
    required this.unitId,
    required this.paletteIndex,
    required this.position,
    required this.facing,
    required this.state,
    required this.moveProgress,
    required this.distanceCells,
    required this.visualTime,
    required this.playing,
    required this.reducedMotion,
    this.selected = false,
    this.durationUnits = 1,
    this.reactionTime = Duration.zero,
    this.playbackRate = 1,
    this.ballRotation = BallRotation.identity,
    this.planning = false,
  });
}

final class VisualCue {
  final VisualCueKind kind;
  final Rational timeInSteps;
  final RationalPoint position;
  final List<String> unitIds;
  final Duration age;
  final BallRotation ballRotation;
  VisualCue(
    this.kind,
    this.timeInSteps,
    this.position,
    Iterable<String> ids, {
    this.age = Duration.zero,
    this.ballRotation = BallRotation.identity,
  }) : unitIds = List.unmodifiable(ids);
}

final class PresentationFrame {
  final List<UnitVisualFrame> units;

  /// Completed Units appear only as visual cues, never active logical bodies.
  final List<VisualCue> cues;
  PresentationFrame(List<UnitVisualFrame> units, List<VisualCue> cues)
    : units = List.unmodifiable(units),
      cues = List.unmodifiable(cues);
}

/// Renderer-independent bridge: any painter/widget/sprite implementation can
/// consume this frame. Poses and gait never modify logical motion timing.
final class MovementPresentation {
  const MovementPresentation();
  UnitFacing _facing(Cell start, Cell end) => end.x > start.x
      ? UnitFacing.right
      : end.x < start.x
      ? UnitFacing.left
      : end.y < start.y
      ? UnitFacing.up
      : UnitFacing.down;
  PresentationFrame frame(
    GameSessionController session, {
    Duration visualTime = Duration.zero,
    bool reducedMotion = false,
    Duration reactionTime = Duration.zero,
  }) {
    final level = session.level, replay = session.replay;
    final units = <UnitVisualFrame>[], cues = <VisualCue>[];
    final positions = replay?.centers;
    final colliding = replay != null && replay.isAtEnd
        ? {
            for (final c in session.trace!.earliestCollisions) ...c.unitIds,
            for (final f in session.trace!.gateTimeline.failures) f.unitId,
          }
        : <String>{};
    for (var i = 0; i < level.units.length; i++) {
      final unit = level.units[i];
      if (replay != null && !positions!.containsKey(unit.id)) continue;
      var facing = UnitFacing.down;
      var progress = 0.0, distance = 0.0, duration = 1.0;
      var state = UnitVisualState.idle;
      if (replay != null) {
        LinearPiece? current;
        for (final piece in session.trace!.motions) {
          if (piece.unitId == unit.id &&
              piece.startTimeUnits <= replay.position)
            current = piece;
        }
        if (current != null) {
          duration = current.durationUnits.toDouble();
          facing = _facing(current.start, current.end);
          progress =
              ((replay.position - current.startTimeUnits) /
                      current.durationUnits)
                  .clamp(0.0, 1.0);
          distance =
              ((current.end.x - current.start.x).abs() +
                      (current.end.y - current.start.y).abs())
                  .toDouble();
          state = colliding.contains(unit.id)
              ? UnitVisualState.collision
              : replay.isAtEnd
              ? UnitVisualState.idle
              : UnitVisualState.moving;
        }
      } else {
        final route = session.routes[i];
        if (route.endpoints.isNotEmpty)
          facing = _facing(
            route.endpoints.length == 1
                ? unit.start
                : level.afterEndpoint(
                    route.endpoints[route.endpoints.length - 2],
                  ),
            route.endpoints.last,
          );
      }
      // Planning endpoints are draft markers, not physical Unit positions.
      // Keep Units at their starts so Execute never teleports them backwards
      // from a shared Goal before the first synchronized Step.
      final current = unit.start;
      units.add(
        UnitVisualFrame(
          unitId: unit.id,
          paletteIndex: i,
          position:
              positions?[unit.id] ??
              DisplayPoint(current.x.toDouble(), current.y.toDouble()),
          facing: facing,
          state: state,
          moveProgress: progress,
          distanceCells: distance,
          visualTime: visualTime,
          playing: session.mode == SessionMode.replaying,
          reducedMotion: reducedMotion,
          selected: session.editable && unit.id == session.selectedUnitId,
          planning: session.editable,
          durationUnits: duration,
          reactionTime: reactionTime,
          playbackRate: session.playbackRate,
          ballRotation: replay == null || reducedMotion
              ? BallRotation.identity
              : BallRotation.at(
                  session.trace!.motions,
                  unit.id,
                  replay.position,
                ),
        ),
      );
    }
    if (replay != null) {
      for (final arrival in session.trace!.arrivals) {
        if (arrival.globalTime.toDouble() <= replay.position)
          cues.add(
            VisualCue(
              VisualCueKind.goal,
              arrival.globalTime,
              RationalPoint.cell(level.goal),
              [arrival.unitId],
              ballRotation: reducedMotion
                  ? BallRotation.identity
                  : BallRotation.at(
                      session.trace!.motions,
                      arrival.unitId,
                      arrival.globalTime.toDouble(),
                    ),
              age:
                  Duration(
                    microseconds:
                        ((replay.position - arrival.globalTime.toDouble()) *
                                650000 /
                                session.playbackRate)
                            .round(),
                  ) +
                  reactionTime,
            ),
          );
      }
      if (replay.isAtEnd) {
        for (final collision in session.trace!.earliestCollisions) {
          cues.add(
            VisualCue(
              VisualCueKind.collision,
              collision.globalTime,
              collision.position,
              collision.unitIds,
              age: reactionTime,
            ),
          );
        }
        if (session.trace!.outcome == SimulationOutcome.success)
          cues.add(
            VisualCue(
              VisualCueKind.success,
              session.trace!.durationInSteps,
              RationalPoint.cell(level.goal),
              level.units.map((u) => u.id),
              age: reactionTime,
            ),
          );
      }
    }
    return PresentationFrame(units, cues);
  }
}
