import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/platform_channel.dart';
import '../l10n/l10n_extensions.dart';
import '../constants/alarm_day_offset.dart';
import 'day_offset_chip.dart';
import 'tappable_number_picker.dart';
import 'app_second_button.dart';
import 'word_safe_spans.dart';

class AlarmTimePicker extends StatefulWidget {
  final String shiftName; // ⭐ 제목 왼쪽에 "{근무명} - 시간 선택"으로 표시
  final Function(TimeOfDay, int dayOffset) onTimeSelected;
  final TimeOfDay? initialTime; // ⭐ 초기 시간 (수정 시 사용)
  final bool showDayOffset;
  final String? description;
  final int? alarmTypeId;
  final ValueChanged<int>? onTypeChanged;
  final int initialDayOffset; // ⭐ 초기 전날/당일/다음날 (기본값: 당일)

  const AlarmTimePicker({
    super.key,
    required this.shiftName,
    required this.onTimeSelected,
    this.initialTime,
    this.showDayOffset = true,
    this.description,
    this.alarmTypeId,
    this.onTypeChanged,
    this.initialDayOffset = kAlarmDaySame,
  });

  @override
  State<AlarmTimePicker> createState() => AlarmTimePickerState();
}

class AlarmTimePickerState extends State<AlarmTimePicker>
    with WidgetsBindingObserver {
  // Canonical state is always 0..23, independent of the visible clock format.
  bool get _isAM => _hour < 12;
  int _hour = 9;
  int _minute = 0;
  late int _dayOffset;
  late int _alarmTypeId;
  bool? _systemUse24;

  // Android's cached Flutter settings can lag behind a system setting change.
  // Read the current preference on entry/resume without changing the time value.
  Future<void> _refreshClockFormat() async {
    try {
      final value = await kAlarmChannel.invokeMethod<bool>('getUse24HourFormat');
      if (mounted && value != null && value != _systemUse24) {
        setState(() => _systemUse24 = value);
      }
    } on MissingPluginException {
      // Other platforms and widget tests continue to use MediaQuery.
    } on PlatformException {
      // Keep the platform-provided fallback if the optional query fails.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshClockFormat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshClockFormat();
    _dayOffset = widget.initialDayOffset;
    _alarmTypeId = widget.alarmTypeId ?? 1;
    // ⭐ 초기 시간이 있으면 설정
    if (widget.initialTime != null) {
      final t = widget.initialTime!;
      _minute = t.minute;
      _hour = t.hour;
    }
  }

  @override
  Widget build(BuildContext context) {
    final use24 = _systemUse24 ?? MediaQuery.alwaysUse24HourFormatOf(context);
    final displayHour = use24 ? _hour : (_hour % 12 == 0 ? 12 : _hour % 12);
    return Dialog(
      child: SingleChildScrollView(
          child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⭐ "{근무명} - 시간 선택" - 근무명이 왼쪽에 오도록
            Text(
              widget.showDayOffset
                  ? '${widget.shiftName} - ${context.l10n.commonSelectTime}'
                  : widget.shiftName,
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),

            if (widget.description != null) ...[
              Text.rich(TextSpan(children: wordSafeSpans(widget.description!,
                  TextStyle(fontSize: 12.sp, height: 1.4)))),
              SizedBox(height: 12.h),
            ],
            // ⭐ 전날/당일/다음날 - 시간 선택 바로 아래, AM/PM+시간 선택 위
            if (widget.showDayOffset)
              DayOffsetSelector(
                value: _dayOffset,
                onChanged: (value) => setState(() => _dayOffset = value),
              ),
            SizedBox(height: 16.h),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!use24)
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _hour %= 12;
                          });
                        },
                        child: Container(
                          width: 50.w,
                          height: 50.h,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _isAM ? Colors.blue : Colors.grey.shade300,
                              width: _isAM ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8.r),
                            color: Theme.of(context).colorScheme.surface,
                          ),
                          child: Center(
                            child: Text(
                              context.l10n.commonAm,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.normal,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _hour = _hour % 12 + 12;
                          });
                        },
                        child: Container(
                          width: 50.w,
                          height: 50.h,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color:
                                  !_isAM ? Colors.blue : Colors.grey.shade300,
                              width: !_isAM ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8.r),
                            color: Theme.of(context).colorScheme.surface,
                          ),
                          child: Center(
                            child: Text(
                              context.l10n.commonPm,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.normal,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (!use24) SizedBox(width: 16.w),
                TappableNumberPicker(
                  key: ValueKey('alarm-hour-${use24 ? "24" : "12"}'),
                  value: displayHour,
                  minValue: use24 ? 0 : 1,
                  maxValue: use24 ? 23 : 12,
                  zeroPad: use24,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(
                      fontSize: 16.sp,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  selectedTextStyle:
                      TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      if (use24) {
                        _hour = value;
                      } else {
                        var am = _isAM;
                        if ((displayHour == 11 && value == 12) ||
                            (displayHour == 12 && value == 11)) am = !am;
                        _hour = value % 12 + (am ? 0 : 12);
                      }
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                      bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
                Text(':',
                    style: TextStyle(
                        fontSize: 24.sp, fontWeight: FontWeight.bold)),
                TappableNumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),
                  textStyle: TextStyle(
                      fontSize: 16.sp,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  selectedTextStyle:
                      TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      _minute = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                      bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ),

            if (widget.onTypeChanged != null) ...[
              SizedBox(height: 16.h),
              AlarmTypeSelector(
                  value: _alarmTypeId,
                  onChanged: (value) {
                    setState(() => _alarmTypeId = value);
                    widget.onTypeChanged!(value);
                  }),
            ],
            SizedBox(height: 24.h),

            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8.w,
              overflowSpacing: 8.h,
              children: [
                AppSecondButton(
                  variant: AppSecondButtonVariant.neutral,
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.commonCancel),
                ),
                AppSecondButton(
                  variant: AppSecondButtonVariant.success,
                  onPressed: () async {
                    await widget.onTimeSelected(
                        TimeOfDay(hour: _hour, minute: _minute), _dayOffset);
                    if (mounted) Navigator.pop(context);
                  },
                  child: Text(context.l10n.commonOk),
                ),
              ],
            ),
          ],
        ),
      )),
    );
  }
}

class AlarmTypeSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const AlarmTypeSelector(
      {super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(children: [
        AlarmTypeButton(
            value: value,
            typeId: 1,
            emoji: '🔔',
            label: context.l10n.alarmSoundVibration,
            onChanged: onChanged),
        SizedBox(width: 8.w),
        AlarmTypeButton(
            value: value,
            typeId: 2,
            emoji: '📳',
            label: context.l10n.alarmVibration,
            onChanged: onChanged),
        SizedBox(width: 8.w),
        AlarmTypeButton(
            value: value,
            typeId: 3,
            emoji: '🔇',
            label: context.l10n.alarmSilent,
            onChanged: onChanged),
      ]);
}

class AlarmTypeButton extends StatelessWidget {
  final int value, typeId;
  final String emoji, label;
  final ValueChanged<int> onChanged;
  const AlarmTypeButton(
      {super.key,
      required this.value,
      required this.typeId,
      required this.emoji,
      required this.label,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final isSelected = value == typeId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          onChanged(typeId);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange.shade800 // 다크모드: 진한 주황 (대비율 6.74:1)
                    : Colors.orange.shade700) // 화이트모드: 진한 주황 (대비율 5.73:1)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: TextStyle(fontSize: 16.sp)),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant, // 선택 시 흰색으로 통일
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
