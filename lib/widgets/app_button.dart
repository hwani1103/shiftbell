import 'package:flutter/material.dart';
import 'app_ui_components.dart';

/// Compatibility entry point; all primary actions share the onboarding control.
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      AppUiButton(onPressed: onPressed, child: child);
}
