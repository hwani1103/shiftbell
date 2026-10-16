import 'package:flutter/material.dart';
import '../constants/layout_limits.dart';
import 'adaptive_layout.dart';
import 'settings_appearance.dart';
import 'app_ui_components.dart';

/// Only the main settings menu flattens groups on roomy inner displays.
/// Phone/closed/short windows retain the original grouped sections.
class SettingsMenuList extends StatelessWidget {
  const SettingsMenuList(
      {super.key,
      required this.children,
      this.padding,
      this.fullWidthFirst = true});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool fullWidthFirst;
  static const _minColumnWidth = 320.0;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final layout = AppLayout.of(context);
        final insets =
            (padding ?? EdgeInsets.zero).resolve(Directionality.of(context));
        final twoColumns = layout.window.shortestSide > kAppMaxContentWidth &&
            bounds.maxWidth - insets.horizontal >= _minColumnWidth * 2 + 16;
        final sections = twoColumns
            ? <Widget>[
                for (final section in children)
                  if (section is SettingsGroup)
                    for (final tile in section.children)
                      SettingsGroup(children: [tile])
                  else
                    section,
              ]
            : children;
        if (twoColumns) {
          final visible = sections
              .where(
                  (w) => !(w is SizedBox && w.child == null) && w is! Divider)
              .toList();
          final rows = <Widget>[];
          for (var i = 0; i < visible.length;) {
            final first = visible[i];
            if ((fullWidthFirst && i == 0) || first is Align || first is Text) {
              rows.add(first);
              i++;
              continue;
            }
            final hasSecond = i + 1 < visible.length &&
                visible[i + 1] is! Align &&
                visible[i + 1] is! Text;
            rows.add(AppUiEqualHeightRow(
              children: [
                first,
                hasSecond ? visible[i + 1] : const SizedBox.shrink()
              ],
            ));
            i += hasSecond ? 2 : 1;
          }
          return ListView(padding: padding, children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              rows[i],
            ],
          ]);
        }
        return AdaptiveSectionList(
          fullWidthFirst: fullWidthFirst,
          minColumnWidth: _minColumnWidth,
          padding: padding,
          children: sections,
        );
      });
}
