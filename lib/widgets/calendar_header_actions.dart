import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';

/// Keeps the month and actions on one row, including narrow cover screens.
class CalendarTitleActionsRow extends StatelessWidget {
  const CalendarTitleActionsRow({super.key, required this.title, required this.actions});
  final Widget title;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft, child: title)),
    const SizedBox(width: 6),
    Expanded(flex: 7, child: actions),
  ]);
}

/// A trailing group with equal button heights and width-aware labels.
class CalendarHeaderActions extends StatelessWidget {
  const CalendarHeaderActions(
      {super.key,
      required this.onToday,
      required this.onAllShifts,
      required this.onFriends,
      required this.isKorean,
      required this.editorial});
  final VoidCallback onToday;
  final VoidCallback? onAllShifts;
  final VoidCallback? onFriends;
  final bool isKorean;
  final bool editorial;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final color = editorial ? Colors.brown.shade600 : Colors.black87;
    final background = editorial ? const Color(0xFFF4EFE9) : const Color(0xFFF1F3F7);
    final border = color.withValues(alpha: editorial ? 0.20 : 0.14);
    final compact = bounds.maxWidth < 280;
    final height = bounds.hasBoundedHeight ? bounds.maxHeight.clamp(0.0, 46.0) : 46.0;
    final gap = compact ? 3.0 : 6.0;
    Widget button(String label, VoidCallback action, {Key? key}) => TextButton(
          key: key,
          style: TextButton.styleFrom(
            foregroundColor: color,
            backgroundColor: background,
            side: BorderSide(color: border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: Size(0, height),
            padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10, vertical: 3),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: TextStyle(
                fontSize: compact ? 11 : 13,
                height: 1.15,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none),
          ),
          onPressed: action,
          child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(label, textAlign: TextAlign.center, maxLines: 2)),
        );
    return Align(alignment: Alignment.centerRight, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: SizedBox(height: height, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (onAllShifts != null) ...[
        SizedBox(width: gap),
        Expanded(child: button(context.usesKoreanFeatures ? '전체 조\n근무표' : context.l10n.shiftFullSchedule, onAllShifts!)),
      ],
      if (onFriends != null && context.usesKoreanFeatures) ...[
        SizedBox(width: gap),
        Expanded(child: button('일정공유', onFriends!)),
      ],
      SizedBox(width: gap),
      Expanded(child: button(context.usesKoreanFeatures ? 'TODAY' : context.l10n.commonToday.toUpperCase(), onToday)),
    ]))));
  });
}
