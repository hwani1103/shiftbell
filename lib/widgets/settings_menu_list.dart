import 'package:flutter/material.dart';
import '../constants/layout_limits.dart';
import 'adaptive_layout.dart';
import 'settings_appearance.dart';

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
        return AdaptiveSectionList(
          fullWidthFirst: fullWidthFirst,
          minColumnWidth: _minColumnWidth,
          padding: padding,
          children: sections,
        );
      });
}
