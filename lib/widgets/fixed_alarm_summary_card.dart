import 'package:flutter/material.dart';
import '../screens/onboarding_screen.dart' show AlarmSetting;
import '../constants/alarm_limits.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_ui_theme.dart';
import 'app_ui_components.dart';
import 'day_offset_chip.dart';

class FixedAlarmSummaryCard extends StatelessWidget {
  const FixedAlarmSummaryCard(
      {super.key,
      required this.shift,
      required this.alarms,
      required this.onEdit,
      this.editKey,
      this.tapAnywhere = false});
  final bool tapAnywhere;
  final String shift;
  final List<AlarmSetting> alarms;
  final VoidCallback onEdit;
  final Key? editKey;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: tapAnywhere ? onEdit : null,
      borderRadius: BorderRadius.circular(AppUiMetrics.cardRadius),
      child: AppUiCard(
          padding: const EdgeInsets.all(AppUiMetrics.compactCardPadding),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(width: 100, child: AppUiShiftChip(name: shift)),
              const SizedBox(width: 8),
              Expanded(
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppUiText(
                                alarms.length.toString() +
                                    ' / ' +
                                    kMaxAlarmTemplatesPerShift.toString(),
                                role: AppTextRole.supporting,
                                tone: AppTextTone.secondary),
                            AppUiButton(
                                key: editKey,
                                label: context.l10n.onboardingEditAlarms,
                                icon: Icons.edit_outlined,
                                compact: true,
                                action: AppUiAction.secondary,
                                onPressed: onEdit),
                          ]))),
            ]),
            if (alarms.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final alarm in alarms)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Flexible(
                          child: DayOffsetBadge(dayOffset: alarm.dayOffset)),
                      const SizedBox(width: 8),
                      AppUiText(
                          '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}',
                          role: AppTextRole.section),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppUiText(
                              switch (alarm.alarmTypeId) {
                                2 => context.l10n.alarmVibration,
                                3 => context.l10n.alarmSilent,
                                _ => context.l10n.alarmSoundVibration
                              },
                              role: AppTextRole.supporting,
                              tone: AppTextTone.secondary)),
                    ])),
            ],
          ])));
}
