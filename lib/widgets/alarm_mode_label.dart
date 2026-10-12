import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';

/// Keep translated alarm modes balanced across the three equal-width cards.
class AlarmModeLabel extends StatelessWidget {
  const AlarmModeLabel(this.label, {super.key, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (context.usesKoreanFeatures) {
      return Text(label, style: style, textAlign: TextAlign.center);
    }
    final resolved =
        DefaultTextStyle.of(context).style.merge(style).copyWith(height: 1.35);
    // Break at the meaning boundary; never leave '+' alone on another line.
    final balanced = label.replaceFirst(RegExp(r'\s*\+\s*'), ' +\n');
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: scaler.scale(resolved.fontSize ?? 14) * 2.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(balanced,
                style: resolved,
                textAlign: TextAlign.center,
                softWrap: false,
                maxLines: 2),
          ),
        ),
      ),
    );
  }
}
