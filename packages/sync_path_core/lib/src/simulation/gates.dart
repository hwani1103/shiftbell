import '../model/models.dart';
import 'collision.dart';

final class GateActivation {
  final String gateId, unitId;
  final int time, until;
  const GateActivation(this.gateId, this.unitId, this.time, this.until);
  Map<String, Object> toJson() => {
    'gateId': gateId,
    'unitId': unitId,
    'time': time,
    'until': until,
  };
}

final class GateFailure {
  final String gateId, unitId;
  final Cell cell;
  final int time;
  const GateFailure(this.gateId, this.unitId, this.cell, this.time);
  Map<String, Object> toJson() => {
    'gateId': gateId,
    'unitId': unitId,
    'cell': cell.toJson(),
    'time': time,
  };
}

final class GateTimeline {
  final List<GateActivation> activations;
  final List<GateFailure> failures;
  const GateTimeline(this.activations, this.failures);
  Map<String, Object> toJson() => {
    'activations': activations.map((e) => e.toJson()).toList(),
    'failures': failures.map((e) => e.toJson()).toList(),
  };
  double remaining(String id, double time) {
    var end = time;
    for (final a in activations) {
      if (a.gateId == id && a.time <= time && a.until > end)
        end = a.until.toDouble();
    }
    return end - time;
  }
}

/// Exact integer cell-center events, independent of animation and command
/// splitting. Simultaneous triggers precede door checks; expiry is exclusive.
/// Evaluate planned visits, then the engine clamps to the earliest failure.
GateTimeline evaluateGates(LevelSpec level, List<LinearPiece> pieces) {
  if (level.gates.isEmpty) return const GateTimeline([], []);
  final visits = <int, Map<String, Cell>>{};
  for (final p in pieces) {
    final dx = (p.end.x - p.start.x).sign, dy = (p.end.y - p.start.y).sign;
    for (var t = 1; t <= p.durationUnits; t++) {
      visits.putIfAbsent(p.startTimeUnits + t, () => {})[p.unitId] = Cell(
        p.start.x + dx * t,
        p.start.y + dy * t,
      );
    }
  }
  final activations = <GateActivation>[], failures = <GateFailure>[];
  final until = <String, int>{};
  for (final time in visits.keys.toList()..sort()) {
    final entries = visits[time]!.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final g in level.gates) {
      for (final v in entries.where((e) => e.value == g.trigger)) {
        until[g.id] = time + g.openFor;
        activations.add(GateActivation(g.id, v.key, time, time + g.openFor));
      }
    }
    for (final g in level.gates) {
      for (final v in entries.where((e) => e.value == g.door)) {
        if ((until[g.id] ?? -1) <= time)
          failures.add(GateFailure(g.id, v.key, g.door, time));
      }
    }
    if (failures.isNotEmpty) break;
  }
  return GateTimeline(
    List.unmodifiable(activations),
    List.unmodifiable(failures),
  );
}
