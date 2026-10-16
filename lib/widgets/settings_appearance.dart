import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_ui_theme.dart';
import 'app_ui_theme_scope.dart';

/// The same palette, type hierarchy and surfaces as onboarding, including
/// independently pushed settings routes and their captured modal themes.
class SettingsAppearance extends StatelessWidget {
  const SettingsAppearance({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) {
    // Standalone editors can inherit an injected palette without app state.
    // App routes also follow time changes while a modal remains open.
    try {
      ProviderScope.containerOf(context, listen: false);
      return AppUiThemeScope(builder: builder);
    } on StateError {
      return Theme(
          data: AppUiTheme.withPalette(
              Theme.of(context), AppUiPalette.of(context)),
          child: Builder(builder: builder));
    }
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1,
                  indent: AppUiMetrics.gap,
                  endIndent: AppUiMetrics.gap),
            children[i],
          ],
        ]),
      );
}
