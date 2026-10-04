import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pending DB open is shared, failure reaches both callers, next attempt recovers', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('startup_retry_');
    final gate = Completer<void>();
    var paths = 0;
    DatabaseService.debugIsAndroidOverride = true;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method != 'getDeviceProtectedStoragePath') return null;
      paths++;
      if (paths == 1) {
        await gate.future;
        throw PlatformException(code: 'DE_STORAGE_NOT_READY');
      }
      return '${dir.path}/shiftbell.db';
    });
    Database? opened;
    try {
      final first = DatabaseService.instance.database;
      final second = DatabaseService.instance.database;
      expect(identical(first, second), isTrue);
      final firstError = expectLater(first, throwsA(isA<PlatformException>()));
      final secondError = expectLater(second, throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      expect(paths, 1);
      gate.complete();
      await Future.wait([firstError, secondError]);
      await Future<void>.delayed(Duration.zero);
      opened = await DatabaseService.instance.database;
      expect(paths, 2);
      expect((await opened.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
      expect(await opened.query('alarm_types'), hasLength(3));
      expect(identical(await DatabaseService.instance.database, opened), isTrue);
    } finally {
      await opened?.close();
      messenger.setMockMethodCallHandler(kAlarmChannel, null);
      DatabaseService.debugIsAndroidOverride = null;
      await dir.delete(recursive: true);
    }
  });
}
