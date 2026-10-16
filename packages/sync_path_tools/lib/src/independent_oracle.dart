import 'package:sync_path_core/sync_path_core.dart';

/// Verification only. No ray graph, BFS pruning, CollisionResolver or engine is
/// used here. The finite v1 denominator bound makes this exhaustive, not FPS sampling.
List<UnitRoute> directRoutes(LevelSpec level, UnitSpec unit) {
  final result = <UnitRoute>[];
  bool walkable(int x, int y) =>
      x >= 0 &&
      y >= 0 &&
      x < level.map.width &&
      y < level.map.height &&
      level.map.rows[y][x] == '.';
  void dfs(Cell current, List<Cell> prefix) {
    if (current == level.goal) {
      result.add(UnitRoute(unit.id, prefix));
      return;
    }
    if (prefix.length == level.maxCommands) return;
    for (final (dx, dy) in const [(1, 0), (0, 1), (-1, 0), (0, -1)]) {
      var x = current.x + dx, y = current.y + dy;
      while (walkable(x, y)) {
        final end = Cell(x, y);
        var landing = end;
        for (final p in level.portals) {
          if (end == p.entry) landing = p.exit;
        }
        dfs(landing, [...prefix, end]);
        if (end == level.goal) break;
        x += dx;
        y += dy;
      }
    }
  }

  dfs(unit.start, []);
  return result;
}

List<CollisionEvent> oracleCollisions(LevelSpec level, List<UnitRoute> routes) {
  if (level.identity.ruleSetId == constantSpeedRuleSet)
    return _cellTimeOracle(level, routes);
  final starts = {for (final u in level.units) u.id: u.start};
  final bound =
      2 *
      ((level.map.width > level.map.height
              ? level.map.width
              : level.map.height) -
          1);
  final events = <CollisionEvent>[];
  for (var step = 1; step <= level.maxCommands; step++) {
    final active = routes.where((r) => r.endpoints.length >= step).toList();
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final a = active[i], b = active[j];
        final sa = step == 1 ? starts[a.unitId]! : a.endpoints[step - 2];
        final sb = step == 1 ? starts[b.unitId]! : b.endpoints[step - 2];
        final ea = a.endpoints[step - 1], eb = b.endpoints[step - 1];
        Rational? time;
        for (var q = 1; q <= bound; q++) {
          for (var p = 0; p <= q; p++) {
            final ax = q * sa.x + p * (ea.x - sa.x),
                ay = q * sa.y + p * (ea.y - sa.y);
            final bx = q * sb.x + p * (eb.x - sb.x),
                by = q * sb.y + p * (eb.y - sb.y);
            if (ax != bx || ay != by) continue;
            if (p == q && ax == q * level.goal.x && ay == q * level.goal.y)
              continue;
            final candidate = Rational(p, q);
            if (time == null || candidate.compareTo(time) < 0) time = candidate;
          }
        }
        if (time != null) {
          final p = time.numerator, q = time.denominator;
          events.add(
            CollisionEvent(
              step,
              time,
              RationalPoint(
                Rational(q * sa.x + p * (ea.x - sa.x), q),
                Rational(q * sa.y + p * (ea.y - sa.y), q),
              ),
              a.unitId,
              b.unitId,
            ),
          );
        }
      }
    }
    if (events.isNotEmpty) {
      events.sort((a, b) {
        var c = a.globalTime.compareTo(b.globalTime);
        if (c == 0) c = a.position.compareTo(b.position);
        if (c == 0) c = a.unitIds[0].compareTo(b.unitIds[0]);
        if (c == 0) c = a.unitIds[1].compareTo(b.unitIds[1]);
        return c;
      });
      final earliest = events.first.globalTime;
      return events.where((e) => e.globalTime == earliest).toList();
    }
  }
  return [];
}

/// Independent v2 oracle: expand commands to unit-cell edges, then exhaust
/// t=0,1/2,1 in each interval. Relative velocity components are integers in
/// [-2,2], so these include every possible first center contact exactly.
/// Twice-time / twice-position lattice. Each cell edge contributes its start,
/// midpoint and end. A transfer contributes BOTH endpoints at the same instant;
/// it contributes no edge between them. This is independent of MotionCompiler.
Map<int, Set<Cell>> oracleSamples(LevelSpec level, UnitRoute route) {
  final samples = <int, Set<Cell>>{};
  void add(int tick, Cell c) {
    if (c != Cell(level.goal.x * 2, level.goal.y * 2))
      samples.putIfAbsent(tick, () => <Cell>{}).add(c);
  }

  var c = level.units.singleWhere((u) => u.id == route.unitId).start;
  var tick = 0;
  add(tick, Cell(c.x * 2, c.y * 2));
  for (final end in route.endpoints) {
    final dx = (end.x - c.x).sign, dy = (end.y - c.y).sign;
    while (c != end) {
      add(tick + 1, Cell(c.x * 2 + dx, c.y * 2 + dy));
      c = Cell(c.x + dx, c.y + dy);
      tick += 2;
      add(tick, Cell(c.x * 2, c.y * 2));
    }
    for (final p in level.portals) {
      if (end == p.entry) {
        c = p.exit;
        add(tick, Cell(c.x * 2, c.y * 2));
        break;
      }
    }
  }
  return samples;
}

List<CollisionEvent> _cellTimeOracle(LevelSpec level, List<UnitRoute> routes) {
  final paths = {for (final r in routes) r.unitId: oracleSamples(level, r)};
  final ids = paths.keys.toList()..sort();
  final ticks = paths.values.expand((p) => p.keys).toSet().toList()..sort();
  for (final tick in ticks) {
    final events = <CollisionEvent>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = paths[ids[i]]![tick] ?? <Cell>{};
        final b = paths[ids[j]]![tick] ?? <Cell>{};
        for (final c in a.intersection(b)) {
          final step = tick == 0 ? 1 : (tick + 1) ~/ 2;
          events.add(
            CollisionEvent(
              step,
              Rational(tick, 2) - Rational(step - 1),
              RationalPoint(Rational(c.x, 2), Rational(c.y, 2)),
              ids[i],
              ids[j],
            ),
          );
        }
      }
    }
    if (events.isNotEmpty) {
      events.sort((a, b) {
        var c = a.position.compareTo(b.position);
        if (c == 0) c = a.unitIds[0].compareTo(b.unitIds[0]);
        if (c == 0) c = a.unitIds[1].compareTo(b.unitIds[1]);
        return c;
      });
      return events;
    }
  }
  return [];
}
