import '../math/rational.dart';
import '../model/models.dart';
import '../validation/issues.dart';
import '../validation/validators.dart';
import 'collision.dart';
import 'gates.dart';

final class PortalEvent {
  final String portalId, unitId;
  final Cell entry, exit;
  final int timeUnits;
  const PortalEvent(
    this.portalId,
    this.unitId,
    this.entry,
    this.exit,
    this.timeUnits,
  );
  Map<String, Object> toJson() => {
    'portalId': portalId,
    'unitId': unitId,
    'entry': entry.toJson(),
    'exit': exit.toJson(),
    'timeUnits': timeUnits,
  };
}

final class CompiledMotion {
  final List<LinearPiece> pieces;
  final List<PortalEvent> portals;
  CompiledMotion(
    List<LinearPiece> pieces, [
    List<PortalEvent> portals = const [],
  ]) : pieces = List.unmodifiable(pieces),
       portals = List.unmodifiable(portals);
}

final class MotionCompiler {
  const MotionCompiler();

  /// Rejects drafts and stale identity before generating any motion.
  CompiledMotion compile(LevelSpec level, RoutePlan plan) {
    final result = const RouteValidator().validate(level, plan);
    if (!result.isValid) throw ArgumentError(result.issues.join(', '));
    final pieces = <LinearPiece>[];
    final portals = <PortalEvent>[];
    final starts = {for (final unit in level.units) unit.id: unit.start};
    for (final route in plan.routes) {
      var current = starts[route.unitId]!;
      var elapsed = 0;
      for (var i = 0; i < route.endpoints.length; i++) {
        final end = route.endpoints[i];
        if (level.identity.ruleSetId == constantSpeedRuleSet) {
          final duration =
              (end.x - current.x).abs() + (end.y - current.y).abs();
          pieces.add(
            LinearPiece(
              route.unitId,
              i + 1,
              current,
              end,
              startTimeUnits: elapsed,
              endTimeUnits: elapsed + duration,
            ),
          );
          elapsed += duration;
        } else {
          pieces.add(LinearPiece(route.unitId, i + 1, current, end));
        }
        final portal = level.portalAt(end);
        if (portal != null)
          portals.add(
            PortalEvent(
              portal.id,
              route.unitId,
              portal.entry,
              portal.exit,
              elapsed,
            ),
          );
        current = level.afterEndpoint(end);
      }
    }
    pieces.sort((a, b) {
      final order = a.startTimeUnits.compareTo(b.startTimeUnits);
      return order == 0 ? a.unitId.compareTo(b.unitId) : order;
    });
    portals.sort((a, b) {
      final order = a.timeUnits.compareTo(b.timeUnits);
      return order == 0 ? a.unitId.compareTo(b.unitId) : order;
    });
    return CompiledMotion(pieces, portals);
  }
}

enum SimulationOutcome { success, collision, closedGate }

sealed class SimulationResult {
  const SimulationResult();
}

final class InvalidPlan extends SimulationResult {
  final List<ValidationIssue> issues;
  InvalidPlan(Iterable<ValidationIssue> issues)
    : issues = List.unmodifiable(issues);
}

final class ArrivalEvent {
  final String unitId;
  final int step;
  final int? timeUnits;
  const ArrivalEvent(this.unitId, this.step, {this.timeUnits});
  Rational get globalTime => Rational(timeUnits ?? step);
  Map<String, Object> toJson() => {
    'unitId': unitId,
    'step': step,
    'globalTime': globalTime.toJson(),
  };
}

final class SimulationTrace extends SimulationResult {
  final SimulationOutcome outcome;
  final GateTimeline gateTimeline;
  final List<PortalEvent> portals;

  /// Planned pieces beginning at/before the stop cursor. Rendering MUST clamp to
  /// durationInSteps; endpoints after a collision are not applied motion results.
  final List<LinearPiece> motions;
  final List<ArrivalEvent> arrivals;
  final List<CollisionEvent> earliestCollisions;
  final Rational durationInSteps;
  Rational get durationInTimeUnits => durationInSteps;
  final LevelIdentity levelIdentity;
  final int routeRevision;
  String get ruleSetId => levelIdentity.ruleSetId;
  SimulationTrace({
    required this.outcome,
    List<PortalEvent> portals = const [],
    this.gateTimeline = const GateTimeline([], []),
    required List<LinearPiece> motions,
    required List<ArrivalEvent> arrivals,
    required List<CollisionEvent> earliestCollisions,
    required this.durationInSteps,
    required this.levelIdentity,
    required this.routeRevision,
  }) : portals = List.unmodifiable(portals),
       motions = List.unmodifiable(motions),
       arrivals = List.unmodifiable(arrivals),
       earliestCollisions = List.unmodifiable(earliestCollisions);
  Map<String, Object> toJson() => {
    'outcome': outcome.name,
    if (portals.isNotEmpty) 'portals': portals.map((e) => e.toJson()).toList(),
    if (gateTimeline.activations.isNotEmpty || gateTimeline.failures.isNotEmpty)
      'gates': gateTimeline.toJson(),
    'motions': motions.map((e) => e.toJson()).toList(),
    'arrivals': arrivals.map((e) => e.toJson()).toList(),
    'earliestCollisions': earliestCollisions.map((e) => e.toJson()).toList(),
    'durationInSteps': durationInSteps.toJson(),
    'levelIdentity': levelIdentity.toJson(),
    'routeRevision': routeRevision,
    'ruleSetId': ruleSetId,
  };
}

final class SimulationEngine {
  const SimulationEngine();
  SimulationResult simulate(LevelSpec level, RoutePlan plan) {
    final validation = const RouteValidator().validate(level, plan);
    if (!validation.isValid) return InvalidPlan(validation.issues);
    final compiled = const MotionCompiler().compile(level, plan);
    if (level.identity.ruleSetId == constantSpeedRuleSet) {
      final contacts = earliestTemporalCollisions(compiled.pieces, level.goal);
      final allArrivals =
          [
            for (final p in compiled.pieces)
              if (p.end == level.goal)
                ArrivalEvent(p.unitId, p.step, timeUnits: p.endTimeUnits),
          ]..sort((a, b) {
            final order = a.globalTime.compareTo(b.globalTime);
            return order == 0 ? a.unitId.compareTo(b.unitId) : order;
          });
      final gates = evaluateGates(level, compiled.pieces);
      final contactStop = contacts.isEmpty
          ? allArrivals.last.globalTime
          : contacts.first.globalTime;
      final gateStop = gates.failures.isEmpty
          ? null
          : Rational(gates.failures.first.time);
      final stop = gateStop != null && gateStop.compareTo(contactStop) <= 0
          ? gateStop
          : contactStop;
      final finalContacts = contacts
          .where((c) => c.globalTime == stop)
          .toList();
      final timeline = GateTimeline(
        gates.activations
            .where((a) => Rational(a.time).compareTo(stop) <= 0)
            .toList(),
        gates.failures.where((f) => Rational(f.time) == stop).toList(),
      );
      return SimulationTrace(
        gateTimeline: timeline,
        portals: compiled.portals
            .where(
              (p) =>
                  Rational(p.timeUnits).compareTo(stop) <= 0 &&
                  !finalContacts.any(
                    (c) =>
                        c.globalTime == Rational(p.timeUnits) &&
                        c.unitIds.contains(p.unitId) &&
                        c.position == RationalPoint.cell(p.entry),
                  ),
            )
            .toList(),
        outcome: timeline.failures.isNotEmpty
            ? SimulationOutcome.closedGate
            : finalContacts.isEmpty
            ? SimulationOutcome.success
            : SimulationOutcome.collision,
        motions: compiled.pieces
            .where((p) => Rational(p.startTimeUnits).compareTo(stop) <= 0)
            .toList(),
        arrivals: allArrivals
            .where((a) => a.globalTime.compareTo(stop) <= 0)
            .toList(),
        earliestCollisions: finalContacts,
        durationInSteps: stop,
        levelIdentity: level.identity,
        routeRevision: plan.revision,
      );
    }
    final motions = <LinearPiece>[];
    final arrivals = <ArrivalEvent>[];
    for (var step = 1; step <= level.maxCommands; step++) {
      final active = compiled.pieces
          .where((piece) => piece.step == step)
          .toList();
      if (active.isEmpty) break;
      motions.addAll(active);
      final collisions = earliestStepCollisions(active, level.goal);
      final stop = collisions.isEmpty
          ? Rational.one
          : collisions.first.localTime;
      if (stop == Rational.one) {
        for (final piece in active.where((piece) => piece.end == level.goal)) {
          arrivals.add(ArrivalEvent(piece.unitId, step));
        }
      }
      // A forbidden event wins even when another Unit arrives at the same time.
      if (collisions.isNotEmpty)
        return SimulationTrace(
          outcome: SimulationOutcome.collision,
          motions: motions,
          arrivals: arrivals,
          earliestCollisions: collisions,
          durationInSteps: collisions.first.globalTime,
          levelIdentity: level.identity,
          routeRevision: plan.revision,
        );
      if (arrivals.length == level.units.length)
        return SimulationTrace(
          outcome: SimulationOutcome.success,
          motions: motions,
          arrivals: arrivals,
          earliestCollisions: const [],
          durationInSteps: Rational(step),
          levelIdentity: level.identity,
          routeRevision: plan.revision,
        );
    }
    throw StateError('Validated complete routes must terminate');
  }
}
