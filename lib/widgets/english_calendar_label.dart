import 'package:flutter/widgets.dart';

/// Keep the complete shift name on one line, shrinking to the cell's width.
/// Shared by English badges and wide-calendar badges in either language.
class EnglishCalendarLabel extends StatelessWidget {
  const EnglishCalendarLabel(
    this.text, {
    super.key,
    required this.style,
    required this.textScaler,
    this.textKey,
  });
  final String text;
  final TextStyle style;
  final TextScaler textScaler;
  final Key? textKey;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final resolved = DefaultTextStyle.of(context).style.merge(style);
        // A badge may reserve the original font's line height. Center the
        // smaller fitted line within it instead of painting at its top edge.
        return Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(
          text,
          key: textKey,
          semanticsLabel: text,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          textScaler: textScaler,
          style: resolved.copyWith(
              leadingDistribution: TextLeadingDistribution.even),
          )),
        );
      });
}
