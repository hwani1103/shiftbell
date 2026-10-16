import 'package:flutter/material.dart';
import '../utils/calendar_cell_annotations.dart';

/// A duration, never a memo. Only the event theme removes spaces before fitting.
class CalendarOvertimeLabel extends StatelessWidget {
  const CalendarOvertimeLabel(
      {super.key,
      required this.minutes,
      required this.style,
      this.semanticLabel,
      this.compactSpaces = false,
      this.background,
      this.border,
      this.alignment = Alignment.center});
  final int minutes;
  final TextStyle style;
  final String? semanticLabel;
  final bool compactSpaces;
  final Color? background, border;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        key: const ValueKey('calendar-overtime'),
        padding: EdgeInsets.symmetric(horizontal: background == null ? .5 : 1),
        decoration: background == null
            ? null
            : BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(2),
                border: border == null
                    ? null
                    : Border.all(color: border!, width: .5)),
        child: LayoutBuilder(builder: (context, box) {
          final choices = calendarOvertimeLabels(minutes);
          var label = choices.first;
          if (compactSpaces) {
            for (final candidate in choices) {
              label = candidate;
              final painter = TextPainter(
                  text: TextSpan(
                      text: candidate,
                      style: DefaultTextStyle.of(context).style.merge(style)),
                  textDirection: Directionality.of(context),
                  textScaler: TextScaler.noScaling,
                  maxLines: 1)
                ..layout();
              final fits = painter.width <= box.maxWidth;
              painter.dispose();
              if (fits) break;
            }
          }
          return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: style));
        }),
      ));
}
