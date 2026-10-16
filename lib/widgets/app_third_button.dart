import 'package:flutter/material.dart';
import 'app_ui_components.dart';

class AppThirdButton extends StatelessWidget {
  const AppThirdButton(
      {super.key,
      required this.onPressed,
      required this.child,
      this.compact = false});
  final VoidCallback? onPressed;
  final Widget child;
  final bool compact;
  @override
  Widget build(BuildContext context) => AppUiButton(
      onPressed: onPressed,
      child: child,
      compact: compact,
      action: AppUiAction.secondary);
}
