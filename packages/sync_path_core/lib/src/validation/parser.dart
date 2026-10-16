import 'dart:convert';
import '../model/models.dart';
import 'issues.dart';
import 'validators.dart';

/// Bounded untrusted JSON boundary. Certificates are deliberately not runtime data.
final class LevelParser {
  static const maxJsonBytes = 262144;
  static const maxLevels = 128;
  const LevelParser();

  ParseResult<LevelPack> parsePack(String source) => _parse(() {
    final root = _object(_decode(source), r'$');
    final rule = _rules(root);
    final id = _id(root['packId'], 'packId');
    final revision = _integer(root['revision'], 'revision', 1, 2147483647);
    final entries = _list(root['levels'], 'levels', 1, maxLevels);
    final levels = <LevelSpec>[];
    final ids = <String>{};
    for (var i = 0; i < entries.length; i++) {
      final level = _level(_object(entries[i], 'levels[$i]'), id, rule);
      if (!ids.add(level.identity.levelId))
        _fail(IssueCode.duplicateLevelId, 'levels[$i].id');
      levels.add(level);
    }
    return LevelPack(id, revision, levels);
  });

  ParseResult<LevelSpec> parseLevel(String source, {required String packId}) =>
      _parse(() {
        _id(packId, 'packId');
        final root = _object(_decode(source), r'$');
        final rule = _rules(root);
        return _level(root, packId, rule);
      });

  ParseResult<RoutePlan> parsePlan(String source) => _parse(() {
    final root = _object(_decode(source), r'$');
    final binding = _object(root['levelIdentity'], 'levelIdentity');
    final identity = LevelIdentity(
      _id(binding['packId'], 'packId'),
      _id(binding['levelId'], 'levelId'),
      _integer(binding['revision'], 'revision', 1, 2147483647),
      _rule(binding['ruleSetId']),
    );
    final revision = _integer(
      root['routeRevision'],
      'routeRevision',
      0,
      2147483647,
    );
    final routes = _list(root['routes'], 'routes', 0, 5);
    return RoutePlan(identity, [
      for (var i = 0; i < routes.length; i++)
        _route(_object(routes[i], 'routes[$i]')),
    ], revision: revision);
  });

  LevelSpec _level(Map<String, dynamic> root, String packId, String rule) {
    final width = _integer(root['width'], 'width', 5, 8);
    final height = _integer(root['height'], 'height', 5, 8);
    final rawRows = _list(root['rows'], 'rows', height, height);
    final rows = <String>[];
    for (final row in rawRows) {
      if (row is! String ||
          row.length != width ||
          !RegExp(r'^[.#]+$').hasMatch(row))
        _fail(IssueCode.invalidMap, 'rows');
      rows.add(row);
    }
    final rawUnits = _list(root['units'], 'units', 2, 5);
    final units = <UnitSpec>[];
    for (final entry in rawUnits) {
      final unit = _object(entry, 'units');
      units.add(
        UnitSpec(
          _id(unit['id'], 'units.id'),
          _cell(unit['start'], 'units.start'),
        ),
      );
    }
    final mechanics = _list(
      root['requiredMechanics'],
      'requiredMechanics',
      0,
      4,
    );
    for (final mechanic in mechanics) {
      if (mechanic is! String || !supportedMechanics.contains(mechanic))
        _fail(IssueCode.unsupportedMechanic, 'requiredMechanics');
    }
    final gates = <TimedGate>[];
    for (final value in _list(root['gates'] ?? [], 'gates', 0, 2)) {
      final g = _object(value, 'gates');
      gates.add(
        TimedGate(
          _id(g['id'], 'gates.id'),
          _cell(g['trigger'], 'gates.trigger'),
          _cell(g['door'], 'gates.door'),
          _integer(g['openFor'], 'gates.openFor', 1, 12),
        ),
      );
    }
    final portals = <PortalPair>[];
    for (final value in _list(root['portals'] ?? [], 'portals', 0, 2)) {
      final p = _object(value, 'portals');
      portals.add(
        PortalPair(
          _id(p['id'], 'portals.id'),
          _cell(p['entry'], 'portals.entry'),
          _cell(p['exit'], 'portals.exit'),
        ),
      );
    }
    final level = LevelSpec(
      portals: portals,
      gates: gates,
      identity: LevelIdentity(
        packId,
        _id(root['id'], 'id'),
        _integer(root['revision'], 'revision', 1, 2147483647),
        rule,
      ),
      map: GridMap(width: width, height: height, rows: rows),
      goal: _cell(root['goal'], 'goal'),
      units: units,
      maxCommands: _integer(
        root['maxCommands'],
        'maxCommands',
        1,
        maxRouteCommands,
      ),
      requiredMechanics: mechanics.cast<String>(),
    );
    final issues = const LevelValidator().validate(level).issues;
    if (issues.isNotEmpty) throw _ParseFailure(issues);
    return level;
  }

  UnitRoute _route(Map<String, dynamic> root) {
    final endpoints = _list(
      root['endpoints'],
      'endpoints',
      0,
      maxRouteCommands,
    );
    return UnitRoute(_id(root['unitId'], 'unitId'), [
      for (final endpoint in endpoints) _cell(endpoint, 'endpoints'),
    ]);
  }

  Object? _decode(String source) {
    // Check code units first, before allocating UTF-8 or decoding collections.
    if (source.length > maxJsonBytes ||
        utf8.encode(source).length > maxJsonBytes)
      _fail(IssueCode.inputTooLarge, r'$');
    // Native/JS JSON decoders differ for 1.0. Require integer lexical tokens too.
    var quoted = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == '-' || RegExp(r'[0-9]').hasMatch(char)) {
        final start = i;
        while (i + 1 < source.length &&
            RegExp(r'[0-9.eE+\-]').hasMatch(source[i + 1])) {
          i++;
        }
        final token = source.substring(start, i + 1);
        if (token.length > 11 ||
            !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(token))
          _fail(IssueCode.invalidInteger, r'$');
      }
    }
    try {
      return jsonDecode(source);
    } on FormatException {
      _fail(IssueCode.invalidFormat, r'$');
    }
  }

  String _rules(Map<String, dynamic> root) {
    if (root['schemaVersion'] is! int || root['schemaVersion'] != 1)
      _fail(IssueCode.unsupportedSchema, 'schemaVersion');
    return _rule(root['ruleSetId']);
  }

  String _rule(Object? value) {
    if (!supportedRuleSets.contains(value))
      _fail(IssueCode.unsupportedRuleSet, 'ruleSetId');
    return value as String;
  }

  Map<String, dynamic> _object(Object? value, String path) {
    if (value is! Map<String, dynamic>) _fail(IssueCode.invalidFormat, path);
    return value;
  }

  List<dynamic> _list(Object? value, String path, int min, int max) {
    if (value is! List) _fail(IssueCode.invalidFormat, path);
    final list = value;
    if (list.length > max) _fail(IssueCode.inputTooLarge, path);
    if (list.length < min) _fail(IssueCode.invalidFormat, path);
    return list;
  }

  String _id(Object? value, String path) {
    if (value is! String || !validId(value)) _fail(IssueCode.invalidId, path);
    return value;
  }

  int _integer(Object? value, String path, int min, int max) {
    if (value is! int) _fail(IssueCode.invalidInteger, path);
    final number = value;
    if (number < min || number > max) _fail(IssueCode.outOfBounds, path);
    return number;
  }

  Cell _cell(Object? value, String path) {
    final list = _list(value, path, 2, 2);
    return Cell(
      _integer(list[0], '$path.x', 0, 7),
      _integer(list[1], '$path.y', 0, 7),
    );
  }

  Never _fail(IssueCode code, String path) =>
      throw _ParseFailure([ValidationIssue(code, path)]);
  ParseResult<T> _parse<T>(T Function() work) {
    try {
      return ParseResult.success(work());
    } on _ParseFailure catch (error) {
      return ParseResult.failure(error.issues);
    }
  }
}

final class _ParseFailure implements Exception {
  final List<ValidationIssue> issues;
  _ParseFailure(this.issues);
}
