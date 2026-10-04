// 1.0.24 B - 원터치 알람 할당 검증(지난 시각·오늘/내일·같은 분 중복)과 설정 저장 형식.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/models/custom_alarm_preset.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/alarm_provider.dart';
import 'package:shiftbell/services/custom_alarm_service.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 23, 6, 30);

  group('CustomAlarmService.validate', () {
    test('지금 이후면 통과', () {
      expect(
          CustomAlarmService.validate(ringAt: DateTime(2026, 9, 23, 7, 0), now: now, sameDay: const []), isNull);
    });

    test('오늘과 내일만 허용', () {
      expect(CustomAlarmService.validate(
        ringAt: DateTime(2026, 9, 24, 7), now: now, sameDay: const []), isNull);
      expect(CustomAlarmService.validate(
        ringAt: DateTime(2026, 9, 25, 7), now: now, sameDay: const []),
        CustomAlarmAssignResult.outsideWindow);
    });

    test('지난 시각·지금과 같은 시각은 만들지 않음', () {
      expect(CustomAlarmService.validate(ringAt: DateTime(2026, 9, 23, 6, 0), now: now, sameDay: const []),
          CustomAlarmAssignResult.past);
      expect(CustomAlarmService.validate(ringAt: now, now: now, sameDay: const []), CustomAlarmAssignResult.past);
    });

    test('같은 날짜·같은 분(고정/커스텀/스누즈 모두)이면 중복', () {
      for (final type in ['fixed', 'custom', 'snoozed']) {
        expect(
            CustomAlarmService.validate(
                ringAt: DateTime(2026, 9, 23, 7, 0),
                now: now,
                sameDay: [ExistingAlarmSlot(DateTime(2026, 9, 23, 7, 0, 0, 500), type)]),
            CustomAlarmAssignResult.duplicate,
            reason: type);
      }
      // 분이 다르면 중복 아님
      expect(
          CustomAlarmService.validate(
              ringAt: DateTime(2026, 9, 23, 7, 1),
              now: now,
              sameDay: [ExistingAlarmSlot(DateTime(2026, 9, 23, 7, 0), 'fixed')]),
          isNull);
    });

    test('같은 분이 아니면 하루 5개가 있어도 추가할 수 있다', () {
      final five = [
        for (var h = 8; h < 13; h++) ExistingAlarmSlot(DateTime(2026, 9, 23, h), h.isEven ? 'fixed' : 'custom'),
      ];
      expect(CustomAlarmService.validate(ringAt: DateTime(2026, 9, 23, 20), now: now, sameDay: five),
          isNull);
    });

    test('자정 넘김 없음 - 그 날짜 기준 시각', () {
      const preset = CustomAlarmPreset(time: '00:30');
      expect(CustomAlarmService.ringAtFor(DateTime(2026, 9, 23), preset), DateTime(2026, 9, 23, 0, 30));
      // 오늘 00:30은 이미 지났으므로 거부
      expect(
          CustomAlarmService.validate(
              ringAt: CustomAlarmService.ringAtFor(DateTime(2026, 9, 23), preset), now: now, sameDay: const []),
          CustomAlarmAssignResult.past);
    });
  });

  group('CustomAlarmPreset 저장 형식', () {
    test('항상 5칸, 손상된 값은 빈 칸/기본 종류로', () {
      expect(CustomAlarmPreset.decodeList(null), hasLength(5));
      expect(CustomAlarmPreset.decodeList('not json').every((p) => p.isEmpty), isTrue);
      final list = CustomAlarmPreset.decodeList(
          '[{"time":"07:00","alarmTypeId":2},{"time":"25:00","alarmTypeId":3},{"time":"09:15","alarmTypeId":99},"x"]');
      expect(list[0], const CustomAlarmPreset(time: '07:00', alarmTypeId: 2));
      expect(list[1], const CustomAlarmPreset(alarmTypeId: 3)); // 잘못된 시각 → 빈 칸
      expect(list[2], const CustomAlarmPreset(time: '09:15', alarmTypeId: 1)); // 알 수 없는 종류 → 1
      expect(list[3].isEmpty && list[4].isEmpty, isTrue);
    });

    test('왕복 인코딩', () {
      final presets = [
        const CustomAlarmPreset(time: '06:40', alarmTypeId: 1),
        CustomAlarmPreset.empty,
        const CustomAlarmPreset(time: '18:00', alarmTypeId: 3),
        CustomAlarmPreset.empty,
        const CustomAlarmPreset(time: '23:59', alarmTypeId: 2),
      ];
      expect(CustomAlarmPreset.decodeList(CustomAlarmPreset.encodeList(presets)), presets);
    });
  });

  group('실제 DB 할당 연결', () {
    late Directory dir;
    late Database db;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('one_tap_slots_');
      await databaseFactory.setDatabasesPath(dir.path);
      DatabaseService.debugIsAndroidOverride = false;
      db = await DatabaseService.instance.database;
      messenger.setMockMethodCallHandler(kAlarmChannel, (call) async => null);
    });
    tearDownAll(() async {
      messenger.setMockMethodCallHandler(kAlarmChannel, null);
      await db.close();
      DatabaseService.debugIsAndroidOverride = null;
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    setUp(() async {
      for (final table in ['alarm_history', 'alarm_creation_log', 'alarms',
        'shift_alarm_templates', 'shift_schedule', 'alarm_overrides']) {
        await db.delete(table);
      }
    });

    test('offset snooze remains upcoming and cancellation history keeps its instant', () async {
      final target = DateTime.now().add(const Duration(minutes: 5));
      final id = await db.insert('alarms', Alarm(time: '01:04', date: target,
          type: 'snoozed', alarmTypeId: 1, presetSlot: 0).toMap()
        ..['date'] = target.toUtc().toIso8601String());
      expect((await DatabaseService.instance.getNextAlarms()).single.date, target);
      expect((await DatabaseService.instance.getAlarmsByDate(target)).single.id, id);
      final assignments = await CustomAlarmService.instance.futureAssignments(0);
      expect(assignments.single.date, target);
      expect(assignments.single.time,
          '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}');
      expect(await DatabaseService.instance.deleteFutureOneTapSlot(0), hasLength(1));
      final history = await DatabaseService.instance.getAllAlarmHistory();
      expect(history.single.scheduledDate, target);
    });

    test('history sorts the second 01:04 after the first 01:58', () async {
      for (final date in ['2026-11-01T01:58:00-04:00', '2026-11-01T01:04:00-05:00']) {
        await db.insert('alarm_history', {'alarm_id': 7,
          'scheduled_date': date, 'scheduled_time': date.substring(11, 16),
          'actual_ring_time': date, 'created_at': date, 'dismiss_type': 'snoozed', 'snooze_count': 0});
      }
      final history = await DatabaseService.instance.getAllAlarmHistory();
      expect(history, hasLength(2));
      expect(history.first.createdAt.toUtc(), DateTime.parse('2026-11-01T06:04:00Z'));
    });

    test('5칸을 하루에 한 번씩만 할당하고 설정 칸 삭제는 연결된 날짜를 함께 지운다', () async {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      for (var slot = 0; slot < 5; slot++) {
        final preset = CustomAlarmPreset(time: '${(6 + slot).toString().padLeft(2, '0')}:00');
        final result = await CustomAlarmService.instance.assign(tomorrow, preset, slot);
        expect(result.result, CustomAlarmAssignResult.scheduled);
      }
      final sixth = await CustomAlarmService.instance.assign(
          tomorrow, const CustomAlarmPreset(time: '12:00'), 0);
      expect(sixth.result, CustomAlarmAssignResult.alreadyAssigned);
      expect(await db.rawQuery("SELECT id FROM alarms WHERE type = 'custom'"), hasLength(5));
      final removed = await DatabaseService.instance.deleteFutureOneTapSlot(0);
      expect(removed, hasLength(1));
      expect(await db.rawQuery("SELECT id FROM alarms WHERE type = 'custom'"), hasLength(4));
      expect(await db.rawQuery('SELECT id FROM alarm_history WHERE alarm_id = ?', [removed.single.id]), hasLength(1));
    });

    test('Native 예약 실패 시 원터치 행과 생성 원장을 지우고 재시도를 허용한다', () async {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final fallbackReservations = <int>{};
      messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
        if (call.method == 'scheduleNativeAlarm') {
          fallbackReservations.add(call.arguments['id'] as int);
          throw PlatformException(code: 'SCHEDULE_DENIED');
        }
        if (call.method == 'cancelNativeAlarm') {
          final id = call.arguments['id'] as int;
          expect(await db.query('alarms', where: 'id = ?', whereArgs: [id]), isEmpty,
              reason: 'Native cancellation must follow the committed DB rollback');
          fallbackReservations.remove(id);
        }
        return null;
      });
      try {
        final failed = await CustomAlarmService.instance.assign(
            tomorrow, const CustomAlarmPreset(time: '23:11'), 1);
        expect(failed.result, CustomAlarmAssignResult.scheduleFailed);
        expect(fallbackReservations, isEmpty);
        expect(await db.query('alarms', where: 'id = ?', whereArgs: [failed.alarmId]), isEmpty);
        expect(await db.query('alarm_creation_log',
            where: 'alarm_id = ?', whereArgs: [failed.alarmId]), isEmpty);
        expect(await db.query('alarm_history',
            where: 'alarm_id = ?', whereArgs: [failed.alarmId]), isEmpty);
      } finally {
        messenger.setMockMethodCallHandler(kAlarmChannel, (call) async => null);
      }
      final retried = await CustomAlarmService.instance.assign(
          tomorrow, const CustomAlarmPreset(time: '23:11'), 1);
      expect(retried.result, CustomAlarmAssignResult.scheduled);
      expect(await db.query('alarms', where: "type = 'custom'"), hasLength(1));
    });

    test('replacement scheduling failure reports failure and requests native retry', () async {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final dayKey = tomorrow.toIso8601String().substring(0, 10);
      final oneTap = await CustomAlarmService.instance.assign(
          tomorrow, const CustomAlarmPreset(time: '07:00'), 0);
      await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
          isRegular: false, shiftTypes: const ['DAY'], assignedDates: {dayKey: 'DAY'}));
      await db.insert('shift_alarm_templates', {
        'shift_type': 'DAY', 'time': '07:00', 'alarm_type_id': 1, 'day_offset': 0,
      });
      var retryRequested = false;
      messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
        if (call.method == 'scheduleNativeAlarm') {
          throw PlatformException(code: 'SCHEDULE_DENIED');
        }
        if (call.method == 'forceNativeRefresh') retryRequested = true;
        return null;
      });
      final notifier = AlarmNotifier();
      try {
        final result = await notifier.deleteAlarm(oneTap.alarmId!, oneTap.ringAt);
        expect(result.reservationFailed, isTrue);
        expect(result.fixedReplacement, isFalse);
        expect(retryRequested, isTrue);
        expect(await db.query('alarms', where: "type = 'custom'"), isEmpty);
        expect(await db.query('alarms', where: "type = 'fixed'"), hasLength(1));
        expect(await db.query('alarm_history', where: 'alarm_id = ?',
            whereArgs: [oneTap.alarmId]), hasLength(1));
      } finally {
        notifier.dispose();
        messenger.setMockMethodCallHandler(kAlarmChannel, (call) async => null);
      }
    });

    test('원터치 삭제 뒤 잠시 건너뛴 고정을 새 ID로 생성하고 예약한다', () async {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final dayKey = '${tomorrow.year.toString().padLeft(4, '0')}-'
          '${tomorrow.month.toString().padLeft(2, '0')}-'
          '${tomorrow.day.toString().padLeft(2, '0')}';
      final oneTap = await CustomAlarmService.instance.assign(
          tomorrow, const CustomAlarmPreset(time: '07:00'), 0);
      expect(oneTap.result, CustomAlarmAssignResult.scheduled);
      await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
          isRegular: false, shiftTypes: const ['DAY'], assignedDates: {dayKey: 'DAY'}));
      await db.insert('shift_alarm_templates', {
        'shift_type': 'DAY', 'time': '07:00', 'alarm_type_id': 1, 'day_offset': 0,
      });
      final notifier = AlarmNotifier();
      await notifier.refresh();
      final deletion = await notifier.deleteAlarm(oneTap.alarmId!, oneTap.ringAt);
      expect(deletion.fixedReplacement, isTrue);
      expect(deletion.reservationFailed, isFalse);
      final fixed = await db.query('alarms', where: "type = 'fixed'");
      expect(fixed, hasLength(1));
      expect(fixed.single['id'], isNot(oneTap.alarmId));
      expect(await db.query('alarm_creation_log', where: 'alarm_id = ?', whereArgs: [oneTap.alarmId]), hasLength(1));
      expect(await db.query('alarm_creation_log', where: 'alarm_id = ?', whereArgs: [fixed.single['id']]), hasLength(1));
      expect(await db.query('alarm_history', where: 'alarm_id = ?', whereArgs: [oneTap.alarmId]), hasLength(1));
      notifier.dispose();
    });
  });
}
