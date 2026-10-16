const supportedRuleSet = 'shared-goal-v1';
const maxRouteCommands = 16;
const constantSpeedRuleSet = 'constant-cell-speed-v2';
const supportedRuleSets = {supportedRuleSet, constantSpeedRuleSet};
const supportedMechanics = {
  'straight-motion',
  'absorbing-shared-goal',
  'timed-gates',
  'endpoint-portals',
};

final class Cell implements Comparable<Cell> {
  final int x;
  final int y;
  const Cell(this.x, this.y);
  @override
  int compareTo(Cell other) {
    final dx = x.compareTo(other.x);
    return dx == 0 ? y.compareTo(other.y) : dx;
  }

  @override
  bool operator ==(Object other) =>
      other is Cell && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
  List<int> toJson() => [x, y];
  @override
  String toString() => '($x,$y)';
}

final class GridMap {
  final int width;
  final int height;
  final List<String> rows;
  GridMap({
    required this.width,
    required this.height,
    required List<String> rows,
  }) : rows = List.unmodifiable(rows);
  bool contains(Cell cell) =>
      cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height;
  bool isWalkable(Cell cell) => contains(cell) && rows[cell.y][cell.x] == '.';
  Iterable<Cell> get walkable sync* {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final cell = Cell(x, y);
        if (isWalkable(cell)) yield cell;
      }
    }
  }
}

final class UnitSpec {
  final String id;
  final Cell start;
  const UnitSpec(this.id, this.start);
}

final class LevelIdentity {
  final String packId;
  final String levelId;
  final int revision;
  final String ruleSetId;
  const LevelIdentity(this.packId, this.levelId, this.revision, this.ruleSetId);
  @override
  bool operator ==(Object other) =>
      other is LevelIdentity &&
      packId == other.packId &&
      levelId == other.levelId &&
      revision == other.revision &&
      ruleSetId == other.ruleSetId;
  @override
  int get hashCode => Object.hash(packId, levelId, revision, ruleSetId);
  Map<String, Object> toJson() => {
    'packId': packId,
    'levelId': levelId,
    'revision': revision,
    'ruleSetId': ruleSetId,
  };
}

/// A center crossing opens the paired gate on [time, time + openFor).
final class TimedGate {
  final String id;
  final Cell trigger, door;
  final int openFor;
  const TimedGate(this.id, this.trigger, this.door, this.openFor);
}

/// Landing on entry as a command endpoint transfers instantly to exit.
/// Passing across entry without ending the command does not activate it.
final class PortalPair {
  final String id;
  final Cell entry, exit;
  const PortalPair(this.id, this.entry, this.exit);
}

final class LevelSpec {
  final List<PortalPair> portals;
  PortalPair? portalAt(Cell endpoint) {
    for (final p in portals) {
      if (p.entry == endpoint) return p;
    }
    return null;
  }

  Cell afterEndpoint(Cell endpoint) => portalAt(endpoint)?.exit ?? endpoint;
  final List<TimedGate> gates;
  final int schemaVersion;
  final LevelIdentity identity;
  final GridMap map;
  final Cell goal;
  final List<UnitSpec> units;
  final int maxCommands;
  final List<String> requiredMechanics;
  LevelSpec({
    this.schemaVersion = 1,
    List<TimedGate> gates = const [],
    List<PortalPair> portals = const [],
    required this.identity,
    required this.map,
    required this.goal,
    required List<UnitSpec> units,
    required this.maxCommands,
    List<String> requiredMechanics = const [
      'straight-motion',
      'absorbing-shared-goal',
    ],
  }) : portals = List.unmodifiable(portals),
       gates = List.unmodifiable(gates),
       units = List.unmodifiable(units),
       requiredMechanics = List.unmodifiable(requiredMechanics);
}

final class LevelPack {
  final String id;
  final int revision;
  final List<LevelSpec> levels;
  LevelPack(this.id, this.revision, List<LevelSpec> levels)
    : levels = List.unmodifiable(levels);
}

final class MoveCommand {
  final Cell destination;
  const MoveCommand(this.destination);
}

final class UnitRoute {
  final String unitId;
  final List<Cell> endpoints;
  UnitRoute(this.unitId, List<Cell> endpoints)
    : endpoints = List.unmodifiable(endpoints);
  bool completes(LevelSpec level) =>
      endpoints.isNotEmpty && endpoints.last == level.goal;
  Map<String, Object> toJson() => {
    'unitId': unitId,
    'endpoints': endpoints.map((e) => e.toJson()).toList(),
  };
}

/// Persist this binding with a draft. IDs alone are insufficient for replay.
final class RoutePlan {
  final LevelIdentity levelIdentity;
  final int revision;
  final List<UnitRoute> routes;
  RoutePlan(this.levelIdentity, List<UnitRoute> routes, {this.revision = 0})
    : routes = List.unmodifiable(routes);
}
