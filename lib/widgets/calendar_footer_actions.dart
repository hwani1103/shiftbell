import 'package:flutter/material.dart';

/// Separate, full-width tap regions for the calendar's two summaries.
class CalendarFooterActions extends StatelessWidget {
  const CalendarFooterActions(
      {super.key,
      required this.monthly,
      required this.weekly,
      required this.onMonthly,
      required this.onWeekly});
  final Widget monthly, weekly;
  final VoidCallback onMonthly, onWeekly;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: _action('calendar-monthly-summary', Alignment.centerLeft,
                monthly, onMonthly)),
        const SizedBox(width: 16),
        Expanded(
            child: _action('calendar-weekly-summary', Alignment.centerRight,
                weekly, onWeekly)),
      ]);

  Widget _action(
          String key, Alignment alignment, Widget label, VoidCallback onTap) =>
      Semantics(
          button: true,
          child: GestureDetector(
            key: ValueKey(key),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(alignment: alignment, child: label)),
          ));
}
