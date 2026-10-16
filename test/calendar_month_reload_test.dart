import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/providers/memo_provider.dart';
import 'package:shiftbell/providers/overtime_provider.dart';
import 'package:shiftbell/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('calendar_reload_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await directory.delete(recursive: true);
  });
  test('same memo range emits no rebuild, changed/deleted rows do', () async {
    final notifier = MemoNotifier();
    addTearDown(notifier.dispose);
    var changes = 0;
    notifier.addListener((_) => changes++, fireImmediately: false);
    final start = DateTime(2026, 10, 1), end = DateTime(2026, 10, 31);
    await notifier.loadMemosForDateRange(start, end);
    expect(changes, 0);
    final id = await DatabaseService.instance.createMemo('2026-10-15', 'first');
    await notifier.loadMemosForDateRange(start, end);
    expect(changes, 1);
    await notifier.loadMemosForDateRange(start, end);
    expect(changes, 1);
    await DatabaseService.instance.updateMemo(id!, 'changed');
    await notifier.loadMemosForDateRange(start, end);
    expect(changes, 2);
    expect(notifier.getMemosForDate('2026-10-15').single.memoText, 'changed');
    await DatabaseService.instance.createMemo('2026-11-01', 'outside');
    await notifier.loadMemosForDateRange(start, DateTime(2026, 11, 1));
    await DatabaseService.instance.deleteMemo(id);
    await notifier.loadMemosForDateRange(start, end);
    expect(notifier.getMemosForDate('2026-10-15'), isEmpty);
    expect(notifier.getMemosForDate('2026-11-01').single.memoText, 'outside');
  });
  test('same OT range emits no rebuild, changed/zero values do', () async {
    final notifier = OvertimeNotifier();
    addTearDown(notifier.dispose);
    var changes = 0;
    notifier.addListener((_) => changes++, fireImmediately: false);
    final day = DateTime(2026, 10, 15);
    await notifier.loadForRange(day, day);
    expect(changes, 0);
    await DatabaseService.instance.adjustOvertime('2026-10-15', 30);
    await notifier.loadForRange(day, day);
    expect(changes, 1);
    await notifier.loadForRange(day, day);
    expect(changes, 1);
    await DatabaseService.instance.adjustOvertime('2026-10-15', -30);
    await notifier.loadForRange(day, day);
    expect(changes, 2);
    expect(notifier.getForDate('2026-10-15'), 0);
  });
}
