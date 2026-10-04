import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../models/team_rule.dart';
import '../theme/app_colors.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_second_button.dart';
import '../widgets/app_shift_chip.dart';
import '../widgets/team_assignment_grid.dart';

/// Draft-only editor. No main schedule, alarm, or roster writes happen here.
class TeamRuleEditorScreen extends StatefulWidget {
  const TeamRuleEditorScreen(
      {super.key,
      required this.team,
      required this.basePattern,
      required this.shiftTypes,
      required this.date,
      this.initial});
  final String team;
  final List<String> basePattern;
  final List<String> shiftTypes;
  final DateTime date;
  final TeamRule? initial;
  @override
  State<TeamRuleEditorScreen> createState() => _TeamRuleEditorScreenState();
}

class _TeamRuleEditorScreenState extends State<TeamRuleEditorScreen> {
  int _mode = 0;
  List<String> _cycle = [];
  late List<String?> _week;
  int? _baseIndex;
  int? _cycleIndex;
  String? _picked;
  @override
  void initState() {
    super.initState();
    _week = List.filled(7, null);
    final rule = widget.initial;
    if (rule != null) {
      if (rule.kind == TeamRuleKind.weekly) {
        _mode = 2;
        _week = List.of(rule.shifts);
      } else if (rule.shifts.join(',') == widget.basePattern.join(',')) {
        _baseIndex = rule.indexOn(widget.date);
      } else {
        _mode = 1;
        _cycle = List.of(rule.shifts);
        _cycleIndex = rule.indexOn(widget.date);
      }
    }
  }

  bool get _complete => _mode == 2
      ? _week.every((s) => s != null)
      : _mode == 0
          ? _baseIndex != null
          : _cycle.isNotEmpty && _cycleIndex != null;

  void _save() {
    if (!_complete) return;
    final rule = _mode == 2
        ? TeamRule.weekly(_week.cast<String>())
        : TeamRule.cycle(_mode == 0 ? widget.basePattern : _cycle, widget.date,
            (_mode == 0 ? _baseIndex : _cycleIndex)!);
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final weekdays = [
      l.teamRuleMonday,
      l.teamRuleTuesday,
      l.teamRuleWednesday,
      l.teamRuleThursday,
      l.teamRuleFriday,
      l.teamRuleSaturday,
      l.teamRuleSunday
    ];
    final pattern = _mode == 0 ? widget.basePattern : _cycle;
    final selected = _mode == 0 ? _baseIndex : _cycleIndex;
    return Scaffold(
      backgroundColor: kAppBackgroundPastel,
      appBar: AppBar(title: Text('${widget.team} · ${l.teamRuleTitle}')),
      body: AdaptiveFormBody(
          child: SafeArea(
              child: Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < 3; i++)
              AppShiftChip(
                  key: ValueKey('rule-mode-$i'),
                  label: [l.teamRuleBase, l.teamRuleCycle, l.teamRuleWeekly][i],
                  selected: _mode == i,
                  onTap: () => setState(() => _mode = i)),
          ]),
          const SizedBox(height: 24),
          if (_mode != 0) ...[
            Text(_mode == 1 ? l.teamRulePatternHint : l.teamRuleWeeklyHint,
                style: const TextStyle(height: 1.5)),
            const SizedBox(height: 8),
            Text(l.teamRuleAllShiftsHint,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final shift in widget.shiftTypes)
                AppShiftChip(
                    key: ValueKey('rule-shift-$shift'),
                    label: shift,
                    selected: _mode == 2 && _picked == shift,
                    onTap: _mode == 1 && _cycle.length >= 40
                        ? null
                        : () => setState(() {
                              if (_mode == 1) {
                                _cycle.add(shift);
                                _cycleIndex = null;
                              } else {
                                _picked = shift;
                              }
                            })),
            ]),
            const SizedBox(height: 20),
          ],
          if (_mode == 1) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < _cycle.length; i++)
                AppShiftChip(
                    key: ValueKey('rule-cycle-remove-$i'),
                    label: '${i + 1} ${_cycle[i]}',
                    dense: true,
                    onTap: () => setState(() {
                          _cycle.removeAt(i);
                          _cycleIndex = null;
                        })),
            ]),
            if (_cycle.isNotEmpty)
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => setState(() {
                            _cycle.clear();
                            _cycleIndex = null;
                          }),
                      child: Text(l.teamRuleResetCycle))),
          ],
          if (_mode == 2)
            LayoutBuilder(builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final cols =
                  (constraints.maxWidth / (100 * scale)).floor().clamp(1, 7);
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < 7; i++)
                  SizedBox(
                      width: (constraints.maxWidth - (cols - 1) * 8) / cols,
                      child: Semantics(
                          button: true,
                          label:
                              '${weekdays[i]} ${_week[i] ?? l.teamRuleUnset}',
                          child: InkWell(
                              key: ValueKey('rule-weekday-$i'),
                              onTap: _picked == null
                                  ? null
                                  : () => setState(() => _week[i] = _picked),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 14),
                                  decoration: BoxDecoration(
                                      color: _week[i] == null
                                          ? Colors.white
                                          : kAppSurface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: _week[i] == null
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant
                                              : kAppMainAccent)),
                                  child: Column(children: [
                                    Text(weekdays[i],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(_week[i] ?? l.teamRuleUnset,
                                        textAlign: TextAlign.center)
                                  ]))))),
              ]);
            })
          else if (pattern.isNotEmpty) ...[
            Text(
                '${widget.date.month}/${widget.date.day} · ${l.teamRulePositionHint}',
                style:
                    const TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TeamAssignmentGrid(
                pattern: pattern,
                teamAtSlot: (i) => i == selected ? widget.team : null,
                isMine: (_) => false,
                selectedIndex: selected,
                keyPrefix: 'rule-position',
                onTapSlot: (i) => setState(() {
                      if (_mode == 0)
                        _baseIndex = i;
                      else
                        _cycleIndex = i;
                    })),
          ],
        ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              Expanded(
                  child: AppSecondButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.commonCancel))),
              const SizedBox(width: 12),
              Expanded(
                  child: AppSecondButton(
                      key: const ValueKey('rule-save'),
                      variant: AppSecondButtonVariant.success,
                      onPressed: _complete ? _save : null,
                      child: Text(l.teamRuleComplete))),
            ])),
      ]))),
    );
  }
}
