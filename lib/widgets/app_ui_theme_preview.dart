import '../widgets/app_ui_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_ui_theme_preview_provider.dart';
import '../theme/app_ui_theme.dart';
import '../theme/app_ui_time_palettes.dart';
import '../l10n/l10n_extensions.dart';
import 'app_ui_components.dart';

class AppUiThemePreview extends ConsumerWidget {
  const AppUiThemePreview({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(appUiThemePreviewProvider).valueOrNull;
    final selected = saved;
    const choices = AppUiTimeTheme.values;
    String label(AppUiTimeTheme theme) => switch (theme) {
          AppUiTimeTheme.dawn => context.l10n.uiThemeDawn,
          AppUiTimeTheme.morning => context.l10n.uiThemeMorning,
          AppUiTimeTheme.daytime => context.l10n.uiThemeDaytime,
          AppUiTimeTheme.evening => context.l10n.uiThemeEvening,
          AppUiTimeTheme.night => context.l10n.uiThemeOriginalDark,
          AppUiTimeTheme.originalWhite => context.l10n.uiThemeOriginalWhite,
        };
    return AppUiCard(
        key: const ValueKey('app-ui-theme-preview'),
        padding: const EdgeInsets.all(AppUiMetrics.compactCardPadding),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: AppUiText(context.l10n.uiThemePreviewTitle,
                    role: AppTextRole.section)),
            AppUiButton(
                label: context.l10n.uiThemeAutomatic,
                compact: true,
                action: selected == null
                    ? AppUiAction.primary
                    : AppUiAction.secondary,
                onPressed: () async {
                  try {
                    await ref
                        .read(appUiThemePreviewProvider.notifier)
                        .select(null);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(AppUiSnackBar(
                          content: Text(context.l10n.uiThemeSaveFailed)));
                    }
                  }
                }),
          ]),
          const SizedBox(height: AppUiMetrics.previewGap),
          Row(children: [
            for (final theme in choices) ...[
              if (theme.index > 0)
                const SizedBox(width: AppUiMetrics.previewGap),
              Expanded(
                  child: Semantics(
                      button: true,
                      selected: selected == theme,
                      label: label(theme),
                      child: Material(
                          color: theme.palette.soft,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppUiMetrics.controlRadius),
                              side: BorderSide(
                                  color: selected == theme
                                      ? theme.palette.primary
                                      : theme.palette.border,
                                  width: selected == theme ? 2 : 1)),
                          child: InkWell(
                              key: ValueKey('app-ui-theme-${theme.name}'),
                              borderRadius: BorderRadius.circular(
                                  AppUiMetrics.controlRadius),
                              onTap: () async {
                                try {
                                  await ref
                                      .read(appUiThemePreviewProvider.notifier)
                                      .select(theme);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        AppUiSnackBar(
                                            content: Text(context
                                                .l10n.uiThemeSaveFailed)));
                                  }
                                }
                              },
                              child: SizedBox(
                                  height: AppUiMetrics.previewHeight,
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                            width: AppUiMetrics.previewDotSize,
                                            height: AppUiMetrics.previewDotSize,
                                            decoration: BoxDecoration(
                                                color: theme.palette.background,
                                                border: Border.all(
                                                    color:
                                                        theme.palette.border),
                                                shape: BoxShape.circle)),
                                        const SizedBox(
                                            height: AppUiMetrics.previewGap),
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal:
                                                    AppUiMetrics.previewGap),
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(label(theme),
                                                    textScaler:
                                                        TextScaler.noScaling,
                                                    style: AppTypography.style(
                                                            context,
                                                            AppTextRole
                                                                .supporting)
                                                        .copyWith(
                                                            color: theme.palette
                                                                .text)))),
                                      ]))))))
            ]
          ]),
        ]));
  }
}
