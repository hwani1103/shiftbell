import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_tools/src/solver.dart';
import 'package:sync_path_tools/src/generator.dart';

String normalized(Cell start, UnitRoute r) {
  final ends = <Cell>[];
  var current = start;
  Cell? direction;
  for (final end in r.endpoints) {
    final d = Cell((end.x - current.x).sign, (end.y - current.y).sign);
    if (d == direction) {
      ends[ends.length - 1] = end;
    } else {
      ends.add(end);
    }
    current = end;
    direction = d;
  }
  return ends.map((c) => '${c.x},${c.y}').join(';');
}

int distance(Cell start, UnitRoute r) {
  var d = 0, c = start;
  for (final e in r.endpoints) {
    d += (e.x - c.x).abs() + (e.y - c.y).abs();
    c = e;
  }
  return d;
}

Map<String, Object> metrics(LevelSpec l, SolverResult s) {
  final minimum = <String, int>{}, choices = <String, int>{};
  for (final u in l.units) {
    minimum[u.id] = s.domains[u.id]!
        .map((r) => distance(u.start, r))
        .reduce(min);
    choices[u.id] = s.domains[u.id]!
        .map((r) => normalized(u.start, r))
        .toSet()
        .length;
  }
  var extra = 999, detours = 999, reverses = 999, moves = 999;
  final plans = <String>{};
  List<UnitRoute>? best;
  var bestDistance = 999;
  for (final a in s.assignments) {
    var e = 0, d = 0, r = 0, m = 0;
    plans.add(
      a
          .map(
            (route) => normalized(
              l.units.singleWhere((u) => u.id == route.unitId).start,
              route,
            ),
          )
          .join('|'),
    );
    for (final route in a) {
      final start = l.units.singleWhere((u) => u.id == route.unitId).start;
      final delta = distance(start, route) - minimum[route.unitId]!;
      e += delta;
      if (delta > 0) d++;
      if (hasReverse(start, route)) r++;
      m += route.endpoints.length;
    }
    extra = min(extra, e);
    detours = min(detours, d);
    reverses = min(reverses, r);
    moves = min(moves, m);
    if (e < bestDistance) {
      bestDistance = e;
      best = a;
    }
  }
  final space = choices.values.fold<int>(1, (a, b) => a * b);
  final information = log(space / plans.length) / ln2;
  final score =
      l.units.length * 1.3 +
      information * .45 +
      extra * .45 +
      detours * .7 +
      moves * .12;
  return {
    'units': l.units.length,
    'temporalChoices': choices,
    'temporalCombinations': space,
    'distinctSolutions': plans.length,
    'minimumExtraDistance': extra,
    'minimumDetouringUnits': detours,
    'minimumReversingUnits': reverses,
    'minimumTotalCommands': moves,
    'constraintBits': information,
    'score': score,
    'witness': best!.map((r) => r.toJson()).toList(),
  };
}

void main(List<String> args) {
  final seed = int.parse(args[0]), attempts = int.parse(args[1]);
  final out = File(args[2]);
  final rng = Random(seed);
  var kept = 0;
  final sink = out.openWrite();
  for (var attempt = 0; attempt < attempts; attempt++) {
    final tier = attempt % 5;
    final size = tier < 2 ? 5 + rng.nextInt(2) : 6 + rng.nextInt(3);
    final n = tier < 1
        ? 2
        : tier < 3
        ? 3
        : tier < 4
        ? 4
        : 5;
    final commands = tier < 2 ? 3 + rng.nextInt(2) : 4 + rng.nextInt(2);
    final open = <Cell>{};
    final density = .48 + rng.nextDouble() * .2;
    for (var y = 0; y < size; y++)
      for (var x = 0; x < size; x++)
        if (rng.nextDouble() < density) open.add(Cell(x, y));
    // Retain the largest connected room/corridor component only.
    var largest = <Cell>{};
    final todo = Set<Cell>.from(open);
    while (todo.isNotEmpty) {
      final component = <Cell>{}, queue = [todo.first];
      todo.remove(queue.first);
      while (queue.isNotEmpty) {
        final c = queue.removeLast();
        component.add(c);
        for (final d in const [
          Cell(1, 0),
          Cell(-1, 0),
          Cell(0, 1),
          Cell(0, -1),
        ]) {
          final next = Cell(c.x + d.x, c.y + d.y);
          if (todo.remove(next)) queue.add(next);
        }
      }
      if (component.length > largest.length) largest = component;
    }
    if (largest.length < 10 + n * 2 || largest.length > 42) continue;
    final cells = largest.toList()..shuffle(rng);
    final goal = cells.first;
    final level = LevelSpec(
      identity: LevelIdentity(
        'campaign-search',
        'S$seed-$attempt',
        1,
        constantSpeedRuleSet,
      ),
      map: GridMap(
        width: size,
        height: size,
        rows: [
          for (var y = 0; y < size; y++)
            [
              for (var x = 0; x < size; x++)
                largest.contains(Cell(x, y)) ? '.' : '#',
            ].join(),
        ],
      ),
      goal: goal,
      units: [
        for (var i = 0; i < n; i++)
          UnitSpec(String.fromCharCode(65 + i), cells[i + 1]),
      ],
      maxCommands: commands,
    );
    if (!const LevelValidator().validate(level).isValid) continue;
    final result = const PuzzleSolver().solve(
      level,
      budget: const SolverBudget(
        maxNodes: 35000,
        maxDomainRoutes: 180,
        solutionCap: 250,
        maxCacheEntries: 15000,
      ),
    );
    if (result.status != SolverStatus.sat || !result.exhaustive) continue;
    final m = metrics(level, result);
    if ((m['distinctSolutions'] as int) > 50 ||
        (m['constraintBits'] as double) < 1.5)
      continue;
    final entry = {
      'seed': seed,
      'attempt': attempt,
      'level': levelJson(level),
      'metrics': m,
      'exactCommandSolutions': result.exactCount.toString(),
    };
    sink.writeln(jsonEncode(entry));
    kept++;
    if (kept % 10 == 0)
      stdout.writeln(
        'seed=$seed attempts=$attempt kept=$kept score=${m['score']}',
      );
  }
  sink.close();
  stdout.writeln('DONE seed=$seed attempts=$attempts kept=$kept');
}
