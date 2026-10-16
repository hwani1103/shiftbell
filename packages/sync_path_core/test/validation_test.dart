import 'dart:convert';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:test/test.dart';
import 'support/fixtures.dart';

void main() {
  const parser = LevelParser();
  test('W01 all pilot levels and witnesses load and validate', () {
    final pack = pilotPack();
    final certificates = fixture('09_pilot_certificates.json')['levels'];
    expect(pack.levels.length, 12);
    for (var i = 0; i < pack.levels.length; i++) {
      expect(
        const RouteValidator()
            .validate(
              pack.levels[i],
              RoutePlan(
                pack.levels[i].identity,
                routes(certificates[i]['witness']),
              ),
            )
            .issues,
        isEmpty,
      );
    }
  });
  final mutations = <String, (IssueCode, void Function(Map<String, dynamic>))>{
    'float width': (IssueCode.invalidInteger, (j) => j['width'] = 5.0),
    'string width': (IssueCode.invalidInteger, (j) => j['width'] = '5'),
    'rows length': (IssueCode.invalidFormat, (j) => j['rows'] = ['.....']),
    'row character': (IssueCode.invalidMap, (j) => j['rows'][0] = '....G'),
    'row width': (IssueCode.invalidMap, (j) => j['rows'][0] = '......'),
    'small board': (IssueCode.outOfBounds, (j) => j['width'] = 4),
    'schema': (IssueCode.unsupportedSchema, (j) => j['schemaVersion'] = 2),
    'rule': (IssueCode.unsupportedRuleSet, (j) => j['ruleSetId'] = 'portal-v1'),
    'mechanic': (
      IssueCode.unsupportedMechanic,
      (j) => j['requiredMechanics'] = ['portal'],
    ),
    'duplicate id': (
      IssueCode.duplicateUnitId,
      (j) => j['units'][1]['id'] = 'A',
    ),
    'empty id': (IssueCode.invalidId, (j) => j['units'][0]['id'] = ''),
    'invalid id charset': (
      IssueCode.invalidId,
      (j) => j['units'][0]['id'] = 'A/B',
    ),
    'duplicate start': (
      IssueCode.duplicateStart,
      (j) => j['units'][1]['start'] = [0, 0],
    ),
    'start goal': (
      IssueCode.startOnGoal,
      (j) => j['units'][0]['start'] = [4, 4],
    ),
    'blocked placement': (
      IssueCode.blockedPlacement,
      (j) => j['rows'][0] = '#....',
    ),
    'coordinate range': (IssueCode.outOfBounds, (j) => j['goal'] = [5, 4]),
    'negative coordinate': (IssueCode.outOfBounds, (j) => j['goal'] = [-1, 4]),
    'fraction coordinate': (
      IssueCode.invalidInteger,
      (j) => j['goal'] = [4, 3.5],
    ),
    'disconnected': (
      IssueCode.disconnectedWalkable,
      (j) => j['rows'][2] = '#####',
    ),
    'unreachable within N': (
      IssueCode.individuallyUnreachable,
      (j) => j['maxCommands'] = 1,
    ),
    'oversize units': (
      IssueCode.inputTooLarge,
      (j) => j['units'] = List.filled(6, {
        'id': 'A',
        'start': [0, 0],
      }),
    ),
    'oversize ID': (IssueCode.invalidId, (j) => j['id'] = 'A' * 65),
  };
  for (final entry in mutations.entries) {
    test('V01..V04 ${entry.key}', () {
      final j = levelJson();
      entry.value.$2(j);
      final result = parser.parseLevel(jsonEncode(j), packId: 'test-pack');
      expect(result.value, isNull);
      expect(result.issues.map((i) => i.code), contains(entry.value.$1));
    });
  }
  test(
    'V10 hostile JSON is bounded before decode, malformed/huge numeric tokens rejected',
    () {
      expect(
        parser
            .parsePack(' ' * (LevelParser.maxJsonBytes + 1))
            .issues
            .single
            .code,
        IssueCode.inputTooLarge,
      );
      expect(
        parser.parsePack('{"width":12345678901234567890}').issues.single.code,
        IssueCode.invalidInteger,
      );
      expect(parser.parsePack('{').issues.single.code, IssueCode.invalidFormat);
      expect(
        parser.parsePack('{"schemaVersion":1e0}').issues.single.code,
        IssueCode.invalidInteger,
      );
    },
  );
  test('Goal participates in connectivity but stops rays and allows entry', () {
    final level = openLevel(goal: const Cell(2, 0));
    expect(const LevelValidator().validate(level).isValid, isTrue);
    expect(
      legalDestinations(level, const Cell(0, 0)),
      contains(const Cell(2, 0)),
    );
    expect(
      legalDestinations(level, const Cell(0, 0)),
      isNot(contains(const Cell(3, 0))),
    );
    expect(legalDestinations(level, level.goal), isEmpty);
    expect(minimumCommandsToGoal(level)[const Cell(0, 0)], 1);
  });
  final badRoutes = <String, (IssueCode, List<Cell>)>{
    'diagonal': (IssueCode.diagonalMove, [const Cell(1, 1)]),
    'zero': (IssueCode.zeroLengthMove, [const Cell(0, 0)]),
    'outside': (IssueCode.outOfBounds, [const Cell(5, 0)]),
    'goal pass': (IssueCode.goalPassThrough, [const Cell(4, 0)]),
    'after goal': (
      IssueCode.commandAfterGoal,
      [const Cell(2, 0), const Cell(1, 0)],
    ),
    'too many': (
      IssueCode.tooManyCommands,
      [const Cell(1, 0), const Cell(0, 0), const Cell(1, 0), const Cell(2, 0)],
    ),
    'empty': (IssueCode.emptyRoute, []),
    'incomplete': (IssueCode.incompleteRoute, [const Cell(1, 0)]),
  };
  for (final entry in badRoutes.entries) {
    test('V05..V08 ${entry.key}', () {
      final level = openLevel(goal: const Cell(2, 0));
      final issue = const RouteValidator().validateRoute(
        level,
        level.units.first,
        UnitRoute('A', entry.value.$2),
      );
      expect(issue.issues.map((i) => i.code), contains(entry.value.$1));
    });
  }
  test('Mid-ray wall is rejected even with walkable endpoint', () {
    final level = openLevel(
      rows: ['.#...', '.....', '.....', '.....', '.....'],
    );
    expect(
      const RouteValidator()
          .validateRoute(
            level,
            level.units.first,
            UnitRoute('A', [const Cell(2, 0)]),
          )
          .issues
          .map((i) => i.code),
      contains(IssueCode.blockedMove),
    );
  });
  test(
    'Exact Unit set: missing, extra, duplicate and drafts cannot execute',
    () {
      final level = openLevel();
      final validator = const RouteValidator();
      expect(
        validator
            .validate(level, RoutePlan(level.identity, []))
            .issues
            .map((e) => e.code),
        contains(IssueCode.missingRoute),
      );
      final invalid = RoutePlan(level.identity, [
        UnitRoute('X', []),
        UnitRoute('A', []),
        UnitRoute('A', []),
      ]);
      expect(
        validator.validate(level, invalid).issues.map((e) => e.code),
        containsAll([
          IssueCode.extraRoute,
          IssueCode.duplicateRoute,
          IssueCode.emptyRoute,
        ]),
      );
      final draft = RoutePlan(level.identity, [
        for (final unit in level.units) UnitRoute(unit.id, []),
      ]);
      expect(
        validator
            .validate(level, draft, mode: RouteValidationMode.draft)
            .isValid,
        isTrue,
      );
      expect(
        const SimulationEngine().simulate(level, draft),
        isA<InvalidPlan>(),
      );
    },
  );
  test(
    'V09 stale identity/revision rejected and plan JSON round trip preserves binding',
    () {
      final level = openLevel();
      final json = {
        'levelIdentity': level.identity.toJson(),
        'routeRevision': 7,
        'routes': [
          {'unitId': 'A', 'endpoints': []},
          {'unitId': 'B', 'endpoints': []},
        ],
      };
      final plan = parser.parsePlan(jsonEncode(json)).value!;
      expect(plan.revision, 7);
      final stale = RoutePlan(
        LevelIdentity('test-pack', 'test-level', 2, supportedRuleSet),
        plan.routes,
      );
      expect(
        const RouteValidator().validate(level, stale).issues.map((e) => e.code),
        contains(IssueCode.staleLevelIdentity),
      );
      expect(
        const RouteValidator()
            .validate(
              level,
              RoutePlan(level.identity, plan.routes, revision: -1),
            )
            .issues
            .map((e) => e.code),
        contains(IssueCode.invalidRevision),
      );
    },
  );
  test('R10 split, reverse and revisiting commands are preserved', () {
    final level = openLevel(goal: const Cell(2, 0));
    final split = UnitRoute('A', [const Cell(1, 0), const Cell(2, 0)]);
    final reverse = UnitRoute('A', [
      const Cell(0, 1),
      const Cell(0, 0),
      const Cell(2, 0),
    ]);
    expect(
      const RouteValidator()
          .validateRoute(level, level.units.first, split)
          .isValid,
      isTrue,
    );
    expect(
      const RouteValidator()
          .validateRoute(level, level.units.first, reverse)
          .isValid,
      isTrue,
    );
  });
}
