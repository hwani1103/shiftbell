import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Exactly two geometry presets for both languages; only the choice uses text
/// measurement. Font/accessibility scaling enlarges both presets equally.
class ShiftCellMetrics {
  const ShiftCellMetrics(this.width, this.height, this.large);
  final double width, height;
  final bool large;
  factory ShiftCellMetrics.forNames(
      Iterable<String> names, TextStyle style, TextScaler scaler,
      {double minWidth = 40, double minHeight = 36}) {
    double measure(String value) {
      final p = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler)
        ..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    final smallWidth = math.max(minWidth, measure('가나') + 14);
    final large = names.any((name) => RegExp(r'^[가-힣]+$').hasMatch(name)
        ? name.characters.length > 2
        : measure(name) > smallWidth - 14);
    final lineHeight =
        scaler.scale(style.fontSize ?? 13) * (style.height ?? 1.15);
    return ShiftCellMetrics(smallWidth + (large ? 8 : 0),
        math.max(minHeight, lineHeight * (large ? 2 : 1) + 18), large);
  }
}

/// Width-based wrapping shared by grid chips. Preserve every grapheme and
/// prefer word boundaries in Latin names; Hangul uses balanced two-line rows.
String wrapShiftLabel(
    String name, double width, TextStyle style, TextScaler scaler) {
  double measure(String value) {
    final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout();
    final result = painter.width;
    painter.dispose();
    return result;
  }

  final chars = name.characters.toList();
  if (chars.length < 2) return name;
  if (RegExp(r'^[가-힣]+$').hasMatch(name)) {
    if (chars.length <= 2) return name;
    final split = (chars.length / 2).ceil();
    return '${chars.take(split).join()}\n${chars.skip(split).join()}';
  }
  if (measure(name) <= width) return name;
  int? best;
  var score = double.infinity;
  for (var i = 1; i < chars.length; i++) {
    // Keep Latin words intact, including short names such as Folga and Frei.
    // The enclosing FittedBox handles a word wider than the cell.
    final wordBreak = chars[i - 1] == ' ' || chars[i] == ' ';
    if (!wordBreak) continue;
    final left = chars.take(i).join().trimRight();
    final right = chars.skip(i).join().trimLeft();
    if (left.isEmpty || right.isEmpty) continue;
    final maxWidth = math.max(measure(left), measure(right));
    final candidate = maxWidth;
    if (candidate < score) {
      score = candidate;
      best = i;
    }
  }
  if (best == null) return name;
  return '${chars.take(best).join().trimRight()}\n${chars.skip(best).join().trimLeft()}';
}

class ShiftLabel extends StatelessWidget {
  const ShiftLabel({super.key, required this.label, required this.style});
  final String label;
  final TextStyle style;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final text = wrapShiftLabel(
            label, bounds.maxWidth, style, MediaQuery.textScalerOf(context));
        return Semantics(
            label: label,
            excludeSemantics: true,
            child: Center(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(text,
                      textAlign: TextAlign.center, style: style, maxLines: 2)),
            ));
      });
}
