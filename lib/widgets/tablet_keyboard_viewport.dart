import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../constants/platform_channel.dart';

/// Use an explicit platform device category, never a wide/folded window size.
Future<bool> isTabletLayoutDevice() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await kAlarmChannel
            .invokeMethod<bool>('isTabletLayoutDevice')
            .timeout(const Duration(milliseconds: 500)) ??
        false;
  } catch (_) {
    return false;
  }
}

/// Provide the keyboard-free viewport to a modal's existing height calculation.
/// The fixed footer stays above the keyboard on phones, folds, and tablets.
class KeyboardSafeViewport extends StatelessWidget {
  const KeyboardSafeViewport({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    if (keyboard <= 0) return child;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: MediaQuery(
        data: media.copyWith(
          size:
              Size(media.size.width, math.max(0, media.size.height - keyboard)),
          viewInsets: media.viewInsets.copyWith(bottom: 0),
        ),
        child: child,
      ),
    );
  }
}
