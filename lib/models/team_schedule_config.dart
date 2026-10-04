import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'shift_schedule.dart';
import 'team_rule.dart';

class TeamScheduleConfig {
  const TeamScheduleConfig(
      {required this.names,
      required this.offsets,
      required this.myTeam,
      this.individual = false,
      this.rules = const {},
      this.ids = const {}});
  final List<String> names;
  final Map<String, int> offsets;
  final String myTeam;
  final bool individual;
  final Map<String, TeamRule> rules;
  final Map<String, String> ids;

  TeamRule ruleFor(String team, List<String> legacyPattern) =>
      rules[team] ??
      TeamRule.cycle(
          legacyPattern, baseDate, offsets[team]! % legacyPattern.length);

  TeamScheduleConfig materialize(List<String> pattern) => TeamScheduleConfig(
        names: names,
        offsets: offsets,
        myTeam: myTeam,
        // Older rosters could contain duplicate positions. Preserve every team
        // by migrating those as independent rules instead of crashing on read.
        individual: individual ||
            (rules.isEmpty &&
                names.map((name) => offsets[name]! % pattern.length).toSet().length != names.length),
        ids: {
          for (var i = 0; i < names.length; i++)
            names[i]: ids[names[i]] ?? 'team-$i'
        },
        rules: {for (final name in names) name: ruleFor(name, pattern)},
      );

  TeamScheduleConfig withMyTeam(String name) {
    if (!names.contains(name)) throw ArgumentError('Unknown team');
    return TeamScheduleConfig(
        names: names,
        offsets: offsets,
        myTeam: name,
        individual: individual,
        rules: rules,
        ids: ids);
  }

  TeamScheduleConfig renameShifts(Map<String, String> changes) =>
      TeamScheduleConfig(
          names: names,
          offsets: offsets,
          myTeam: myTeam,
          individual: individual,
          ids: ids,
          rules:
              rules.map((name, rule) => MapEntry(name, rule.rename(changes))));

  Set<String> get referencedShifts =>
      rules.values.expand((r) => r.shifts).toSet();

  Map<String, dynamic> toJson() => {
        'version': 2,
        'individual': individual,
        'myTeamId': ids[myTeam] ?? 'team-${names.indexOf(myTeam)}',
        'teams': [
          for (var i = 0; i < names.length; i++)
            {
              'id': ids[names[i]] ?? 'team-$i',
              'name': names[i],
              'rule': rules[names[i]]!.toJson(),
            }
        ],
      };

  factory TeamScheduleConfig.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2 || json['individual'] is! bool) {
      throw const FormatException('Unsupported roster');
    }
    final names = <String>[];
    final ids = <String, String>{};
    final rules = <String, TeamRule>{};
    for (final item in json['teams'] as List) {
      final name = item['name'] as String;
      final id = item['id'] as String;
      if (name.trim().isEmpty ||
          id.isEmpty ||
          names.contains(name) ||
          ids.containsValue(id)) {
        throw const FormatException('Invalid team identity');
      }
      names.add(name);
      ids[name] = id;
      rules[name] =
          TeamRule.fromJson(Map<String, dynamic>.from(item['rule'] as Map));
    }
    if (names.length < 2 || !ids.containsValue(json['myTeamId'])) {
      throw const FormatException('Missing teams');
    }
    final individual = json['individual'] as bool;
    if (!individual) {
      final first = rules.values.first;
      if (rules.values.any((r) =>
              r.kind != TeamRuleKind.cycle ||
              jsonEncode(r.shifts) != jsonEncode(first.shifts)) ||
          rules.values.map((r) => r.indexOn(baseDate)).toSet().length !=
              names.length) {
        throw const FormatException('Invalid shared cycle');
      }
    }
    return TeamScheduleConfig(
        names: List.unmodifiable(names),
        offsets: {
          for (final name in names) name: rules[name]!.indexOn(baseDate)
        },
        myTeam: ids.entries.singleWhere((e) => e.value == json['myTeamId']).key,
        individual: individual,
        rules: Map.unmodifiable(rules),
        ids: Map.unmodifiable(ids));
  }
  static final baseDate = DateTime(2024, 1, 1);

  static TeamScheduleConfig? read(SharedPreferences prefs) {
    final names = prefs.getStringList('all_teams_names');
    final mine = prefs.getString('all_teams_my_team');
    if (names == null ||
        names.length < 2 ||
        !names.contains(mine) ||
        names.any((n) => n.trim().isEmpty) ||
        names.toSet().length != names.length) {
      return null;
    }
    try {
      final raw = jsonDecode(prefs.getString('all_teams_offsets') ?? '{}')
          as Map<String, dynamic>;
      final offsets = raw.map((k, v) => MapEntry(k, int.parse('$v')));
      if (names.any((n) => !offsets.containsKey(n))) return null;
      return TeamScheduleConfig(names: names, offsets: offsets, myTeam: mine!);
    } catch (_) {
      return null;
    }
  }

  int indexOn(String team, DateTime date, int length) {
    if (rules.containsKey(team)) return rules[team]!.indexOn(date);
    final days = julianDayNumber(date.year, date.month, date.day) -
        julianDayNumber(baseDate.year, baseDate.month, baseDate.day);
    return (offsets[team]! + days) % length;
  }

  List<String> teamsAt(int index, DateTime date, int length) =>
      names.where((team) => indexOn(team, date, length) == index).toList();

  /// Roster positions never move when the user joins another existing team.
  static Future<void> applySelection(
      SharedPreferences prefs, String? team) async {
    if (team != null) {
      if (!await prefs.setString('all_teams_my_team', team))
        throw StateError('Team save failed');
    } else {
      for (final key in [
        'all_teams_names',
        'all_teams_offsets',
        'all_teams_my_team'
      ]) {
        if (!await prefs.remove(key)) throw StateError('Team reset failed');
      }
    }
  }
}
