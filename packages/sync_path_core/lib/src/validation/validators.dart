import '../model/models.dart';
import 'issues.dart';

bool validId(String value) =>
    value.length <= 64 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(value);
bool validRevision(int value) => value >= 0 && value <= 2147483647;

/// Cardinal rays stop at walls, the edge, or the absorbing Goal.
/// Use with a validated LevelSpec; no Unit start is treated as an obstacle.
List<Cell> legalDestinations(LevelSpec level, Cell current) {
  if (!level.map.isWalkable(current) || current == level.goal) return const [];
  final result = <Cell>[];
  for (final direction in const [
    Cell(1, 0),
    Cell(0, 1),
    Cell(-1, 0),
    Cell(0, -1),
  ]) {
    var next = Cell(current.x + direction.x, current.y + direction.y);
    while (level.map.isWalkable(next)) {
      result.add(next);
      if (next == level.goal) break;
      next = Cell(next.x + direction.x, next.y + direction.y);
    }
  }
  result.sort();
  return List.unmodifiable(result);
}

final class LevelValidator {
  const LevelValidator();
  ValidationResult validate(LevelSpec level) {
    final issues = <ValidationIssue>[];
    void issue(IssueCode code, String path, [String? unit]) =>
        issues.add(ValidationIssue(code, path, unitId: unit));
    final map = level.map;
    if (map.width < 5 ||
        map.width > 8 ||
        map.height < 5 ||
        map.height > 8 ||
        map.rows.length != map.height ||
        map.rows.any(
          (row) => row.length != map.width || !RegExp(r'^[.#]+$').hasMatch(row),
        )) {
      issue(IssueCode.invalidMap, 'map');
    }
    if (level.units.length < 2 ||
        level.units.length > 5 ||
        level.maxCommands < 1 ||
        level.maxCommands > maxRouteCommands) {
      issue(IssueCode.invalidFormat, 'units/maxCommands');
    }
    if (!validId(level.identity.packId) || !validId(level.identity.levelId))
      issue(IssueCode.invalidId, 'identity');
    if (!validRevision(level.identity.revision) || level.identity.revision == 0)
      issue(IssueCode.invalidRevision, 'identity.revision');
    if (issues.isNotEmpty) return ValidationResult(issues);
    final ids = <String>{};
    final starts = <Cell>{};
    void placement(Cell cell, String path, [String? unit]) {
      if (!map.contains(cell)) {
        issue(IssueCode.outOfBounds, path, unit);
      } else if (!map.isWalkable(cell)) {
        issue(IssueCode.blockedPlacement, path, unit);
      }
    }

    placement(level.goal, 'goal');
    for (final unit in level.units) {
      if (!validId(unit.id)) issue(IssueCode.invalidId, 'units.id', unit.id);
      if (!ids.add(unit.id))
        issue(IssueCode.duplicateUnitId, 'units.id', unit.id);
      if (!starts.add(unit.start))
        issue(IssueCode.duplicateStart, 'units.start', unit.id);
      if (unit.start == level.goal)
        issue(IssueCode.startOnGoal, 'units.start', unit.id);
      placement(unit.start, 'units.start', unit.id);
    }
    final gateIds = <String>{};
    final devices = <Cell>{};
    if (level.gates.length > 2 ||
        (level.gates.isNotEmpty &&
            (level.identity.ruleSetId != constantSpeedRuleSet ||
                !level.requiredMechanics.contains('timed-gates')))) {
      issue(IssueCode.unsupportedMechanic, 'gates');
    }
    for (final g in level.gates) {
      if (!validId(g.id) ||
          !gateIds.add(g.id) ||
          g.openFor < 1 ||
          g.openFor > 12)
        issue(IssueCode.invalidFormat, 'gates');
      for (final cell in [g.trigger, g.door]) {
        placement(cell, 'gates');
        if (!devices.add(cell) || cell == level.goal || starts.contains(cell))
          issue(IssueCode.invalidFormat, 'gates.placement');
      }
    }
    if (issues.isNotEmpty) return ValidationResult(issues);
    final portalIds = <String>{};
    if (level.portals.length > 2 ||
        (level.portals.isNotEmpty &&
            (level.identity.ruleSetId != constantSpeedRuleSet ||
                !level.requiredMechanics.contains('endpoint-portals')))) {
      issue(IssueCode.unsupportedMechanic, 'portals');
    }
    for (final p in level.portals) {
      if (!validId(p.id) || !portalIds.add(p.id))
        issue(IssueCode.invalidFormat, 'portals.id');
      for (final c in [p.entry, p.exit]) {
        placement(c, 'portals');
        if (!devices.add(c) || c == level.goal || starts.contains(c))
          issue(IssueCode.invalidFormat, 'portals.placement');
      }
    }
    if (issues.isNotEmpty) return ValidationResult(issues);
    final cells = map.walkable.toSet();
    final reached = <Cell>{cells.first};
    final queue = <Cell>[cells.first];
    for (var i = 0; i < queue.length; i++) {
      final cell = queue[i];
      for (final next in [
        Cell(cell.x + 1, cell.y),
        Cell(cell.x - 1, cell.y),
        Cell(cell.x, cell.y + 1),
        Cell(cell.x, cell.y - 1),
      ]) {
        if (cells.contains(next) && reached.add(next)) queue.add(next);
      }
    }
    if (reached.length != cells.length)
      issue(IssueCode.disconnectedWalkable, 'map');
    if (level.schemaVersion != 1)
      issue(IssueCode.unsupportedSchema, 'schemaVersion');
    if (!supportedRuleSets.contains(level.identity.ruleSetId))
      issue(IssueCode.unsupportedRuleSet, 'ruleSetId');
    if (level.requiredMechanics.length > supportedMechanics.length ||
        level.requiredMechanics.any((m) => !supportedMechanics.contains(m)) ||
        level.requiredMechanics.toSet().length !=
            level.requiredMechanics.length) {
      issue(IssueCode.unsupportedMechanic, 'requiredMechanics');
    }
    if (issues.isNotEmpty) return ValidationResult(issues);
    final distances = minimumCommandsToGoal(level);
    for (final unit in level.units) {
      if ((distances[unit.start] ?? 999) > level.maxCommands)
        issue(IssueCode.individuallyUnreachable, 'units.start', unit.id);
    }
    return ValidationResult(issues);
  }
}

/// Reverse BFS is essential: Goal has no outgoing ray but many incoming edges.
Map<Cell, int> minimumCommandsToGoal(LevelSpec level) {
  final reverse = <Cell, List<Cell>>{
    for (final cell in level.map.walkable) cell: [],
  };
  for (final cell in reverse.keys) {
    for (final target in legalDestinations(level, cell)) {
      reverse[level.afterEndpoint(target)]!.add(cell);
    }
  }
  final distances = <Cell, int>{level.goal: 0};
  final queue = <Cell>[level.goal];
  for (var i = 0; i < queue.length; i++) {
    final cell = queue[i];
    for (final previous in reverse[cell] ?? <Cell>[]) {
      if (!distances.containsKey(previous)) {
        distances[previous] = distances[cell]! + 1;
        queue.add(previous);
      }
    }
  }
  return Map.unmodifiable(distances);
}

enum RouteValidationMode { draft, complete }

final class RouteValidator {
  const RouteValidator();
  ValidationResult validate(
    LevelSpec level,
    RoutePlan plan, {
    RouteValidationMode mode = RouteValidationMode.complete,
  }) {
    final levelIssues = const LevelValidator().validate(level).issues;
    if (levelIssues.isNotEmpty) return ValidationResult(levelIssues);
    final issues = <ValidationIssue>[];
    if (plan.levelIdentity != level.identity)
      issues.add(
        const ValidationIssue(IssueCode.staleLevelIdentity, 'levelIdentity'),
      );
    if (!validRevision(plan.revision))
      issues.add(
        const ValidationIssue(IssueCode.invalidRevision, 'routeRevision'),
      );
    if (plan.routes.length > 5)
      return ValidationResult([
        ...issues,
        const ValidationIssue(IssueCode.inputTooLarge, 'routes'),
      ]);
    final units = {for (final unit in level.units) unit.id: unit};
    final seen = <String>{};
    for (final route in plan.routes) {
      if (!seen.add(route.unitId))
        issues.add(
          ValidationIssue(
            IssueCode.duplicateRoute,
            'routes',
            unitId: route.unitId,
          ),
        );
      final unit = units[route.unitId];
      if (unit == null) {
        issues.add(
          ValidationIssue(IssueCode.extraRoute, 'routes', unitId: route.unitId),
        );
        continue;
      }
      issues.addAll(validateRoute(level, unit, route, mode: mode).issues);
    }
    for (final id in units.keys.where((id) => !seen.contains(id))) {
      issues.add(ValidationIssue(IssueCode.missingRoute, 'routes', unitId: id));
    }
    return ValidationResult(issues);
  }

  /// For editors/tools with an already validated level and its corresponding Unit.
  ValidationResult validateRoute(
    LevelSpec level,
    UnitSpec unit,
    UnitRoute route, {
    RouteValidationMode mode = RouteValidationMode.complete,
  }) {
    final issues = <ValidationIssue>[];
    void issue(IssueCode code, [int? index]) => issues.add(
      ValidationIssue(
        code,
        'routes.endpoints',
        unitId: route.unitId,
        commandIndex: index,
      ),
    );
    if (route.unitId != unit.id) issue(IssueCode.extraRoute);
    if (route.endpoints.length > level.maxCommands) {
      issue(IssueCode.tooManyCommands);
      return ValidationResult(issues);
    }
    if (route.endpoints.isEmpty && mode == RouteValidationMode.complete)
      issue(IssueCode.emptyRoute);
    var current = unit.start;
    for (var i = 0; i < route.endpoints.length; i++) {
      final end = route.endpoints[i];
      if (current == level.goal) {
        issue(IssueCode.commandAfterGoal, i);
        break;
      }
      if (!level.map.contains(end)) {
        issue(IssueCode.outOfBounds, i);
        break;
      }
      if (current == end) {
        issue(IssueCode.zeroLengthMove, i);
        break;
      }
      if (current.x != end.x && current.y != end.y) {
        issue(IssueCode.diagonalMove, i);
        break;
      }
      final dx = (end.x - current.x).sign;
      final dy = (end.y - current.y).sign;
      var cursor = Cell(current.x + dx, current.y + dy);
      var rejected = false;
      while (true) {
        if (!level.map.isWalkable(cursor)) {
          issue(IssueCode.blockedMove, i);
          rejected = true;
          break;
        }
        if (cursor == level.goal && cursor != end) {
          issue(IssueCode.goalPassThrough, i);
          rejected = true;
          break;
        }
        if (cursor == end) break;
        cursor = Cell(cursor.x + dx, cursor.y + dy);
      }
      if (rejected) break;
      current = level.afterEndpoint(end);
    }
    if (mode == RouteValidationMode.complete && !route.completes(level))
      issue(IssueCode.incompleteRoute);
    return ValidationResult(issues);
  }
}
