import 'package:flutter/material.dart';
import 'app_ui_components.dart';

enum AppSecondButtonVariant { danger, success, neutral, primary }

/// Existing callers retain their action and sizing contracts; success is the
/// primary save role, rather than a separate green design system.
class AppSecondButton extends StatelessWidget {
  const AppSecondButton(
      {super.key,
      required this.onPressed,
      required this.child,
      this.variant = AppSecondButtonVariant.neutral,
      this.compact = false,
      this.padding,
      this.fontSize});
  final VoidCallback? onPressed;
  final Widget child;
  final AppSecondButtonVariant variant;
  final bool compact;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  @override
  Widget build(BuildContext context) => AppUiButton(
      onPressed: onPressed,
      child: child,
      compact: compact,
      padding: padding,
      fontSize: fontSize,
      action: switch (variant) {
        AppSecondButtonVariant.danger => AppUiAction.danger,
        AppSecondButtonVariant.neutral => AppUiAction.secondary,
        _ => AppUiAction.primary,
      });
}
