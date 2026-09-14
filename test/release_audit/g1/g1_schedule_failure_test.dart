// 출시전 감사 G1 #13 - 등록 실패 무통보 + 권한 상태 오판 (docs/release_audit/g1/handoff.md)
//
// - AlarmScheduleOutcome: 0개·전부·일부 실패 판정 (예전 `failCount > 0 && scheduled.isEmpty`는 항상 거짓)
// - ScheduleNotificationService.syncForSchedule: Native true/false/throw/형식 이상별 반환
// - PermissionService.checkExactAlarmPermissionState: true/false/throw/형식 이상 → granted/denied/unknown
//
// Native 쪽 실제 예약 실패(SecurityException → false)는 Kotlin G1ScheduleResultTest.
// 화면 안내(스낵바)·재허용 후 회복은 E/D S2.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/models/date_schedule.dart';
import 'package:shiftbell/services/alarm_service.dart';
import 'package:shiftbell/services/permission_service.dart';
import 'package:shiftbell/services/schedule_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];
  void mockChannel(Object? Function(MethodCall call) handler) {
    calls.clear();
    messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(kAlarmChannel, null));

  group('#13 AlarmScheduleOutcome', () {
    test('시도 0개는 실패 아님', () {
      const o = AlarmScheduleOutcome(attempted: 0, failed: 0);
      expect(o.allFailed, isFalse);
      expect(o.partiallyFailed, isFalse);
    });
    test('전부 실패', () {
      const o = AlarmScheduleOutcome(attempted: 3, failed: 3);
      expect(o.allFailed, isTrue);
      expect(o.partiallyFailed, isFalse);
    });
    test('일부 실패', () {
      const o = AlarmScheduleOutcome(attempted: 3, failed: 1);
      expect(o.allFailed, isFalse);
      expect(o.partiallyFailed, isTrue);
    });
    test('실패 없음', () {
      const o = AlarmScheduleOutcome(attempted: 3, failed: 0);
      expect(o.allFailed, isFalse);
      expect(o.partiallyFailed, isFalse);
    });
  });

  group('#13 ScheduleNotificationService.syncForSchedule', () {
    final future = DateTime.now().add(const Duration(days: 2));
    String two(int v) => v.toString().padLeft(2, '0');
    final dateKey = '${future.year}-${two(future.month)}-${two(future.day)}';

    DateSchedule schedule({bool notify = true, String? date}) => DateSchedule(
          id: 5,
          date: date ?? dateKey,
          content: '회의',
          startMinutes: 600,
          durationMinutes: 30,
          notifyEnabled: notify,
          createdAt: '2026-09-14T00:00:00',
        );

    test('Native가 true면 true', () async {
      mockChannel((call) => call.method == 'scheduleDateNotification' ? true : null);
      expect(await ScheduleNotificationService.syncForSchedule(schedule()), isTrue);
      expect(calls.map((c) => c.method), ['cancelDateNotification', 'scheduleDateNotification']);
    });

    test('Native가 false(예약 거부)면 false', () async {
      mockChannel((call) => call.method == 'scheduleDateNotification' ? false : null);
      expect(await ScheduleNotificationService.syncForSchedule(schedule()), isFalse);
    });

    test('채널 오류면 false', () async {
      mockChannel((call) {
        if (call.method == 'scheduleDateNotification') {
          throw PlatformException(code: 'boom');
        }
        return null;
      });
      expect(await ScheduleNotificationService.syncForSchedule(schedule()), isFalse);
    });

    test('Native 결과가 bool이 아니면(null) 성공으로 보지 않음', () async {
      mockChannel((call) => null);
      expect(await ScheduleNotificationService.syncForSchedule(schedule()), isFalse);
    });

    test('알림이 꺼져 있으면 예약 없이 true', () async {
      mockChannel((call) => true);
      expect(await ScheduleNotificationService.syncForSchedule(schedule(notify: false)), isTrue);
      expect(calls.map((c) => c.method), ['cancelDateNotification']);
    });

    test('이미 지난 시각이면 예약 없이 true', () async {
      mockChannel((call) => true);
      expect(await ScheduleNotificationService.syncForSchedule(schedule(date: '2020-01-01')), isTrue);
      expect(calls.map((c) => c.method), ['cancelDateNotification']);
    });

    test('날짜 형식 오류면 false', () async {
      mockChannel((call) => true);
      expect(await ScheduleNotificationService.syncForSchedule(schedule(date: 'bad')), isFalse);
    });
  });

  group('#13 PermissionService.checkExactAlarmPermissionState', () {
    Future<ExactAlarmPermissionState> stateFor(Object? Function(MethodCall) handler) {
      mockChannel(handler);
      return PermissionService().checkExactAlarmPermissionState();
    }

    test('true → granted', () async {
      expect(await stateFor((_) => true), ExactAlarmPermissionState.granted);
    });
    test('false → denied', () async {
      expect(await stateFor((_) => false), ExactAlarmPermissionState.denied);
      expect(await PermissionService().checkExactAlarmPermission(), isFalse);
    });
    test('채널 오류 → unknown (허용으로 보지 않음)', () async {
      expect(await stateFor((_) => throw PlatformException(code: 'boom')), ExactAlarmPermissionState.unknown);
    });
    test('형식 이상(null) → unknown', () async {
      expect(await stateFor((_) => null), ExactAlarmPermissionState.unknown);
    });
    test('T11-01 채널 오류 unknown은 권한 허용으로 축약하지 않는다', () async {
      mockChannel((_) => throw PlatformException(code: 'boom'));
      expect(await PermissionService().checkExactAlarmPermission(), isFalse);
    });
    test('T11-01 형식 이상 unknown도 권한 허용으로 축약하지 않는다', () async {
      mockChannel((_) => null);
      expect(await PermissionService().checkExactAlarmPermission(), isFalse);
    });
  });
}
