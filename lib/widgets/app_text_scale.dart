import 'package:flutter/widgets.dart';

/// App typography follows the available window, independent of OS font size.
const double kAppMaxTextScale = 1.0;

class AppTextScale extends StatelessWidget {
  const AppTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.noScaling,
      ),
      child: child,
    );
  }
}
