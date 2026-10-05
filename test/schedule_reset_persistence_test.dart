import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/services/friend_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final disk = <String, Object>{};
  final nativeCalls = <String>[];
  String? writeFailure;
  bool readFailure = false;
  late Directory directory;
  late Database db;
  final service = DatabaseService.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('reset_persistence_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await service.database;
    messenger.setMockMethodCallHandler(prefsChannel, (call) async {
      if (call.method.startsWith('getAll')) {
        if (readFailure) throw PlatformException(code: 'read_failure');
        return Map<String, Object>.from(disk);
      }
      final args = call.arguments as Map;
      final key = args['key'] as String;
      if (call.method.startsWith('set')) {
        if (key == 'flutter.friend_share_state_v2' && writeFailure != null) {
          if (writeFailure == 'throw') throw PlatformException(code: 'disk_full');
          return false;
        }
        disk[key] = args['value'] as Object;
      } else if (call.method == 'remove') {
        disk.remove(key);
      }
      return true;
    });
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(prefsChannel, null);
    messenger.setMockMethodCallHandler(kAlarmChannel, null);
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });

  for (final failure in ['false', 'throw']) {
    test('Reset completes despite preference write $failure; sharing can be stopped later', () async {
      SharedPreferences.resetStatic();
      disk.clear();
      writeFailure = null;
      readFailure = false;
      firebaseReady = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('friend_share_enabled', true);
      await prefs.setStringList('all_teams_names', ['A', 'B']);
      expect((await FriendSyncService.instance.getShareState()).isActive, isTrue);
      final originalShare = disk['flutter.friend_share_state_v2'];
      await service.saveShiftSchedule(ShiftSchedule(
        isRegular: true, pattern: const ['Day', 'Off'], todayIndex: 0,
        startDate: DateTime(2026, 10, 4), shiftTypes: const ['Day', 'Off'],
      ));
      await service.insertAlarm(Alarm(time: '07:00', date: DateTime(2026, 10, 5),
          type: 'custom', alarmTypeId: 1));
      await service.insertAlarmTemplate(shiftType: 'Day', time: '07:00', alarmTypeId: 1);
      final notifier = ScheduleNotifier();
      addTearDown(notifier.dispose);
      await notifier.refresh();
      nativeCalls.clear();

      writeFailure = failure;
      expect(await notifier.resetSchedule(), isFalse);
      expect(disk['flutter.friend_share_state_v2'], originalShare);
      expect(notifier.state.value, isNull);
      expect(await db.query('shift_schedule'), isEmpty);
      expect(await db.query('alarms'), isEmpty);
      expect(await db.query('shift_alarm_templates'), isEmpty);
      expect(nativeCalls, contains('cancelNativeAlarm'));
      expect(prefs.getStringList('all_teams_names'), ['A', 'B']);

      // Reading settings can fail too; it still must not block a reset.
      readFailure = true;
      expect(await notifier.resetSchedule(), isFalse);
      readFailure = false;
      expect((await FriendSyncService.instance.getShareState()).isActive, isTrue);

      // User retries Stop Sharing after storage recovers.
      writeFailure = null;
      await FriendSyncService.instance.stopSharing();
      expect((await FriendSyncService.instance.getShareState()).intent,
          FriendShareIntent.stopPending);
      expect(await db.query('shift_schedule'), isEmpty);
      expect(await db.query('alarms'), isEmpty);
      expect(nativeCalls, contains('cancelNativeAlarm'));
    });
  }
}
