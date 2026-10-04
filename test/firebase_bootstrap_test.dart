import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/firebase_options.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';

class _CoreHost extends MockFirebaseApp {
  int calls = 0;

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    calls++;
    final options = DefaultFirebaseOptions.android;
    return [
      CoreInitializeResponse(
        name: '[DEFAULT]',
        options: CoreFirebaseOptions(
          apiKey: options.apiKey,
          appId: options.appId,
          messagingSenderId: options.messagingSenderId,
          projectId: options.projectId,
          storageBucket: options.storageBucket,
        ),
        pluginConstants: {},
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing Analytics channel must not disable initialized Firestore', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final core = _CoreHost();
    TestFirebaseCoreHostApi.setUp(core);
    addTearDown(() => TestFirebaseCoreHostApi.setUp(null));
    firebaseReady = false;
    analytics = null;

    // No Analytics mock: reproduce the production web's missing plugin channel.
    await initFirebase();

    expect(firebaseReady, isTrue);
    expect(analytics, isNull);
    expect(core.calls, 1);
  });
}
