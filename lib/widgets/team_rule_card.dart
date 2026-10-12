import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../models/team_rule.dart';
import '../theme/app_colors.dart';
import 'team_label.dart';

/// Team identity remains the selection target even when today's shifts match.
class TeamRuleCard extends StatelessWidget {
  const TeamRuleCard(
      {super.key,
      required this.team,
      required this.rule,
      required this.date,
      this.isMine = false,
      this.selected = false,
      this.onTap,
      this.locked = false});
  final String team;
  final TeamRule? rule;
  final DateTime date;
  final bool isMine;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final r = rule;
    return Semantics(
        selected: selected,
        button: onTap != null,
        child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
                color: isMine
                    ? colors.surfaceContainerHighest
                    : selected
                        ? kAppSurface
                        : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color:
                            selected ? kAppMainAccent : colors.outlineVariant,
                        width: selected ? 2 : 1)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    onTap: onTap,
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                TeamLabel(name: team, isMine: isMine),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(
                                        isMine
                                            ? (locked
                                                ? l.teamRuleLocked.replaceFirst(' · ', '\n')
                                                : l.teamRuleCurrentTeam)
                                            : r == null
                                                ? l.teamRuleMissing
                                                : r.kind == TeamRuleKind.weekly
                                                    ? l.teamRuleWeekly
                                                    : l.statusPatternDayCycle(
                                                        r.shifts.length),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            height: 1.4))),
                                if (locked)
                                  const Icon(Icons.lock_outline, size: 18)
                                else if (onTap != null)
                                  Icon(
                                      selected
                                          ? Icons.check_circle
                                          : Icons.chevron_right,
                                      color: kAppMainAccent),
                              ]),
                              if (r != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                    '${date.month}/${date.day} · ${r.shiftOn(date)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                if (r.kind == TeamRuleKind.weekly)
                                  Text(l.teamRuleWeeklyLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                Text(r.shifts.join(' · '),
                                    maxLines: selected ? null : 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        height: 1.5)),
                              ],
                            ]))))));
  }
}
