import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/providers/overtime_provider.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/work_hours_calculator.dart' show dateKey;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  late Directory dir;
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('ot_calendar_dates_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await DatabaseService.instance.database;
  });
  tearDownAll(() async {
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    await dir.delete(recursive: true);
  });
  for (final row in [
    ('Europe/Berlin', 3, 28),
    ('Europe/Berlin', 10, 24),
    ('Europe/London', 3, 28),
    ('Europe/London', 10, 24),
    ('America/New_York', 3, 7),
    ('America/New_York', 10, 31),
    ('Australia/Lord_Howe', 4, 4),
    ('Australia/Lord_Howe', 10, 3),
    ('Asia/Seoul', 3, 28),
    ('Asia/Seoul', 10, 24),
    ('Asia/Kolkata', 12, 31)
  ]) {
    test(
        '${row.$1} ${row.$2} DB reload evicts zero OT and preserves outside dates',
        () async {
      await db.delete('date_overtime');
      final notifier = OvertimeNotifier();
      addTearDown(notifier.dispose);
      final zone = tz.getLocation(row.$1);
      final dates = [
        for (var i = -1; i <= 3; i++)
          tz.TZDateTime(zone, 2026, row.$2, row.$3 + i)
      ];
      for (final d in dates) {
        await notifier.adjust(dateKey(d), 30);
      }
      await DatabaseService.instance.adjustOvertime(dateKey(dates[2]), 60);
      await DatabaseService.instance.adjustOvertime(dateKey(dates[3]), -30);
      final before = await db.query('date_overtime', orderBy: 'date');
      await notifier.loadForRange(dates[1], dates[3]);
      expect(notifier.getForDate(dateKey(dates[1])), 30);
      expect(notifier.getForDate(dateKey(dates[2])), 90);
      expect(notifier.getForDate(dateKey(dates[3])), 0);
      expect(notifier.getForDate(dateKey(dates[0])), 30);
      expect(notifier.getForDate(dateKey(dates[4])), 30);
      expect(notifier.getRangeTotal(dates[1], dates[3]), 120);
      expect(notifier.getRangeEntries(dates[1], dates[3]).map((e) => e.key),
          [dateKey(dates[1]), dateKey(dates[2])]);
      expect(notifier.getRangeEntries(dates[3], dates[1]), isEmpty);
      expect(notifier.getRangeTotal(dates[3], dates[1]), 0);
      expect(await db.query('date_overtime', orderBy: 'date'), before,
          reason: 'Reload and aggregate must not rewrite stored OT');
      await notifier.loadForRange(dates.first, dates.last);
      final all = notifier.getRangeEntries(dates.first, dates.last);
      expect(all.map((e) => e.key).toSet().length, all.length);
      expect(notifier.getRangeTotal(dates.first, dates.last), 180);
    });
  }
}
