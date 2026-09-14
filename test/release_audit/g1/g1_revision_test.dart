// 출시전 수정 연결 - docs/release_audit/contracts.md §3 변경 통지 (G1 쓰기 쪽 의무)
// 원본 저장이 **성공한 뒤에만** 해당 영역 revision이 오르고, 저장이 실패하면 오르지 않는지 실제 SQLite로 확인.
// 계산 쪽 watch(G3)는 이 테스트 범위 밖.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/condition_shift_time_provider.dart';
import 'package:shiftbell/providers/data_revision_provider.dart';
import 'package:shiftbell/providers/overtime_provider.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/providers/work_hours_settings_provider.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late Database db;

  setUpAll(() async {
    initFfi();
    dir = await Directory.systemTemp.createTemp('g1_revision_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    db = await DatabaseService.instance.database;
    // 위젯 갱신 등 부수 채널 호출은 무시
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async => null);
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(kAlarmChannel, null);
    await db.close();
    DatabaseService.debugIsAndroidOverride = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.execute('DROP TRIGGER IF EXISTS g1_rev_fail_update');
    for (final t in ['shift_schedule', 'date_overtime', 'condition_shift_times']) {
      await db.delete(t);
    }
  });

  int rev(ProviderContainer c, DataDomain d) => c.read(dataRevisionProvider(d));

  test('근무표 저장·수정 성공 뒤 shiftSchedule·workHoursSettings 통지', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(scheduleProvider.notifier);

    await notifier.saveSchedule(ShiftSchedule(isRegular: false, shiftTypes: const ['A']));
    expect(rev(c, DataDomain.shiftSchedule), 1);
    expect(rev(c, DataDomain.workHoursSettings), 1);

    final saved = (await DatabaseService.instance.getShiftSchedule())!;
    await notifier.updateSchedule(ShiftSchedule(id: saved.id, isRegular: false, shiftTypes: const ['A'], assignedDates: const {'2026-09-20': 'A'}));
    expect(rev(c, DataDomain.shiftSchedule), 2);
  });

  test('근무표 수정이 DB에서 실패하면 통지하지 않는다', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(scheduleProvider.notifier);
    await notifier.saveSchedule(ShiftSchedule(isRegular: false, shiftTypes: const ['A']));
    final saved = (await DatabaseService.instance.getShiftSchedule())!;
    final before = rev(c, DataDomain.shiftSchedule);
    await db.execute("CREATE TRIGGER g1_rev_fail_update BEFORE UPDATE ON shift_schedule BEGIN SELECT RAISE(ABORT, 'injected'); END");

    await expectLater(
      notifier.updateSchedule(ShiftSchedule(id: saved.id, isRegular: false, shiftTypes: const ['A'], assignedDates: const {'2026-09-20': 'A'})),
      throwsA(anything),
    );
    expect(rev(c, DataDomain.shiftSchedule), before);
  });

  test('근로시간 설정 저장 성공 뒤 workHoursSettings 통지', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(workHoursSettingsProvider.notifier).setShiftChangeCountsAsOt(true);
    expect(rev(c, DataDomain.workHoursSettings), 1);
  });

  test('OT 증감 성공 뒤 overtime 통지', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(overtimeProvider.notifier).adjust('2026-09-14', 30);
    expect(rev(c, DataDomain.overtime), 1);
  });

  test('출퇴근 시각 저장·삭제 뒤 shiftTimes 통지', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(conditionShiftTimeProvider.notifier);
    await notifier.save('A', 540, 1080);
    await notifier.remove('A');
    expect(rev(c, DataDomain.shiftTimes), 2);
  });
}
