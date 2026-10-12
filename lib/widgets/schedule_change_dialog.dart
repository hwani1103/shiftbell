import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../l10n/l10n_extensions.dart';
import '../models/team_schedule_config.dart';
import 'app_second_button.dart';
import 'app_button.dart';
import 'app_shift_chip.dart';
import 'shift_editor_dialog.dart';
import 'shift_label_layout.dart';

class ScheduleChangeSelection {
  const ScheduleChangeSelection(this.index, this.team);
  final int index;
  final String? team;
}

class ScheduleChangeDialog extends StatefulWidget {
  const ScheduleChangeDialog(
      {super.key, required this.pattern, required this.date, this.teams});
  final List<String> pattern;
  final DateTime date;
  final TeamScheduleConfig? teams;
  @override
  State<ScheduleChangeDialog> createState() => _ScheduleChangeDialogState();
}

class _ScheduleChangeDialogState extends State<ScheduleChangeDialog> {
  int? _index;
  bool _confirming = false;

  Future<void> _save() async {
    if (_index == null || _confirming) return;
    if (widget.teams != null) {
      setState(() => _confirming = true);
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => ShiftEditorDialog(
                  title: Text(context.l10n.shiftChangeSchedule),
                  content: Text(context.l10n.teamScheduleResetConfirm,
                      style: const TextStyle(height: 1.5)),
                  actions: [
                    AppSecondButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(context.l10n.commonCancel)),
                    AppSecondButton(
                        variant: AppSecondButtonVariant.danger,
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(context.l10n.commonOk)),
                  ]));
      if (!mounted) return;
      setState(() => _confirming = false);
      if (accepted != true) return;
    }
    if (mounted) Navigator.pop(context, ScheduleChangeSelection(_index!, null));
  }

  @override
  Widget build(BuildContext context) {
    final style =
        TextStyle(fontSize: 13.sp, height: 1.15, fontWeight: FontWeight.w600);
    final metrics = ShiftCellMetrics.forNames(
        widget.pattern, style, MediaQuery.textScalerOf(context),
        minWidth: 40.w, minHeight: 36.h);
    return ShiftEditorDialog(
        title: Text(context.l10n.shiftChangeSchedule),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.onboardingTodayShiftQuestion(context
                      .usesKoreanFeatures
                  ? '${widget.date.month}/${widget.date.day}'
                  : DateFormat.MMMd(Localizations.localeOf(context).toString())
                      .format(widget.date))),
              const SizedBox(height: 8),
              Text(context.l10n.settingsSelectTodayShiftFromPattern),
              const SizedBox(height: 16),
              // One full cycle, with team markers directly below their current slot.
              Wrap(spacing: 4, runSpacing: 8, children: [
                for (var i = 0; i < widget.pattern.length; i++)
                  SizedBox(
                      width: metrics.width,
                      child: Padding(
                          padding: const EdgeInsets.all(1.3),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('${i + 1}'),
                            const SizedBox(height: 4),
                            SizedBox(
                                height: metrics.height,
                                width: double.infinity,
                                child: AppShiftChip(
                                    key: ValueKey('schedule-slot-$i'),
                                    label: widget.pattern[i],
                                    dense: true,
                                    selected: _index == i,
                                    strongSelected: true,
                                    cellTextStyle: style.copyWith(
                                        color: _index == i
                                            ? Colors.white
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                    onTap: () => setState(() {
                                          _index = i;
                                        }))),
                            const SizedBox(height: 6),
                          ]))),
              ]),
              if (widget.teams != null) ...[
                const SizedBox(height: 16),
                Text(context.l10n.teamScheduleResetConfirm,
                    style: const TextStyle(height: 1.5)),
              ],
              const SizedBox(height: 16),
              Text(context.l10n.settingsScheduleChangeWarning),
            ]),
        actions: [
          AppSecondButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonCancel)),
          AppButton(
              onPressed: _index == null || _confirming ? null : _save,
              child: Text(context.l10n.commonSave)),
        ]);
  }
}
