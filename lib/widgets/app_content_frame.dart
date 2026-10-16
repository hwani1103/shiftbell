import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../theme/app_ui_system_bars.dart';

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
    final navigationInset =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? MediaQuery.viewPaddingOf(context).bottom
            : 0.0;
    return AppTextScale(
        child: ColoredBox(
      color: theme.scaffoldBackgroundColor,
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
        child: Stack(fit: StackFit.expand, children: [
          child,
          if (navigationInset > 0)
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: navigationInset,
                child: ExcludeSemantics(
                    child: IgnorePointer(
                        child: AnnotatedRegion<SystemUiOverlayStyle>(
                            value: AppUiSystemBars.withBlackNavigation(
                                const SystemUiOverlayStyle()),
                            child: const ColoredBox(
                                key: ValueKey('system-navigation-background'),
                                color: AppUiSystemBars
                                    .legacyNavigationBackground))))),
        ]),
      ),
    ));
  }
}
