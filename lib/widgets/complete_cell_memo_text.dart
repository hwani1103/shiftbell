import 'package:flutter/widgets.dart';

/// Shows only complete grapheme clusters that fit in a single calendar cell line.
/// No ellipsis is added, including for English and combined emoji characters.
class CompleteCellMemoText extends StatelessWidget {
  const CompleteCellMemoText(this.text,
      {super.key,
      required this.style,
      this.textAlign = TextAlign.center,
      this.textScaler,
      this.horizontalInset = 2});

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final TextScaler? textScaler;
  final double horizontalInset;

  @override
  Widget build(BuildContext context) => Padding(
      // Keep glyph ink away from the cell/card edge, even at fractional pixels.
      // Measure after padding so the last character is omitted, never clipped.
      padding: EdgeInsets.symmetric(horizontal: horizontalInset),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width = bounds.maxWidth;
          final height = bounds.maxHeight;
          final scaler = textScaler ?? MediaQuery.textScalerOf(context);
          final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);
          final clusters = text.characters.toList(growable: false);

          bool fits(int count) {
            final painter = TextPainter(
              text: TextSpan(
                  text: clusters.take(count).join(), style: resolvedStyle),
              textDirection: Directionality.of(context),
              locale: Localizations.maybeLocaleOf(context),
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            final result = !painter.didExceedMaxLines &&
                (!width.isFinite || painter.width <= width - 0.5) &&
                (!height.isFinite || painter.height <= height);
            painter.dispose();
            return result;
          }

          var low = 0;
          var high = clusters.length;
          while (low < high) {
            final middle = (low + high + 1) ~/ 2;
            if (fits(middle)) {
              low = middle;
            } else {
              high = middle - 1;
            }
          }
          return Text(clusters.take(low).join(),
              style: resolvedStyle,
              textAlign: textAlign,
              textScaler: scaler,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip);
        },
      ));
}
