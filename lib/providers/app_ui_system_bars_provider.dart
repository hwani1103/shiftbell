import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/platform_channel.dart';

/// Read-only UI capability, cached once per app container. Unknown Android
/// versions keep a dark navigation bar instead of white icons on a light bar.
final appUiDarkNavigationIconsProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final sdk = await kAlarmChannel.invokeMethod<int>('getPlatformSdkInt');
    return sdk != null && sdk >= 26;
  } catch (_) {
    return false;
  }
});
