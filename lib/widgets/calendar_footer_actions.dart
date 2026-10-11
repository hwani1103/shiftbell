import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';

/// Separate, full-width tap regions for the calendar's two summaries.
class CalendarFooterActions extends StatelessWidget {
  const CalendarFooterActions(
      {super.key,
      required this.monthly,
      required this.weekly,
      required this.onMonthly,
      required this.onWeekly,
      this.minimumHeight = 48});
  final Widget monthly, weekly;
  final VoidCallback onMonthly, onWeekly;
  final double minimumHeight;

  @override
  Widget build(BuildContext context) {
    if (!context.usesKoreanFeatures) {
      Widget singleLine(Widget child, Alignment alignment) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: DefaultTextStyle.merge(
              maxLines: 1, softWrap: false, child: child));
      return Table(
        columnWidths: const {
          0: _ShrinkableIntrinsicColumnWidth(),
          1: FixedColumnWidth(16),
          2: _ShrinkableIntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            _action('calendar-monthly-summary', Alignment.centerLeft,
                singleLine(monthly, Alignment.centerLeft), onMonthly),
            const SizedBox(width: 16),
            _action('calendar-weekly-summary', Alignment.centerRight,
                singleLine(weekly, Alignment.centerRight), onWeekly),
          ])
        ],
      );
    }
    return Row(children: [
      Expanded(
          child: _action('calendar-monthly-summary', Alignment.centerLeft,
              monthly, onMonthly)),
      const SizedBox(width: 16),
      Expanded(
          child: _action('calendar-weekly-summary', Alignment.centerRight,
              weekly, onWeekly)),
    ]);
  }

  Widget _action(
          String key, Alignment alignment, Widget label, VoidCallback onTap) =>
      Semantics(
          button: true,
          child: GestureDetector(
            key: ValueKey(key),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumHeight),
                child: Align(alignment: alignment, child: label)),
          ));
}

// Text must keep its natural width preference while allowing the fitted label
// to shrink when the two translated actions exceed the available row width.
class _ShrinkableIntrinsicColumnWidth extends IntrinsicColumnWidth {
  const _ShrinkableIntrinsicColumnWidth() : super(flex: 1);
  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      0;
}
