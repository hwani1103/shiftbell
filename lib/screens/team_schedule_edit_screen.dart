import '../widgets/settings_appearance.dart';
import '../widgets/app_button.dart';
import '../widgets/team_assignment_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../widgets/team_rule_card.dart';
import '../l10n/l10n_extensions.dart';
import '../models/team_schedule_config.dart';
import '../utils/apply_schedule_change.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_second_button.dart';
import '../widgets/schedule_change_dialog.dart';
import '../widgets/shift_editor_dialog.dart';

enum TeamScheduleEditResult { changed, recreate }

/// Editing a configured roster never moves a team's cycle position.
class TeamScheduleEditScreen extends ConsumerStatefulWidget {
  const TeamScheduleEditScreen(
      {super.key,
      required this.teams,
      required this.pattern,
      required this.date});
  final TeamScheduleConfig teams;
  final List<String> pattern;
  final DateTime date;

  @override
  ConsumerState<TeamScheduleEditScreen> createState() =>
      _TeamScheduleEditScreenState();
}

class _TeamScheduleEditScreenState
    extends ConsumerState<TeamScheduleEditScreen> {
  bool _showTeams = false;
  bool _busy = false;
  String? _selected;
  bool get _ko => Localizations.localeOf(context).languageCode == 'ko';

  Future<bool> _confirm(String message, {bool destructive = false}) async {
    return await showDialog<bool>(
            context: context,
            builder: (context) => ShiftEditorDialog(
                    title: Text(context.l10n.teamEditTitle),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final paragraph in message.split('\n\n'))
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(paragraph,
                                    style: const TextStyle(height: 1.5)))
                        ]),
                    actions: [
                      AppSecondButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(context.l10n.commonCancel)),
                      AppSecondButton(
                          variant: destructive
                              ? AppSecondButtonVariant.danger
                              : AppSecondButtonVariant.success,
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(context.l10n.commonOk)),
                    ])) ??
        false;
  }

  Future<void> _save() async {
    final team = _selected;
    if (_busy || team == null || team == widget.teams.myTeam) return;
    setState(() => _busy = true);
    final accepted = await _confirm(
        context.l10n.teamEditSwitchConfirm(widget.teams.myTeam, team));
    if (!mounted) return;
    if (!accepted) {
      setState(() => _busy = false);
      return;
    }
    // Use the date shown by the chips even if confirmation crosses midnight.
    final saved = await applyScheduleChange(
        context,
        ref,
        ScheduleChangeSelection(
            widget.teams.indexOn(team, widget.date, widget.pattern.length),
            team),
        widget.date,
        widget.teams);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, TeamScheduleEditResult.changed);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _recreate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final accepted =
        await _confirm(context.l10n.teamEditRecreateConfirm, destructive: true);
    if (!mounted) return;
    if (!accepted) {
      setState(() => _busy = false);
      return;
    }
    try {
      await DatabaseService.instance.saveTeamScheduleConfig(null);
      if (mounted) Navigator.pop(context, TeamScheduleEditResult.recreate);
    } catch (error) {
      debugPrint('Team schedule reset failed: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.settingsScheduleChangeFailedWithError(
              context.localizedErrorDetail(error)))));
    }
  }

  Widget _recreateAction({bool compact = false}) {
    final title = context.l10n.teamEditRecreateTitle;
    if (compact) {
      return TextButton.icon(
        key: const ValueKey('team-edit-recreate'),
        onPressed: _busy ? null : _recreate,
        icon: const Icon(Icons.restart_alt),
        label: Text(title),
      );
    }
    return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const ValueKey('team-edit-recreate'),
          title: Text(title),
          subtitle: Text(context.l10n.teamEditRecreateHint),
          trailing: const Icon(Icons.restart_alt),
          onTap: _busy ? null : _recreate,
        ));
  }

  String? _teamAt(int index) {
    final teams =
        widget.teams.teamsAt(index, widget.date, widget.pattern.length);
    return teams.contains(widget.teams.myTeam)
        ? widget.teams.myTeam
        : teams.firstOrNull;
  }

  @override
  Widget build(BuildContext context) =>
      SettingsAppearance(builder: _buildStyled);

  Widget _buildStyled(BuildContext context) {
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: Text(context.l10n.teamEditTitle)),
          body: AdaptiveFormBody(
              child: SafeArea(
                  child: Column(children: [
            Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(context.l10n.teamEditChangedQuestion,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: const ValueKey('team-edit-switch'),
                    title: Text(context.l10n.teamSwitchAction),
                    subtitle: Text(_ko ? 'A조 → C조, B조 → D조 등' : 'A → C, B → D'),
                    trailing: Icon(
                        _showTeams ? Icons.expand_less : Icons.expand_more),
                    onTap: _busy
                        ? null
                        : () => setState(() => _showTeams = !_showTeams),
                  )),
              if (_showTeams) ...[
                const SizedBox(height: 20),
                Text(context.l10n.teamEditPositionsOn(_ko
                    ? '${widget.date.month}/${widget.date.day}'
                    : DateFormat.yMMMd(
                            Localizations.localeOf(context).toString())
                        .format(widget.date))),
                const SizedBox(height: 12),
                if (widget.teams.individual) ...[
                  for (final team in widget.teams.names)
                    TeamRuleCard(
                      key: ValueKey('team-switch-$team'),
                      team: team,
                      rule: widget.teams.rules[team],
                      date: widget.date,
                      isMine: team == widget.teams.myTeam,
                      selected: _selected == team,
                      onTap: _busy || team == widget.teams.myTeam
                          ? null
                          : () => setState(() => _selected = team),
                    )
                ] else
                  TeamAssignmentGrid(
                    pattern: widget.pattern,
                    teamAtSlot: _teamAt,
                    isMine: (index) => _teamAt(index) == widget.teams.myTeam,
                    canSelectSlot: (index) => !_busy && _teamAt(index) != null,
                    selectedIndex: _selected == null
                        ? null
                        : widget.teams.indexOn(
                            _selected!, widget.date, widget.pattern.length),
                    onTapSlot: (index) =>
                        setState(() => _selected = _teamAt(index)),
                    keyPrefix: 'team-switch-slot',
                  ),
                const SizedBox(height: 16),
                Text(context.l10n.teamEditChooseTeam),
                if (_selected != null) ...[
                  const SizedBox(height: 12),
                  Text(
                      context.l10n.teamEditSwitchPreview(
                          widget.teams.myTeam, _selected!),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          height: 1.5)),
                ],
              ] else
                _recreateAction(),
            ])),
            if (_showTeams)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Divider(),
                    Align(
                        alignment: Alignment.centerRight,
                        child: _recreateAction(compact: true)),
                  ])),
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(children: [
                  Expanded(
                      child: AppSecondButton(
                          onPressed:
                              _busy ? null : () => Navigator.pop(context),
                          child: Text(context.l10n.commonCancel))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: AppButton(
                          onPressed: _busy || !_showTeams || _selected == null
                              ? null
                              : _save,
                          child: Text(context.l10n.commonSave))),
                ])),
          ]))),
        ));
  }
}
