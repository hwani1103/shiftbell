import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:shiftbell/services/update_service.dart';

class _Launcher extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;
  String? opened;
  bool result = true;
  bool fail = false;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened = url;
    expect(options.mode, PreferredLaunchMode.externalApplication);
    if (fail) throw PlatformException(code: 'unavailable');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.ffuf.in_app_update/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalLauncher = UrlLauncherPlatform.instance;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    UrlLauncherPlatform.instance = originalLauncher;
  });
  for (final entry in {
    0: ManualUpdateStatus.unavailable,
    1: ManualUpdateStatus.upToDate,
    2: ManualUpdateStatus.available,
    3: ManualUpdateStatus.available
  }.entries) {
    test('manual check interprets Play availability ${entry.key}', () async {
      SharedPreferences.setMockInitialValues({
        'notified_update_version': 9999,
        'play_update_last_checked_at': DateTime.now().millisecondsSinceEpoch,
      });
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'checkForUpdate');
        return {
          'updateAvailability': entry.key,
          'immediateAllowed': false,
          'flexibleAllowed': false,
          'availableVersionCode': 29,
          'installStatus': 0,
          'packageName': 'com.hwani1103.shiftbell',
          'updatePriority': 0
        };
      });
      expect(await UpdateService.checkManually(), entry.value);
      expect(calls, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notified_update_version'), 9999);
    }, skip: appFlavor == 'dev');
  }
  test('offline check remains unknown rather than latest', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'offline'));
    expect(await UpdateService.checkManually(), ManualUpdateStatus.unavailable);
  });
  testWidgets('hung Play request times out as unavailable', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      await Future<void>.delayed(const Duration(minutes: 1));
      throw PlatformException(code: 'offline');
    });
    final check = UpdateService.checkManually();
    await tester.pump(const Duration(seconds: 16));
    expect(await check, ManualUpdateStatus.unavailable);
    await tester.pump(const Duration(minutes: 1));
  }, skip: appFlavor == 'dev');
  test('dev cannot compare its package against the Play product', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    expect(await UpdateService.checkManually(), ManualUpdateStatus.unavailable);
    expect(calls, 0);
  }, skip: appFlavor != 'dev');
  test('store destination always targets product and reports launch failure',
      () async {
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    expect(await UpdateService.openPlayStore(), true);
    expect(Uri.parse(launcher.opened!).queryParameters['id'],
        'com.hwani1103.shiftbell');
    launcher.result = false;
    expect(await UpdateService.openPlayStore(), false);
    launcher.fail = true;
    expect(await UpdateService.openPlayStore(), false);
  });
}
