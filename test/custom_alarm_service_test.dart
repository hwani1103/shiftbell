// 1.0.24 B - 커스텀 알람 할당 검증(지난 시각·같은 분 중복·하루 5개)과 프리셋 저장 형식.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/custom_alarm_preset.dart';
import 'package:shiftbell/services/custom_alarm_service.dart';

void main() {
  final now = DateTime(2026, 9, 23, 6, 30);

  group('CustomAlarmService.validate', () {
    test('지금 이후면 통과', () {
      expect(
          CustomAlarmService.validate(ringAt: DateTime(2026, 9, 23, 7, 0), now: now, sameDay: const []), isNull);
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

    test('고정+커스텀 합산 5개면 하루 한도(스누즈는 세지 않음)', () {
      final five = [
        for (var h = 8; h < 13; h++) ExistingAlarmSlot(DateTime(2026, 9, 23, h), h.isEven ? 'fixed' : 'custom'),
      ];
      expect(CustomAlarmService.validate(ringAt: DateTime(2026, 9, 23, 20), now: now, sameDay: five),
          CustomAlarmAssignResult.dailyLimit);
      final fourPlusSnooze = [
        ...five.take(4),
        ExistingAlarmSlot(DateTime(2026, 9, 23, 13), 'snoozed'),
      ];
      expect(CustomAlarmService.validate(ringAt: DateTime(2026, 9, 23, 20), now: now, sameDay: fourPlusSnooze),
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
}
