import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Uses the sheet's width, not the full device width (including unfolded screens).
class CalendarAlarmCardStrip extends StatelessWidget {
  const CalendarAlarmCardStrip({super.key, required this.cards});

  final List<CalendarAlarmCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, bounds) {
          final viewport = bounds.hasBoundedWidth ? bounds.maxWidth : 360.0;
          final textScale = MediaQuery.textScalerOf(context).scale(18) / 18;
          final width = (viewport * .42).clamp(132.0, 168.0) *
              math.max(1.0, textScale.clamp(1.0, 1.4));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  SizedBox(width: width, child: cards[i]),
                ],
              ],
            ),
          );
        },
      );
}

/// Same visual hierarchy for editable fixed alarms and read-only snoozes.
class CalendarAlarmCard extends StatelessWidget {
  const CalendarAlarmCard({
    super.key,
    required this.time,
    required this.label,
    required this.leading,
    this.detail,
    this.onTap,
  });

  final String time;
  final String label;
  final Widget leading;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = onTap == null ? colors.onSurfaceVariant : colors.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconTheme(
                  data: IconThemeData(size: 16, color: accent),
                  child: leading,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(time,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.onSurface,
                      )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant)),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 13, color: accent),
              ],
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!,
                style: TextStyle(
                    fontSize: 11, height: 1.3, color: colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      label: [time, label, if (detail != null) detail!].join(', '),
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Color.alphaBlend(
            accent.withValues(alpha: .035), colors.surfaceContainerLow),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                customBorder: shape,
                excludeFromSemantics: true,
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}
