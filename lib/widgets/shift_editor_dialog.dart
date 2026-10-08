import 'package:flutter/material.dart';
import '../constants/layout_limits.dart';
import 'settings_appearance.dart';

/// Shared shell for shift editors. Content and actions remain reachable with
/// a keyboard, a short cover screen, or large accessibility text.
class ShiftEditorDialog extends StatelessWidget {
  const ShiftEditorDialog(
      {super.key,
      required this.title,
      required this.content,
      required this.actions});
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SettingsAppearance(
      builder: (context) => AlertDialog(
            constraints:
                BoxConstraints(maxWidth: AppLayout.of(context).dialogWidth),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            scrollable: true,
            title: title,
            content: SizedBox(
                width: AppLayout.of(context).dialogWidth, child: content),
            actions: actions,
          ));
}
