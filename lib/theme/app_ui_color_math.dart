import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared contrast policy for generated runtime colors (opaque sRGB).
abstract final class AppUiColorMath {
  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + .05) / (math.min(x, y) + .05);
  }

  static Color ink(Color background) =>
      contrast(Colors.white, background) > contrast(Colors.black, background)
          ? Colors.white
          : Colors.black;

  static Color readable(Color candidate, Iterable<Color> backgrounds,
      {double minimum = 4.5}) {
    double score(Color color) => backgrounds
        .map((background) => contrast(color, background))
        .reduce(math.min);
    if (score(candidate) >= minimum) return candidate;
    final target =
        score(Colors.white) > score(Colors.black) ? Colors.white : Colors.black;
    // Search from the intended hue toward the readable endpoint, retaining as
    // much of the intended color as possible, including quantization at 8 bits.
    for (var step = 1; step <= 100; step++) {
      final color = Color.lerp(candidate, target, step / 100)!;
      if (score(color) >= minimum) return color;
    }
    return target;
  }
}
