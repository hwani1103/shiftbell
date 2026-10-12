import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/services/backup_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  test('picker cancellation remains distinct from read failure', () async {
    messenger.setMockMethodCallHandler(kAlarmChannel, (_) async => null);
    expect(await BackupStorageService.instance.pickAndRead(), isNull);
    messenger.setMockMethodCallHandler(kAlarmChannel, (_) async => '');
    expect(await BackupStorageService.instance.pickAndRead(), '');
    messenger.setMockMethodCallHandler(kAlarmChannel, (_) async {
      throw PlatformException(code: 'read_failed');
    });
    expect(await BackupStorageService.instance.pickAndRead(), '');
  });

  test('selected content reaches backup validation unchanged', () async {
    const content = '{"schemaVersion":2}';
    messenger.setMockMethodCallHandler(kAlarmChannel, (_) async => content);
    expect(await BackupStorageService.instance.pickAndRead(), content);
  });
}
