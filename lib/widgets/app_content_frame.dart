import 'package:flutter/material.dart';

import '../constants/layout_limits.dart';
import 'app_text_scale.dart';

/// Uses the full window, with reading-width constraints for wide modals only.
class AppContentFrame extends StatelessWidget {
  const AppContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final theme = Theme.of(context);
    return AppTextScale(
        child: ColoredBox(
      color: Colors.white,
      child: Theme(
        data: layout.isWide
            ? theme.copyWith(
                dialogTheme: theme.dialogTheme.copyWith(
                  constraints: BoxConstraints(maxWidth: layout.dialogWidth),
                ),
                bottomSheetTheme: theme.bottomSheetTheme.copyWith(
                  constraints: BoxConstraints(maxWidth: layout.sheetWidth),
                ),
              )
            : theme,
        child: child,
      ),
    ));
  }
}
