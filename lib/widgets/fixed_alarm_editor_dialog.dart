import '../widgets/app_ui_feedback.dart';
import 'package:flutter/material.dart';
import '../screens/onboarding_screen.dart' show AlarmSetting;
import '../constants/alarm_limits.dart';
import '../constants/layout_limits.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/app_ui_theme.dart';
import 'app_ui_components.dart';
import 'app_ui_theme_scope.dart';
import 'alarm_time_editor.dart';
import 'day_offset_chip.dart';

class FixedAlarmEditorDialog extends StatefulWidget {
  final String shift;
  final String? title;
  final String? hint;
  final List<AlarmSetting> initialAlarms;
  final Function(List<AlarmSetting>) onSave;

  const FixedAlarmEditorDialog({
    super.key,
    this.title,
    this.hint,
    required this.shift,
    required this.initialAlarms,
    required this.onSave,
  });

  @override
  State<FixedAlarmEditorDialog> createState() => FixedAlarmEditorDialogState();
}

class FixedAlarmEditorDialogState extends State<FixedAlarmEditorDialog> {
  late List<AlarmSetting> _alarms;

  @override
  void initState() {
    super.initState();
    _alarms = List.from(widget.initialAlarms);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: AppLayout.of(context).dialogWidth,
                maxHeight: MediaQuery.sizeOf(context).height * .85),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppUiText(
                          widget.title ??
                              context.l10n.onboardingFixedAlarmDialogTitle(
                                  widget.shift),
                          role: AppTextRole.section),
                      const SizedBox(height: 8),
                      AppUiText(
                          widget.hint ??
                              context.l10n.onboardingFixedAlarmMaxHint(
                                  kMaxAlarmTemplatesPerShift),
                          role: AppTextRole.supporting,
                          tone: AppTextTone.secondary),
                      const SizedBox(height: 12),
                      Flexible(
                          child: SingleChildScrollView(
                              key: const ValueKey(
                                  'onboarding-alarm-editor-list'),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final entry in _alarms.asMap().entries)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: AppUiCard(
                                              padding: const EdgeInsets.all(
                                                  AppUiMetrics
                                                      .compactCardPadding),
                                              child: Column(children: [
                                                Row(children: [
                                                  Expanded(
                                                      child: InkWell(
                                                          onTap: () =>
                                                              _editAlarmTime(
                                                                  entry.key),
                                                          child: Padding(
                                                              padding: const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 8),
                                                              child: Wrap(
                                                                  spacing:
                                                                      AppUiMetrics
                                                                              .gap /
                                                                          2,
                                                                  runSpacing:
                                                                      AppUiMetrics
                                                                              .gap /
                                                                          4,
                                                                  crossAxisAlignment:
                                                                      WrapCrossAlignment
                                                                          .center,
                                                                  children: [
                                                                    DayOffsetBadge(
                                                                        dayOffset: entry
                                                                            .value
                                                                            .dayOffset),
                                                                    AppUiText(
                                                                        _formatAlarmTime(entry
                                                                            .value
                                                                            .time),
                                                                        role: AppTextRole
                                                                            .section),
                                                                    Icon(
                                                                        Icons
                                                                            .edit_outlined,
                                                                        size:
                                                                            16,
                                                                        color: p
                                                                            .secondaryText),
                                                                  ])))),
                                                  IconButton(
                                                      icon: Icon(
                                                          AppUiIcons.delete,
                                                          color: p.danger,
                                                          size: 20),
                                                      tooltip: context
                                                          .l10n.commonDelete,
                                                      onPressed: () => setState(
                                                          () =>
                                                              _alarms.removeAt(
                                                                  entry.key))),
                                                ]),
                                                const SizedBox(height: 4),
                                                AlarmTypeSelector(
                                                    value: entry
                                                        .value.alarmTypeId,
                                                    onChanged: (value) =>
                                                        setState(() => _alarms[
                                                            entry
                                                                .key] = entry
                                                            .value
                                                            .copyWith(
                                                                alarmTypeId:
                                                                    value))),
                                              ]))),
                                  ]))),
                      const SizedBox(height: 8),
                      AppUiButton(
                          label: context.l10n.alarmAdd,
                          icon: Icons.add,
                          compact: true,
                          action: AppUiAction.secondary,
                          onPressed: _alarms.length < kMaxAlarmTemplatesPerShift
                              ? _addAlarm
                              : null),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: AppUiButton(
                                label: context.l10n.commonCancel,
                                action: AppUiAction.secondary,
                                onPressed: () => Navigator.pop(context))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: AppUiButton(
                                label: context.l10n.commonSave,
                                onPressed: () {
                                  _alarms.sort((a, b) => (a.time.hour * 60 +
                                          a.time.minute)
                                      .compareTo(
                                          b.time.hour * 60 + b.time.minute));
                                  widget.onSave(_alarms);
                                  Navigator.pop(context);
                                })),
                      ]),
                    ]))));
  }

  String _formatAlarmTime(TimeOfDay time) =>
      time.hour.toString().padLeft(2, '0') +
      ':' +
      time.minute.toString().padLeft(2, '0');

  // ⭐ 알람 시간 수정
  Future<void> _editAlarmTime(int index) async {
    final currentAlarm = _alarms[index];
    await showAppUiDialog(
      context: context,
      builder: (context) => AlarmTimePicker(
        shiftName: widget.shift,
        initialTime: currentAlarm.time,
        initialDayOffset: currentAlarm.dayOffset,
        onTimeSelected: (time, dayOffset) async {
          // ⭐ 중복 체크 (자기 자신 제외) - 같은 시각이어도 전날/당일/다음날이 다르면
          // 서로 다른 실제 날짜에 울리는 별개의 알람이라 중복이 아님.
          final isDuplicate = _alarms.asMap().entries.any((entry) {
            return entry.key != index &&
                entry.value.time.hour == time.hour &&
                entry.value.time.minute == time.minute &&
                entry.value.dayOffset == dayOffset;
          });

          if (isDuplicate) {
            await showAppUiDialog(
              context: context,
              builder: (context) => AppUiDialog(
                title: context.l10n.alarmDuplicate,
                content: AppUiText(context.l10n
                    .alarmAlreadyExistsAtTime(_formatAlarmTime(time))),
                actions: [
                  AppUiButton(
                      label: context.l10n.commonOk,
                      onPressed: () => Navigator.pop(context))
                ],
              ),
            );
            return;
          }

          setState(() {
            _alarms[index] =
                currentAlarm.copyWith(time: time, dayOffset: dayOffset);
          });
        },
      ),
    );
  }

  Future<void> _addAlarm() async {
    await showAppUiDialog(
      context: context,
      builder: (context) => AlarmTimePicker(
        shiftName: widget.shift,
        onTimeSelected: (time, dayOffset) async {
          // ⭐ 중복 체크 (시각 + 전날/당일/다음날이 모두 같을 때만 중복)
          final isDuplicate = _alarms.any((alarm) =>
              alarm.time.hour == time.hour &&
              alarm.time.minute == time.minute &&
              alarm.dayOffset == dayOffset);

          if (isDuplicate) {
            await showAppUiDialog(
              context: context,
              builder: (context) => AppUiDialog(
                title: context.l10n.alarmDuplicate,
                content: AppUiText(context.l10n
                    .alarmAlreadyExistsAtTime(_formatAlarmTime(time))),
                actions: [
                  AppUiButton(
                      label: context.l10n.commonOk,
                      onPressed: () => Navigator.pop(context))
                ],
              ),
            );
            return;
          }

          setState(() {
            // 기본값: 소리 (alarmTypeId = 1)
            _alarms.add(
                AlarmSetting(time: time, alarmTypeId: 1, dayOffset: dayOffset));
          });
        },
      ),
    );
  }
}
