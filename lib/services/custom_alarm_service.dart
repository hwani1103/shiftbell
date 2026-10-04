import '../utils/alarm_wall_time.dart';
// lib/services/custom_alarm_service.dart
//
// 원터치 알람 설정 칸을 오늘·내일에 할당해 1회 알람(alarms.type='custom')을 만드는 경로.
//
// 동작은 고정 알람과 같은 OS 예약 인프라를 사용한다:
//  - DB 커밋 뒤에만 OS 예약(AlarmService.scheduleAlarm → 네이티브 AlarmWakeScheduler 단일 경로, CLAUDE.md ⚠️5)
//  - 네이티브가 예약 직후 AlarmGuardReceiver를 깨워 20분 전 사전 알림 처리
//  - 자동 갱신 엔진은 type='fixed'만 지우고 다시 만들므로 custom 행은 건드리지 않고, 재부팅·업데이트 때는
//    readOtherFutureAlarms()가 custom도 재등록(#26)
//  - 울림·끄기·스누즈 이력(alarm_history)과 생성 원장(alarm_creation_log, source='custom_preset')도 알람 ID 기준으로 동일하게 기록
//  - shift_type은 NULL, preset_slot/assigned_day가 설정 칸과 할당 날짜를 연결한다.
//    네이티브 화면·알림과 앱 화면에는 "원터치 알람"으로 표시한다.
//
// 검증(요구사항): ① 지금보다 이전(같은 시각 포함)이면 만들지 않음 ② 같은 날짜·같은 분에 이미 알람이 있으면 거부
// 한 설정 칸은 날짜별 1회만 할당한다. 고정과 원터치를 합친 날짜별 총량 제한은 없다.

import 'package:sqflite/sqflite.dart';

import '../models/alarm.dart';
import '../models/custom_alarm_preset.dart';
import '../models/alarm_template.dart';
import 'alarm_generation_service.dart';
import 'alarm_service.dart';
import 'database_service.dart';

enum CustomAlarmAssignResult { scheduled, past, outsideWindow, duplicate, alreadyAssigned, emptyPreset, scheduleFailed }

class CustomAlarmAssignOutcome {
  final CustomAlarmAssignResult result;
  final int? alarmId;
  final DateTime ringAt;
  final String? existingType;
  const CustomAlarmAssignOutcome(this.result, this.ringAt, {this.alarmId, this.existingType});
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

  /// 프리셋 시각을 [day] 날짜에 적용한 울림 시각(자정 넘김 없음 - 그 날짜 기준, 결정 사항).
  static DateTime ringAtFor(DateTime day, CustomAlarmPreset preset) {
    final t = preset.timeOfDay!;
    return resolveAlarmWallTime(DateTime.utc(day.year, day.month, day.day, t.hour, t.minute));
  }

  /// 순수 검증 - 단위 테스트로 고정(test/custom_alarm_service_test.dart).
  static CustomAlarmAssignResult? validate({
    required DateTime ringAt,
    required DateTime now,
    required List<ExistingAlarmSlot> sameDay,
  }) {
    if (!ringAt.isAfter(now)) return CustomAlarmAssignResult.past;
    final lastDay = DateTime(now.year, now.month, now.day + 1);
    final ringDay = DateTime(ringAt.year, ringAt.month, ringAt.day);
    final firstDay = DateTime(now.year, now.month, now.day);
    if (ringDay.isBefore(firstDay) || ringDay.isAfter(lastDay)) return CustomAlarmAssignResult.outsideWindow;
    final sameMinute = sameDay.any((a) =>
        a.ringAt.millisecondsSinceEpoch ~/ 60000 == ringAt.millisecondsSinceEpoch ~/ 60000);
    if (sameMinute) return CustomAlarmAssignResult.duplicate;
    return null;
  }

  static String _dayPrefix(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<ExistingAlarmSlot>> _readSameDay(DatabaseExecutor db, DateTime day) async {
    final rows = await db.query('alarms', columns: ['date', 'type'],
        where: "type = 'snoozed' OR date LIKE ?", whereArgs: ['${_dayPrefix(day)}%']);
    final result = <ExistingAlarmSlot>[];
    for (final r in rows) {
      final parsed = tryParseAlarmDate(r['date'] as String?);
      if (parsed != null) result.add(ExistingAlarmSlot(parsed, r['type'] as String? ?? ''));
    }
    return result;
  }

  /// [day]에 [preset]을 할당. 성공하면 DB 커밋 → OS 예약까지 끝난 상태. OS 예약이 실패하면(정확한 알람 권한 없음 등)
  /// 방금 만든 행을 지워 "DB엔 있는데 안 울리는" 상태를 남기지 않음.
  Future<CustomAlarmAssignOutcome> assign(DateTime day, CustomAlarmPreset preset, int slot, {DateTime? now}) async {
    if (slot < 0 || slot >= kCustomAlarmPresetCount) throw ArgumentError.value(slot, 'slot');
    if (preset.timeOfDay == null) {
      return CustomAlarmAssignOutcome(CustomAlarmAssignResult.emptyPreset, day);
    }
    final ringAt = ringAtFor(day, preset);
    final db = await DatabaseService.instance.database;

    CustomAlarmAssignResult? rejected;
    int? id;
    await db.transaction((txn) async {
      final dayRows = await txn.query('alarms', columns: ['id'],
          where: "type IN ('custom', 'snoozed') AND preset_slot = ? AND assigned_day = ?",
          whereArgs: [slot, _dayPrefix(day)], limit: 1);
      if (dayRows.isNotEmpty) {
        rejected = CustomAlarmAssignResult.alreadyAssigned;
        return;
      }
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
        presetSlot: slot,
        assignedDay: _dayPrefix(day),
      );
      id = await txn.insert('alarms', alarm.toMap()..remove('id'));
      await DatabaseService.instance.logAlarmCreation(txn, id!, alarm, creationSource);
    });
    if (rejected != null) {
      String? existingType;
      if (rejected == CustomAlarmAssignResult.duplicate) {
        final rows = await _readSameDay(db, day);
        for (final item in rows) {
          if (item.ringAt.millisecondsSinceEpoch ~/ 60000 == ringAt.millisecondsSinceEpoch ~/ 60000) {
            existingType = item.type;
            break;
          }
        }
      }
      return CustomAlarmAssignOutcome(rejected!, ringAt, existingType: existingType);
    }

    try {
      await AlarmService().scheduleAlarm(id: id!, dateTime: ringAt, label: '원터치 알람');
    } catch (_) {
      // 정확 예약이 거부돼도 Native가 비정확 대체 예약을 만들었을 수 있다.
      // DB를 먼저 되돌린 뒤 취소해야 Native의 행 재확인이 재예약하지 않는다.
      await DatabaseService.instance.deleteAlarm(id!, createHistory: false);
      await db.delete('alarm_creation_log', where: 'alarm_id = ?', whereArgs: [id]);
      try {
        await AlarmService().cancelAlarm(id!);
      } catch (_) {
        // Native 예약 실패 목록이 다음 갱신에서 DB에 없는 ID를 다시 취소한다.
        // 최초 예약 실패는 계속 scheduleFailed로 사용자에게 안내한다.
      }
      return CustomAlarmAssignOutcome(CustomAlarmAssignResult.scheduleFailed, ringAt, alarmId: id);
    }
    return CustomAlarmAssignOutcome(CustomAlarmAssignResult.scheduled, ringAt, alarmId: id);
  }

  /// 설정 칸에 연결된 아직 울리지 않은 알람. 삭제 확인과 수정 잠금에 공통 사용.
  Future<List<Alarm>> futureAssignments(int slot, {DateTime? now}) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('alarms',
        where: "type IN ('custom', 'snoozed') AND preset_slot = ?",
        whereArgs: [slot]);
    final instant = now ?? DateTime.now();
    return rows.map(Alarm.fromMap)
        .where((alarm) => alarm.date?.isAfter(instant) ?? false).toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
  }

  /// 이 원터치를 지우면 현재 근무와 템플릿 기준으로 같은 분에 생길 고정 알람.
  Future<PendingFixedAlarm?> previewFixedReplacement(DateTime at) async {
    if (!at.isAfter(DateTime.now())) return null;
    final db = await DatabaseService.instance.database;
    final schedule = await DatabaseService.instance.getShiftSchedule();
    if (schedule == null) return null;
    final templates = (await db.query('shift_alarm_templates')).map(AlarmTemplate.fromMap).toList();
    final overrides = await readAlarmOverrides(db);
    final candidates = computeDesiredFixedAlarmsForDate(
      date: at, schedule: schedule, allTemplates: templates, overrides: overrides,
    );
    for (final item in candidates) {
      if (alarmSlotTime(item.dateTime) == alarmSlotTime(at)) return item;
    }
    return null;
  }
}
