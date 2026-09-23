// lib/services/custom_alarm_service.dart
//
// ⭐ 2026-09-23 (1.0.24 B) - 커스텀 알람 프리셋을 날짜에 할당해 1회 알람(alarms.type='custom')을 만드는 단일 경로.
//
// 동작은 고정 알람과 같은 인프라를 그대로 탄다(새 네이티브 코드 없음):
//  - DB 커밋 뒤에만 OS 예약(AlarmService.scheduleAlarm → 네이티브 AlarmWakeScheduler 단일 경로, CLAUDE.md ⚠️5)
//  - 네이티브가 예약 직후 AlarmGuardReceiver를 깨워 20분 전 사전 알림 처리
//  - 자동 갱신 엔진은 type='fixed'만 지우고 다시 만들므로 custom 행은 건드리지 않고, 재부팅·업데이트 때는
//    readOtherFutureAlarms()가 custom도 재등록(#26)
//  - 울림·끄기·스누즈 이력(alarm_history)과 생성 원장(alarm_creation_log, source='custom_preset')도 알람 ID 기준으로 동일하게 기록
//  - shift_type은 NULL - 네이티브 화면·알림은 이미 "알람"으로 표시하고, 앱 화면은 "커스텀 알람"으로 표시
//
// 검증(요구사항): ① 지금보다 이전(같은 시각 포함)이면 만들지 않음 ② 같은 날짜·같은 분에 이미 알람이 있으면 거부
// ③ 그날 울리는 알람(고정+커스텀)이 이미 kMaxAlarmTemplatesPerShift(5)개면 거부. 검증과 insert는 한 트랜잭션.

import 'package:sqflite/sqflite.dart';

import '../constants/alarm_limits.dart';
import '../models/alarm.dart';
import '../models/custom_alarm_preset.dart';
import 'alarm_service.dart';
import 'database_service.dart';

enum CustomAlarmAssignResult { scheduled, past, duplicate, dailyLimit, emptyPreset, scheduleFailed }

class CustomAlarmAssignOutcome {
  final CustomAlarmAssignResult result;
  final int? alarmId;
  final DateTime ringAt;
  const CustomAlarmAssignOutcome(this.result, this.ringAt, {this.alarmId});
}

/// 같은 날 이미 있는 알람 한 개(검증 입력).
class ExistingAlarmSlot {
  final DateTime ringAt;
  final String type; // 'fixed' | 'custom' | 'snoozed' ...
  const ExistingAlarmSlot(this.ringAt, this.type);
}

class CustomAlarmService {
  CustomAlarmService._();
  static final CustomAlarmService instance = CustomAlarmService._();

  /// 생성 원장 source 값.
  static const creationSource = 'custom_preset';

  /// 하루 최대 알람 수(고정+커스텀 합산, 결정 1).
  static const int dailyLimit = kMaxAlarmTemplatesPerShift;

  /// 프리셋 시각을 [day] 날짜에 적용한 울림 시각(자정 넘김 없음 - 그 날짜 기준, 결정 사항).
  static DateTime ringAtFor(DateTime day, CustomAlarmPreset preset) {
    final t = preset.timeOfDay!;
    return DateTime(day.year, day.month, day.day, t.hour, t.minute);
  }

  /// 순수 검증 - 단위 테스트로 고정(test/custom_alarm_service_test.dart).
  static CustomAlarmAssignResult? validate({
    required DateTime ringAt,
    required DateTime now,
    required List<ExistingAlarmSlot> sameDay,
  }) {
    if (!ringAt.isAfter(now)) return CustomAlarmAssignResult.past;
    final sameMinute = sameDay.any((a) =>
        a.ringAt.year == ringAt.year &&
        a.ringAt.month == ringAt.month &&
        a.ringAt.day == ringAt.day &&
        a.ringAt.hour == ringAt.hour &&
        a.ringAt.minute == ringAt.minute);
    if (sameMinute) return CustomAlarmAssignResult.duplicate;
    // 스누즈 연장분은 원래 알람의 연속이라 개수에서 제외(고정+커스텀만 셈)
    final counted = sameDay.where((a) => a.type == 'fixed' || a.type == 'custom').length;
    if (counted >= dailyLimit) return CustomAlarmAssignResult.dailyLimit;
    return null;
  }

  static String _dayPrefix(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<ExistingAlarmSlot>> _readSameDay(DatabaseExecutor db, DateTime day) async {
    final rows = await db.query('alarms', columns: ['date', 'type'], where: 'date LIKE ?', whereArgs: ['${_dayPrefix(day)}%']);
    final result = <ExistingAlarmSlot>[];
    for (final r in rows) {
      final parsed = DateTime.tryParse(r['date'] as String? ?? '');
      if (parsed != null) result.add(ExistingAlarmSlot(parsed, r['type'] as String? ?? ''));
    }
    return result;
  }

  /// [day]에 [preset]을 할당. 성공하면 DB 커밋 → OS 예약까지 끝난 상태. OS 예약이 실패하면(정확한 알람 권한 없음 등)
  /// 방금 만든 행을 지워 "DB엔 있는데 안 울리는" 상태를 남기지 않음.
  Future<CustomAlarmAssignOutcome> assign(DateTime day, CustomAlarmPreset preset, {DateTime? now}) async {
    if (preset.timeOfDay == null) {
      return CustomAlarmAssignOutcome(CustomAlarmAssignResult.emptyPreset, day);
    }
    final ringAt = ringAtFor(day, preset);
    final db = await DatabaseService.instance.database;

    CustomAlarmAssignResult? rejected;
    int? id;
    await db.transaction((txn) async {
      final sameDay = await _readSameDay(txn, day);
      rejected = validate(ringAt: ringAt, now: now ?? DateTime.now(), sameDay: sameDay);
      if (rejected != null) return;
      final alarm = Alarm(
        time: preset.time!,
        date: ringAt,
        type: 'custom',
        alarmTypeId: preset.alarmTypeId,
        shiftType: null,
        dayOffset: 0,
      );
      id = await txn.insert('alarms', alarm.toMap()..remove('id'));
      await DatabaseService.instance.logAlarmCreation(txn, id!, alarm, creationSource);
    });
    if (rejected != null) return CustomAlarmAssignOutcome(rejected!, ringAt);

    try {
      await AlarmService().scheduleAlarm(id: id!, dateTime: ringAt, label: '알람');
    } catch (_) {
      // 예약 실패 - 행만 조용히 되돌림(이력 없음: 사용자가 만든 적이 없는 것과 같게). 생성 원장은 append-only라 그대로 둠.
      await DatabaseService.instance.deleteAlarm(id!, createHistory: false);
      return CustomAlarmAssignOutcome(CustomAlarmAssignResult.scheduleFailed, ringAt, alarmId: id);
    }
    return CustomAlarmAssignOutcome(CustomAlarmAssignResult.scheduled, ringAt, alarmId: id);
  }
}
