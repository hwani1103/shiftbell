import 'package:flutter/material.dart';

/// Shared visual rules for settings and schedule editors. Widths, text scaling
/// and adaptive placement are still owned by each screen's existing layout.
class SettingsAppearance extends StatelessWidget {
  const SettingsAppearance({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.outline.withValues(alpha: .58)),
    );
    return Theme(
      data: base.copyWith(
        cardTheme: base.cardTheme.copyWith(
          color: base.scaffoldBackgroundColor,
          elevation: 0,
          shape: shape,
        ),
        dialogTheme: base.dialogTheme.copyWith(
          backgroundColor: base.scaffoldBackgroundColor,
          shape: shape,
          titleTextStyle: base.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          contentTextStyle: base.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.5,
            color: colors.onSurface,
          ),
        ),
        bottomSheetTheme: base.bottomSheetTheme.copyWith(
          backgroundColor: base.scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          fillColor: colors.onSurface.withValues(alpha: .035),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        listTileTheme: base.listTileTheme.copyWith(
          tileColor: base.scaffoldBackgroundColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          titleTextStyle: base.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            height: 1.45,
            color: colors.onSurfaceVariant,
          ),
          iconColor: colors.primary,
        ),
        dividerTheme: base.dividerTheme.copyWith(
          color: colors.outline.withValues(alpha: .6),
          thickness: 1,
        ),
      ),
      child: Builder(builder: builder),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: .58)),
              children[i],
            ],
          ],
        ),
      );
}
