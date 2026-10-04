import '../services/app_analytics.dart';
import 'alarm_time_editor.dart';
// lib/widgets/custom_alarm_widgets.dart
//
// 원터치 알람 UI 조각. calendar_tab.dart와 분리해 설정·날짜 목록을 관리한다.
// (출시전 코드 품질 검토 "거대 파일은 기능 추가 때마다 떼어내기" 규칙).
//  - showCustomAlarmPresetEditor: 5칸 편집 하단 시트(시각·종류·비우기)
//  - CustomAlarmDayList: 날짜 상세 팝업의 "원터치 알람" 목록(삭제)
//  - customAlarmOutcomeMessage: 할당 결과 안내 문구

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n_extensions.dart';
import '../models/alarm.dart';
import '../models/custom_alarm_preset.dart';
import '../providers/alarm_provider.dart';
import '../providers/custom_alarm_preset_provider.dart';
import '../services/custom_alarm_service.dart';

IconData customAlarmTypeIcon(int alarmTypeId) => switch (alarmTypeId) {
      2 => Icons.vibration,
      3 => Icons.volume_off,
      _ => Icons.volume_up,
    };

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 할당 결과 안내 문구. 1시간 이내면 "N분 후에 울려요", 오늘이면 "오늘 HH:mm", 그 외 "M월 d일 HH:mm".
String customAlarmOutcomeMessage(
    BuildContext context, CustomAlarmAssignOutcome outcome,
    {DateTime? now, int alarmTypeId = 1}) {
  final l10n = context.l10n;
  final at = outcome.ringAt;
  switch (outcome.result) {
    case CustomAlarmAssignResult.scheduled:
      final ko = Localizations.localeOf(context).languageCode == 'ko';
      final type = alarmTypeId == 3
          ? (ko ? '무음' : 'silent')
          : alarmTypeId == 2
              ? (ko ? '진동' : 'vibration')
              : (ko ? '소리+진동' : 'sound + vibration');
      return ko
          ? '${_hm(at)}에 $type 알람이 예약됐어요.'
          : '$type alarm scheduled for ${_hm(at)}.';
    case CustomAlarmAssignResult.past:
      return l10n.customAlarmPast;
    case CustomAlarmAssignResult.outsideWindow:
      return l10n.customAlarmOutsideWindow;
    case CustomAlarmAssignResult.duplicate:
      final ko = Localizations.localeOf(context).languageCode == 'ko';
      final source = outcome.existingType == 'fixed'
          ? (ko ? '고정 알람' : 'fixed alarm')
          : outcome.existingType == 'custom'
              ? (ko ? '원터치 알람' : 'one-tap alarm')
              : (ko ? '알람' : 'alarm');
      return ko
          ? '${at.month}/${at.day} ${_hm(at)}에 이미 $source이 있어 원터치 알람을 추가하지 않았어요.'
          : 'A $source is already set for ${at.month}/${at.day} ${_hm(at)}. No one-tap alarm was added.';
    case CustomAlarmAssignResult.alreadyAssigned:
      return Localizations.localeOf(context).languageCode == 'ko'
          ? '이 원터치 알람은 해당 날짜에 이미 할당되어 있어요.'
          : 'This one-tap alarm is already assigned to that day.';
    case CustomAlarmAssignResult.scheduleFailed:
      return l10n.customAlarmScheduleFailed;
    case CustomAlarmAssignResult.emptyPreset:
      return l10n.customAlarmSlotEmpty;
  }
}

/// 5칸 편집 하단 시트. 저장을 눌러야 반영(취소하면 그대로).
Future<void> showCustomAlarmPresetEditor(BuildContext context, WidgetRef ref,
    {int? slot, bool delete = false}) async {
  final original =
      List<CustomAlarmPreset>.of(ref.read(customAlarmPresetsProvider));
  var draft = List<CustomAlarmPreset>.of(original);
  final l10n = context.l10n;
  if (delete && slot != null) draft[slot] = CustomAlarmPreset.empty;
  final index = slot ?? original.indexWhere((preset) => preset.isEmpty);
  if (index < 0) return;
  var selectedType = draft[index].alarmTypeId;
  final ko = Localizations.localeOf(context).languageCode == 'ko';
  if (!delete && !draft[index].isEmpty) {
    final assignments =
        await CustomAlarmService.instance.futureAssignments(index);
    if (!context.mounted) return;
    if (assignments.isNotEmpty) {
      AppAnalytics.track(AnalyticsEvent.oneTapPresetBlocked);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(ko
              ? '이미 날짜에 추가한 알람이에요. 수정하려면 먼저 해당 알람을 삭제해 주세요.'
              : 'Remove assigned alarms before editing this preset.'),
        ));
      return;
    }
  }
  if (!context.mounted) return;
  var saved = delete;
  if (!delete) {
    AppAnalytics.track(AnalyticsEvent.oneTapPresetEditorOpened,
        params: {'mode': original[index].isEmpty ? 'create' : 'edit'});
    await showDialog<void>(
        context: context,
        builder: (context) => AlarmTimePicker(
              shiftName: ko ? '원터치 알람 설정' : 'One-tap alarm settings',
              description: ko
                  ? '시각과 울림 방식을 저장해 주세요. 저장한 원터치 알람은 오늘과 내일에만 추가할 수 있어요.\n(근무별 고정 알람과 같은 시각이면 알람은 하나만 저장돼요.)'
                  : 'Save a time and sound setting to add an alarm for today or tomorrow. Only one alarm is saved if a fixed alarm has the same time.',
              showDayOffset: false,
              initialTime:
                  draft[index].timeOfDay ?? const TimeOfDay(hour: 7, minute: 0),
              alarmTypeId: selectedType,
              onTypeChanged: (value) => selectedType = value,
              onTimeSelected: (time, _) async {
                draft[index] = draft[index].copyWith(
                    time: CustomAlarmPreset.formatTime(time),
                    alarmTypeId: selectedType);
                saved = true;
              },
            ));
  }
  if (!saved) AppAnalytics.track(AnalyticsEvent.oneTapPresetCancelled);
  if (saved == true) {
    if (!context.mounted) return;
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final deletions = <Alarm>[];
    final slotsToDelete = <int>[];
    for (var slot = 0; slot < kCustomAlarmPresetCount; slot++) {
      if (draft[slot] == original[slot]) continue;
      final assignments =
          await CustomAlarmService.instance.futureAssignments(slot);
      if (assignments.isEmpty) continue;
      final dates = assignments
          .map((a) => DateFormat('M/d HH:mm').format(a.date!))
          .join(', ');
      if (!draft[slot].isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                content: Text(ko
                    ? '$dates에 이미 할당되어 있어 수정할 수 없습니다.'
                    : 'Already assigned on $dates. Delete the preset before changing it.')));
        }
        return;
      }
      deletions.addAll(assignments);
      slotsToDelete.add(slot);
    }
    if (deletions.isNotEmpty) {
      if (!context.mounted) return;
      final dates = deletions
          .map((a) => DateFormat('M/d HH:mm').format(a.date!))
          .join(', ');
      final replacementLines = <String>[];
      for (final alarm in deletions) {
        final fixed = await CustomAlarmService.instance
            .previewFixedReplacement(alarm.date!);
        replacementLines.add('${DateFormat('M/d HH:mm').format(alarm.date!)}: '
            '${fixed == null ? (ko ? '대체 알람 없음' : 'no replacement') : (ko ? '${fixed.shiftType} 고정 알람 재예약' : '${fixed.shiftType} fixed alarm restored')}');
      }
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: Text(
                      ko ? '원터치 알람 설정 삭제' : 'Delete one-tap alarm settings'),
                  content: Text(ko
                      ? '$dates에 원터치 알람이 등록되어 있습니다. 설정을 삭제하면 해당 날짜의 알람도 삭제됩니다.\n${replacementLines.join('\n')}'
                      : 'One-tap alarms are assigned on $dates. Deleting these settings also deletes those alarms.\n${replacementLines.join('\n')}'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(l10n.commonCancel)),
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(l10n.commonDelete)),
                  ]));
      if (confirmed != true) return;
      var failed = false;
      for (final slot in slotsToDelete) {
        final result = await ref
            .read(alarmNotifierProvider.notifier)
            .deleteOneTapSlot(slot);
        failed = failed || result.reservationFailed;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(failed
                  ? (ko
                      ? '원터치 알람 삭제 후 일부 고정 알람 예약에 실패했습니다. 갱신을 다시 시도합니다.'
                      : 'Some fixed alarms could not be scheduled. A refresh will retry them.')
                  : (ko
                      ? '원터치 알람과 연결된 날짜를 삭제하고 고정 알람을 재계산했습니다.'
                      : 'One-tap assignments deleted and fixed alarms recalculated.'))));
      }
    }
    await ref.read(customAlarmPresetsProvider.notifier).saveAll(draft);
    if (draft[index] != original[index]) {
      AppAnalytics.track(delete
          ? AnalyticsEvent.oneTapPresetDeleted
          : original[index].isEmpty
              ? AnalyticsEvent.oneTapPresetSaved
              : AnalyticsEvent.oneTapPresetUpdated);
    }
  }
}

/// 날짜 상세 팝업의 "커스텀 알람" 목록. 해당 날짜에 커스텀 알람이 없으면 아무것도 그리지 않음.
class CustomAlarmDayList extends ConsumerWidget {
  final DateTime day;
  const CustomAlarmDayList({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms =
        ref.watch(alarmNotifierProvider).valueOrNull ?? const <Alarm>[];
    final list = alarms
        .where((a) =>
            (a.type == 'custom' || a.presetSlot != null) &&
            a.date != null &&
            a.date!.year == day.year &&
            a.date!.month == day.month &&
            a.date!.day == day.day)
        .toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
    if (list.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.customAlarmLabel,
            style: TextStyle(
                fontSize: 14.sp,
                color: scheme.onSurface,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        Wrap(spacing: 8.w, runSpacing: 6.h, children: [
          for (final a in list)
            InputChip(
              avatar: Icon(customAlarmTypeIcon(a.alarmTypeId), size: 14.sp),
              label: Text(a.time,
                  style:
                      TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
              onDeleted: () async {
                final preview = await CustomAlarmService.instance
                    .previewFixedReplacement(a.date!);
                if (!context.mounted) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: Text(() {
                      final ko =
                          Localizations.localeOf(context).languageCode == 'ko';
                      final replacementText = preview == null
                          ? (ko
                              ? '삭제하면 이 시각에는 알람이 남지 않습니다.'
                              : 'No alarm will remain at this time.')
                          : (ko
                              ? '삭제 후 ${preview.shiftType} 고정 알람을 다시 예약합니다.'
                              : 'The ${preview.shiftType} fixed alarm will be scheduled after deletion.');
                      return '${context.l10n.customAlarmDeleteConfirm(a.time)}\n$replacementText';
                    }()),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(context.l10n.commonCancel)),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(context.l10n.commonDelete)),
                    ],
                  ),
                );
                if (ok != true || a.id == null) return;
                final result = await ref
                    .read(alarmNotifierProvider.notifier)
                    .deleteAlarm(a.id!, a.date);
                if (context.mounted) {
                  final ko =
                      Localizations.localeOf(context).languageCode == 'ko';
                  final message = result.reservationFailed
                      ? (ko
                          ? '원터치 알람은 삭제됐지만 고정 알람 예약에 실패했습니다. 갱신을 다시 시도합니다.'
                          : 'One-tap alarm deleted, but fixed alarm scheduling failed. A refresh will retry it.')
                      : result.fixedReplacement
                          ? (ko
                              ? '원터치 알람을 삭제하고 고정 알람을 예약했습니다.'
                              : 'One-tap alarm deleted and fixed alarm scheduled.')
                          : context.l10n.customAlarmDeleted;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(message)));
                }
              },
            ),
        ]),
      ]),
    );
  }
}
