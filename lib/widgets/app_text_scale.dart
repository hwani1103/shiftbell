import 'package:flutter/widgets.dart';

/// App-owned UI follows fractional system sizes up to the supported maximum.
/// Keep the incoming (potentially nonlinear) scaler rather than rounding it.
const double kAppMaxTextScale = 1.3;

class AppTextScale extends StatelessWidget {
  const AppTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: kAppMaxTextScale),
      ),
      child: child,
    );
  }
}
