import 'package:flutter/material.dart';
import '../constants/layout_limits.dart';
import '../theme/app_ui_theme.dart';
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
  Widget build(BuildContext context) => SettingsAppearance(builder: (context) {
        final theme = Theme.of(context);
        final width = AppLayout.of(context).dialogWidth;
        // AlertDialog uses intrinsic/dry layout, which cannot measure the
        // responsive shift labels inside Wrap. Give the dialog a real bounded
        // width and lay out its scrollable content directly instead.
        return Dialog(
          constraints: BoxConstraints(maxWidth: width),
          insetPadding: const EdgeInsets.all(AppUiMetrics.dialogInset),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppUiMetrics.dialogRadius)),
          child: SizedBox(
            width: width,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppUiMetrics.dialogContentInset,
                            AppUiMetrics.dialogContentInset,
                            AppUiMetrics.dialogContentInset,
                            0),
                        child: Semantics(
                          namesRoute: true,
                          container: true,
                          child: DefaultTextStyle(
                            style: theme.dialogTheme.titleTextStyle ??
                                theme.textTheme.headlineSmall!,
                            child: title,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppUiMetrics.dialogContentInset,
                            AppUiMetrics.dialogContentGap,
                            AppUiMetrics.dialogContentInset,
                            AppUiMetrics.dialogContentInset),
                        child: DefaultTextStyle(
                          style: theme.dialogTheme.contentTextStyle ??
                              theme.textTheme.bodyMedium!,
                          child: content,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppUiMetrics.dialogContentInset,
                    0,
                    AppUiMetrics.dialogContentInset,
                    AppUiMetrics.dialogContentInset),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: AppUiMetrics.dialogActionGap,
                  overflowSpacing: AppUiMetrics.dialogActionGap,
                  children: actions,
                ),
              ),
            ]),
          ),
        );
      });
}
