import 'shift_schedule.dart';

enum TeamRuleKind { cycle, weekly }

/// Calendar-date arithmetic: DST and the time of day never move a cycle slot.
class TeamRule {
  TeamRule.cycle(List<String> shifts, DateTime anchor, this.anchorIndex)
      : kind = TeamRuleKind.cycle,
        shifts = List.unmodifiable(shifts),
        anchor = DateTime(anchor.year, anchor.month, anchor.day) {
    _validate();
  }

  TeamRule.weekly(List<String> weekdays)
      : kind = TeamRuleKind.weekly,
        shifts = List.unmodifiable(weekdays),
        anchor = DateTime(
            2024, 1, 1), // Monday; compiled for existing alarm engines.
        anchorIndex = 0 {
    _validate();
  }

  final TeamRuleKind kind;
  final List<String> shifts;
  final DateTime anchor;
  final int anchorIndex;

  void _validate() {
    if (shifts.isEmpty ||
        shifts.length > 40 ||
        shifts.any((s) =>
            s.trim().isEmpty || s.contains(',') || s == kUnsetShiftSentinel) ||
        anchorIndex < 0 ||
        anchorIndex >= shifts.length ||
        (kind == TeamRuleKind.weekly && shifts.length != 7)) {
      throw const FormatException('Invalid team rule');
    }
  }

  int indexOn(DateTime date) => kind == TeamRuleKind.weekly
      ? date.weekday - 1
      : (anchorIndex +
              julianDayNumber(date.year, date.month, date.day) -
              julianDayNumber(anchor.year, anchor.month, anchor.day)) %
          shifts.length;

  String shiftOn(DateTime date) => shifts[indexOn(date)];

  TeamRule rename(Map<String, String> names) => kind == TeamRuleKind.weekly
      ? TeamRule.weekly(shifts.map((s) => names[s] ?? s).toList())
      : TeamRule.cycle(
          shifts.map((s) => names[s] ?? s).toList(), anchor, anchorIndex);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'shifts': shifts,
        'anchor': anchor.toIso8601String().split('T').first,
        'index': anchorIndex,
      };

  factory TeamRule.fromJson(Map<String, dynamic> json) {
    final shifts = List<String>.from(json['shifts'] as List);
    if (json['kind'] == 'weekly') return TeamRule.weekly(shifts);
    if (json['kind'] != 'cycle')
      throw const FormatException('Unknown team rule');
    final raw = json['anchor'] as String;
    final date = DateTime.parse(raw);
    if (date.toIso8601String().split('T').first != raw) {
      throw const FormatException('Invalid anchor date');
    }
    return TeamRule.cycle(shifts, date, json['index'] as int);
  }
}
