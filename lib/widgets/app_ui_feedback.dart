import 'package:flutter/material.dart';
import '../theme/app_ui_theme.dart';

/// One visual contract for short feedback. Callers retain timing and actions.
class AppUiSnackBar extends SnackBar {
  const AppUiSnackBar(
      {super.key,
      required super.content,
      super.duration,
      super.action,
      super.onVisible,
      super.dismissDirection,
      super.backgroundColor,
      super.behavior})
      : super(
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                    Radius.circular(AppUiMetrics.controlRadius))));
}

/// Reused in pages, bounded controls and blocking routes without changing
/// their ownership, cancellation or back-button contracts.
class AppUiLoading extends StatelessWidget {
  const AppUiLoading(
      {super.key,
      this.value,
      this.color,
      this.valueColor,
      this.strokeWidth = 2,
      this.backgroundColor,
      this.semanticsLabel});
  final double? value;
  final Color? color, backgroundColor;
  final Animation<Color?>? valueColor;
  final double strokeWidth;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => CircularProgressIndicator(
        value: value,
        color: color ?? AppUiPalette.of(context).primary,
        valueColor: valueColor,
        strokeWidth: strokeWidth,
        backgroundColor: backgroundColor,
        semanticsLabel: semanticsLabel,
      );
}

abstract final class AppUiIcons {
  static const delete = Icons.delete_outline_rounded;
}

class AppUiInlineNotice extends StatelessWidget {
  const AppUiInlineNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    final p = AppUiPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppUiMetrics.compactCardPadding),
      decoration: BoxDecoration(
          color: p.soft,
          borderRadius: BorderRadius.circular(AppUiMetrics.controlRadius),
          border: Border.all(color: p.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 18, color: p.secondaryText),
        const SizedBox(width: AppUiMetrics.dialogActionGap),
        Expanded(
            child: Text(message,
                textScaler: TextScaler.noScaling,
                style: AppTypography.style(context, AppTextRole.supporting,
                    tone: AppTextTone.secondary))),
      ]),
    );
  }
}
