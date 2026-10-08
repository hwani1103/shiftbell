import 'package:flutter/material.dart';

/// Scales only the icon, retaining the navigation bar's adaptive geometry.
class NavIconEmphasis extends StatefulWidget {
  const NavIconEmphasis(
      {super.key, required this.icon, required this.sequence});
  final IconData icon;
  final int sequence;
  @override
  State<NavIconEmphasis> createState() => _NavIconEmphasisState();
}

class _NavIconEmphasisState extends State<NavIconEmphasis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));
  Animation<double> get _scale => TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45),
    TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 40),
  ]).animate(_controller);
  @override
  void didUpdateWidget(covariant NavIconEmphasis oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = const Duration(milliseconds: 1000);
    if (widget.sequence > 0 &&
        widget.sequence != oldWidget.sequence &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: Icon(widget.icon));
}
