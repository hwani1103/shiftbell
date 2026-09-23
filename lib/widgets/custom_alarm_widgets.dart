// lib/widgets/custom_alarm_widgets.dart
//
// ⭐ 2026-09-23 (1.0.24 B) - 커스텀 알람 UI 조각. calendar_tab.dart(5,800줄+)에 직접 넣지 않고 여기로 분리
// (출시전 코드 품질 검토 "거대 파일은 기능 추가 때마다 떼어내기" 규칙).
//  - CustomAlarmPresetBar: 달력 헤더 "2026년 9월" 오른쪽 5칸(탭 = 할당 모드 선택, 길게 눌러 끌기 = 날짜에 놓기, ✎ = 편집)
//  - showCustomAlarmPresetEditor: 5칸 편집 하단 시트(시각·종류·비우기)
//  - CustomAlarmDayList: 날짜 상세 팝업의 "커스텀 알람" 목록(삭제)
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

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 할당 결과 안내 문구. 1시간 이내면 "N분 후에 울려요", 오늘이면 "오늘 HH:mm", 그 외 "M월 d일 HH:mm".
String customAlarmOutcomeMessage(BuildContext context, CustomAlarmAssignOutcome outcome, {DateTime? now}) {
  final l10n = context.l10n;
  final at = outcome.ringAt;
  switch (outcome.result) {
    case CustomAlarmAssignResult.scheduled:
      final n = now ?? DateTime.now();
      final minutes = (at.difference(n).inSeconds / 60).ceil();
      if (minutes <= 60) return l10n.customAlarmScheduledSoon(minutes < 1 ? 1 : minutes);
      final isToday = at.year == n.year && at.month == n.month && at.day == n.day;
      if (isToday) return l10n.customAlarmScheduledToday(_hm(at));
      final locale = Localizations.localeOf(context).languageCode == 'ko' ? 'ko' : 'en';
      return l10n.customAlarmScheduledOn(DateFormat.MMMd(locale).format(at), _hm(at));
    case CustomAlarmAssignResult.past:
      return l10n.customAlarmPast;
    case CustomAlarmAssignResult.duplicate:
      return l10n.customAlarmDuplicate(_hm(at));
    case CustomAlarmAssignResult.dailyLimit:
      return l10n.customAlarmDailyLimit(CustomAlarmService.dailyLimit);
    case CustomAlarmAssignResult.scheduleFailed:
      return l10n.customAlarmScheduleFailed;
    case CustomAlarmAssignResult.emptyPreset:
      return l10n.customAlarmSlotEmpty;
  }
}

/// 달력 헤더 오른쪽 5칸. 남은 폭을 5등분하고 글자는 FittedBox로 줄여 좁은 화면·큰 글씨에서도 한 줄 유지.
class CustomAlarmPresetBar extends ConsumerWidget {
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onEdit;
  /// 헤더 배경이 어두운 테마(굵은 격자·메인 다크)면 true - 글자/테두리를 밝게.
  final bool onDarkHeader;

  const CustomAlarmPresetBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onEdit,
    this.onDarkHeader = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(customAlarmPresetsProvider);
    final scheme = Theme.of(context).colorScheme;
    final fg = onDarkHeader ? Colors.white : scheme.onSurface;
    final line = onDarkHeader ? Colors.white54 : scheme.outlineVariant;
    final accent = onDarkHeader ? Colors.white : scheme.primary;

    return LayoutBuilder(builder: (context, constraints) {
      final editW = 24.w;
      final gap = 3.w;
      final chipW = ((constraints.maxWidth - editW - gap * kCustomAlarmPresetCount) / kCustomAlarmPresetCount)
          .clamp(18.0, 64.0);
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < kCustomAlarmPresetCount; i++) ...[
            _chip(context, i, presets[i], chipW, fg, line, accent),
            SizedBox(width: gap),
          ],
          SizedBox(
            width: editW,
            height: 26.h,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16.sp,
              tooltip: context.l10n.customAlarmEditTooltip,
              icon: Icon(Icons.edit_outlined, color: fg.withValues(alpha: 0.7)),
              onPressed: onEdit,
            ),
          ),
        ],
      );
    });
  }

  Widget _chip(BuildContext context, int index, CustomAlarmPreset preset, double width, Color fg, Color line,
      Color accent) {
    final selected = selectedIndex == index;
    final body = Container(
      width: width,
      height: 26.h,
      padding: EdgeInsets.symmetric(horizontal: 2.w),
      decoration: BoxDecoration(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: selected ? accent : line, width: selected ? 1.4 : 1),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: preset.isEmpty
            ? Icon(Icons.add, size: 14.sp, color: fg.withValues(alpha: 0.5))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(customAlarmTypeIcon(preset.alarmTypeId),
                    size: 10.sp, color: selected ? _onAccent(accent) : fg.withValues(alpha: 0.7)),
                SizedBox(width: 1.w),
                Text(preset.time!,
                    style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: selected ? _onAccent(accent) : fg)),
              ]),
      ),
    );
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => preset.isEmpty ? onEdit() : onSelect(index),
      child: body,
    );
    if (preset.isEmpty) return tappable;
    // 길게 눌러 날짜 칸으로 끌어다 놓기(보조 할당 방식). 놓을 곳은 calendar_tab의 DragTarget<int>(데이터 = 칸 번호).
    return LongPressDraggable<int>(
      data: index,
      feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.9, child: body)),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: tappable,
    );
  }

  Color _onAccent(Color accent) => ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

/// 5칸 편집 하단 시트. 저장을 눌러야 반영(취소하면 그대로).
Future<void> showCustomAlarmPresetEditor(BuildContext context, WidgetRef ref) async {
  var draft = List<CustomAlarmPreset>.of(ref.read(customAlarmPresetsProvider));
  final l10n = context.l10n;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheetState) {
      final scheme = Theme.of(sheetContext).colorScheme;
      Widget typeButton(int slot, int typeId, IconData icon, String label) {
        final sel = draft[slot].alarmTypeId == typeId;
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: () => setSheetState(() => draft[slot] = draft[slot].copyWith(alarmTypeId: typeId)),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 6.h),
              decoration: BoxDecoration(
                color: sel ? scheme.primary : null,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: sel ? scheme.primary : scheme.outlineVariant),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14.sp, color: sel ? scheme.onPrimary : scheme.onSurfaceVariant),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.sp, color: sel ? scheme.onPrimary : scheme.onSurfaceVariant)),
              ]),
            ),
          ),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.customAlarmEditorTitle, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 4.h),
              Text(l10n.customAlarmEditorDesc,
                  style: TextStyle(fontSize: 12.sp, color: scheme.onSurfaceVariant, height: 1.4)),
              SizedBox(height: 12.h),
              for (var i = 0; i < kCustomAlarmPresetCount; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Row(children: [
                    SizedBox(
                      width: 74.w,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 10.h)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: sheetContext,
                            initialTime: draft[i].timeOfDay ?? const TimeOfDay(hour: 7, minute: 0),
                            builder: (c, child) => MediaQuery(
                              data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setSheetState(() => draft[i] = draft[i].copyWith(time: CustomAlarmPreset.formatTime(picked)));
                          }
                        },
                        child: FittedBox(
                          child: Text(draft[i].time ?? l10n.customAlarmSlotEmpty,
                              style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: draft[i].isEmpty ? FontWeight.normal : FontWeight.bold)),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    typeButton(i, 1, Icons.volume_up, l10n.alarmSoundVibration),
                    SizedBox(width: 4.w),
                    typeButton(i, 2, Icons.vibration, l10n.alarmVibration),
                    SizedBox(width: 4.w),
                    typeButton(i, 3, Icons.volume_off, l10n.alarmSilent),
                    IconButton(
                      tooltip: l10n.customAlarmSlotClear,
                      icon: Icon(Icons.close, size: 18.sp),
                      onPressed: draft[i].isEmpty ? null : () => setSheetState(() => draft[i] = draft[i].copyWith(clearTime: true)),
                    ),
                  ]),
                ),
              SizedBox(height: 4.h),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(sheetContext, false), child: Text(l10n.commonCancel)),
                SizedBox(width: 8.w),
                FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: Text(l10n.commonSave)),
              ]),
            ],
          ),
        ),
      );
    }),
  );
  if (saved == true) {
    await ref.read(customAlarmPresetsProvider.notifier).saveAll(draft);
  }
}

/// 날짜 상세 팝업의 "커스텀 알람" 목록. 해당 날짜에 커스텀 알람이 없으면 아무것도 그리지 않음.
class CustomAlarmDayList extends ConsumerWidget {
  final DateTime day;
  const CustomAlarmDayList({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(alarmNotifierProvider).valueOrNull ?? const <Alarm>[];
    final list = alarms
        .where((a) =>
            a.type == 'custom' &&
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
            style: TextStyle(fontSize: 14.sp, color: scheme.onSurface, fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        Wrap(spacing: 8.w, runSpacing: 6.h, children: [
          for (final a in list)
            InputChip(
              avatar: Icon(customAlarmTypeIcon(a.alarmTypeId), size: 14.sp),
              label: Text(a.time, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
              onDeleted: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: Text(context.l10n.customAlarmDeleteConfirm(a.time)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.l10n.commonCancel)),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: Text(context.l10n.commonDelete)),
                    ],
                  ),
                );
                if (ok != true || a.id == null) return;
                await ref.read(alarmNotifierProvider.notifier).deleteAlarm(a.id!, a.date);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.customAlarmDeleted)));
                }
              },
            ),
        ]),
      ]),
    );
  }
}
