import 'package:flutter/material.dart';
import 'hearts.dart';
import 'skin.dart';

/// Campaign-wide visual roles, shared by every card rather than screen literals.
abstract final class CampaignColors {
  static const focus = Color(0xFF1674F2);
  static const heart = Color(0xFFD93858);
  static Color card(int level) {
    final (start, end, from, to) = switch (level) {
      <= 20 => (1, 20, const Color(0xFFEDF8EC), const Color(0xFF8CCBA0)),
      <= 30 => (21, 30, const Color(0xFFE4F5F1), const Color(0xFF8EC6BD)),
      <= 50 => (31, 50, const Color(0xFFFFF3D8), const Color(0xFFEAC37F)),
      <= 70 => (51, 70, const Color(0xFFE4F1FC), const Color(0xFF94B9DF)),
      < 95 => (71, 94, const Color(0xFFECE6F8), const Color(0xFFA492C6)),
      _ => (95, 100, const Color(0xFFFFD9D9), const Color(0xFF920018)),
    };
    return Color.lerp(from, to, ((level - start) / (end - start)).clamp(0, 1))!;
  }

  static Color ink(Color background) =>
      background.computeLuminance() > .179 ? Colors.black : Colors.white;
}

final class HeartMeter extends StatelessWidget {
  final LevelHearts hearts;
  final bool unlimited, reducedMotion;
  final GameSkin skin;
  final GameStrings words;
  const HeartMeter({
    super.key,
    required this.hearts,
    required this.unlimited,
    required this.reducedMotion,
    required this.skin,
    required this.words,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: unlimited
        ? words.testMode
        : words.pick('하트 ${hearts.available}개', '${hearts.available} hearts'),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < LevelHearts.capacity; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('heart-$i'),
              tween: Tween(
                end: unlimited || i < hearts.available
                    ? 1
                    : i == hearts.available
                    ? hearts.fraction
                    : 0,
              ),
              duration: reducedMotion
                  ? Duration.zero
                  : hearts.recovering && i == hearts.available
                  ? GameMetrics.heartFillTransition
                  : GameMetrics.transition,
              builder: (context, fill, _) => SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 22,
                      color: CampaignColors.heart.withValues(alpha: .18),
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: fill,
                            child: const Icon(
                              Icons.favorite_rounded,
                              size: 22,
                              color: CampaignColors.heart,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
