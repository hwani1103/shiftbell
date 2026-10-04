import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/date_schedule.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/providers/date_schedule_provider.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/providers/overtime_provider.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('local_remaining_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await DatabaseService.instance.database;
  });
  tearDownAll(() async {
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    await dir.delete(recursive: true);
  });
  test('OT concurrent increments, year boundary totals and zero-cache eviction', () async {
    final notifier = OvertimeNotifier();
    addTearDown(notifier.dispose);
    await Future.wait(List.generate(10, (_) => notifier.adjust('2030-12-31', 30)));
    await notifier.adjust('2031-01-01', 60);
    await notifier.loadForRange(DateTime(2030, 12, 31), DateTime(2031, 1, 1));
    expect(notifier.getMonthTotal(2030, 12), 300);
    expect(notifier.getMonthTotal(2031, 1), 60);
    expect(notifier.getRangeTotal(DateTime(2030, 12, 31), DateTime(2031, 1, 1)), 360);
    // Simulates a change outside this notifier followed by returning to the month.
    await DatabaseService.instance.adjustOvertime('2030-12-31', -600);
    await notifier.loadForRange(DateTime(2030, 12, 31), DateTime(2031, 1, 1));
    expect(notifier.getForDate('2030-12-31'), 0);
    expect(notifier.getRangeEntries(DateTime(2030, 12, 31), DateTime(2031, 1, 1)).map((e) => e.key), ['2031-01-01']);
    expect(await db.query('date_overtime', where: 'date = ?', whereArgs: ['2030-12-31']), isEmpty);
  });
  test('OBS team preference commit before schedule commit leaves a persistent mismatch', () async {
    // Characterizes the exact interruption boundary in SettingsTab._applyScheduleChange.
    // The host does not kill Android; it omits the second store write after the first succeeds.
    final service = DatabaseService.instance;
    await service.saveShiftSchedule(ShiftSchedule(isRegular: true,
      shiftTypes: ['Day', 'Night'], pattern: ['Day', 'Night'],
      todayIndex: 0, startDate: DateTime(2024, 1, 1)));
    SharedPreferences.setMockInitialValues({
      'all_teams_names': ['A', 'B'],
      'all_teams_offsets': jsonEncode({'A': 0, 'B': 1}),
      'all_teams_my_team': 'A',
    });
    final prefs = await SharedPreferences.getInstance();
    await TeamScheduleConfig.applySelection(prefs, 'B');
    await prefs.reload();
    final config = TeamScheduleConfig.read(prefs)!;
    final persisted = await service.getShiftSchedule();
    expect(config.myTeam, 'B');
    expect(config.indexOn('B', DateTime(2024, 1, 1), 2), 1);
    expect(persisted!.todayIndex, 0,
      reason: 'Observation of an unresolved crash boundary, not a consistency PASS');
  });
  test('moving a schedule between cached dates removes the old card and adds the new card', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kAlarmChannel, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));
    final notifier = DateScheduleNotifier();
    addTearDown(notifier.dispose);
    const oldDate = '2030-12-31';
    const newDate = '2031-01-01';
    await notifier.loadForDate(newDate);
    final created = await notifier.create(const DateSchedule(
      date: oldDate, content: 'move audit', startMinutes: 600, durationMinutes: 30,
      createdAt: '2026-10-03T00:00:00',
    ));
    await notifier.update(created.saved.copyWith(date: newDate, startMinutes: 660));
    expect(notifier.state[oldDate], isEmpty);
    expect(notifier.state[newDate]!.single.id, created.saved.id);
    expect(notifier.state[newDate]!.single.startMinutes, 660);
    expect(await DatabaseService.instance.getSchedulesForDate(oldDate), isEmpty);
    expect((await DatabaseService.instance.getSchedulesForDate(newDate)).single.id, created.saved.id);
    await notifier.delete(notifier.state[newDate]!.single);
  });
}
