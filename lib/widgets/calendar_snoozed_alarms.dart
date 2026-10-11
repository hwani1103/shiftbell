import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/l10n_extensions.dart';
import '../models/alarm.dart';
import '../utils/alarm_clock_label.dart';
import 'calendar_alarm_cards.dart';

/// Read-only reservations, separate from the editable fixed-alarm cards.
/// The caller supplies the live alarm list; no scheduling or deletion occurs here.
class CalendarSnoozedAlarms extends StatelessWidget {
  const CalendarSnoozedAlarms({
    super.key,
    required this.day,
    required this.alarms,
  });

  final DateTime day;
  final List<Alarm> alarms;

  DateTime _localDate(Alarm alarm) {
    final date = alarm.date!;
    return date.isUtc ? date.toLocal() : date;
  }

  @override
  Widget build(BuildContext context) {
    final snoozed = alarms.where((alarm) {
      if (alarm.type != 'snoozed' || alarm.date == null) return false;
      final date = _localDate(alarm);
      // The original shift day/slot may differ, especially across midnight.
      return date.year == day.year &&
          date.month == day.month &&
          date.day == day.day;
    }).toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
    if (snoozed.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final label = context.l10n.calendarSnoozedAlarmLabel;
    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14.sp,
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),
          CalendarAlarmCardStrip(
            cards: [
              for (final alarm in snoozed) _card(context, alarm, label),
            ],
          ),
        ],
      ),
    );
  }

  CalendarAlarmCard _card(BuildContext context, Alarm alarm, String label) {
    final date = _localDate(alarm);
    final time = '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    return CalendarAlarmCard(
      key: ValueKey('calendar-snoozed-${alarm.id}'),
      time: time,
      label: label,
      leading: const Icon(Icons.snooze_rounded),
      detail: alarmClockLabel(context, date),
    );
  }
}
