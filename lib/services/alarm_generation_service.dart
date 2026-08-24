// lib/services/alarm_generation_service.dart
//
// ⭐ 2026-08-24 추가 - "전날/당일/다음날"(day_offset) 고정 알람 도입과 함께,
// 하루치 알람을 계산하는 로직을 한 곳으로 모음.
//
// 예전엔 "날짜 D에 울려야 할 알람 = 그 날 배정된 근무 하나의 템플릿"이라 아주
// 단순했지만, 이제 알람이 "전날/다음날"로도 등록될 수 있어서 날짜 D의 알람은
// 최대 세 근무(D-1/D/D+1에 배정된 근무)의 기여를 받을 수 있음. 이 계산은
// onboarding(초기 10일치), 달력 탭(근무 변경/일괄 배정), 설정(고정 알람 수정
// 저장) 세 곳이 전부 동일하게 써야 함 - 계산식이 조금이라도 어긋나면 Kotlin
// AlarmRefreshEngine.kt의 diff 갱신이 "달라졌다"고 오판해서 알람을 불필요하게
// 지웠다 다시 만드는 처가 생기므로, **이 파일의 알고리즘을 바꾸면 반드시
// AlarmRefreshEngine.kt의 computeDesiredAlarms()도 동일하게 맞출 것.**
//
// ⭐ 같은 실제 시각에 서로 다른 근무의 알람이 겹치는 경우(예: 주간 당일 05:00 +
// 야간 전날 05:00) 물리적으로 알림은 한 번만 울릴 수 있으므로, 우선순위
// 당일(offset 0) > 전날 기여(offset -1, D+1에 배정된 근무) > 다음날 기여
// (offset +1, D-1에 배정된 근무) 순으로 먼저 차지한 시각은 그대로 두고 뒤에
// 오는 건 건너뜀 - "동일한 알람이 중복 생성되면 한 번만 울리게" 요구사항.

import 'package:sqflite/sqflite.dart';
import '../models/alarm.dart';
import '../models/alarm_template.dart';
import '../models/shift_schedule.dart';
import '../constants/alarm_day_offset.dart';
import 'database_service.dart';

class PendingFixedAlarm {
  final DateTime dateTime;
  final String time; // HH:mm
  final int alarmTypeId;
  final String shiftType;
  final int dayOffset;

  PendingFixedAlarm({
    required this.dateTime,
    required this.time,
    required this.alarmTypeId,
    required this.shiftType,
    required this.dayOffset,
  });
}

/// 실제 날짜 [date]에 울려야 하는 고정 알람 목록을 계산함(과거 시각은 제외).
/// [allTemplates]는 보통 DatabaseService.getAllAlarmTemplates()의 전체 목록을
/// 그대로 넘기면 됨(호출부가 여러 날짜를 반복 계산할 때 매번 다시 쿼리하지
/// 않도록 미리 한 번만 읽어서 전달하는 용도).
List<PendingFixedAlarm> computeDesiredFixedAlarmsForDate({
  required DateTime date,
  required ShiftSchedule schedule,
  required List<AlarmTemplate> allTemplates,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final dayBefore = DateTime(date.year, date.month, date.day - 1);
  final dayAfter = DateTime(date.year, date.month, date.day + 1);

  final sameDayShift = schedule.getShiftForDate(date);       // offset 0 기여
  final nextDayShift = schedule.getShiftForDate(dayAfter);   // offset -1(전날) 기여
  final prevDayShift = schedule.getShiftForDate(dayBefore);  // offset +1(다음날) 기여

  final Map<String, PendingFixedAlarm> byTime = {}; // key = "HH:mm"

  void addFrom(String shiftType, int offset) {
    if (shiftType == kUnsetShiftSentinel) return;
    for (final template in allTemplates) {
      if (template.shiftType != shiftType || template.dayOffset != offset) continue;
      if (byTime.containsKey(template.time)) continue; // ⭐ 이미 다른 근무가 이 시각을 선점

      final timeParts = template.time.split(':');
      if (timeParts.length < 2) continue;
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );

      // ⭐ 2026-08-25 - 예전엔 "now - 1분"까지 봐주는 유예가 있었는데, 이 함수가
      // (규모가 커진 regenerateFixedAlarmsForDatesTxn을 통해) 실제 delete 쿼리와
      // 짝을 이루게 되면서 두 경계가 어긋나면 "막 울리기 시작한 알람이 지워지기만
      // 하고 다시 안 만들어지는" 또는 반대로 "같은 알람이 중복으로 다시 만들어지는"
      // 문제가 생길 수 있음이 드러남 - AlarmRefreshEngine.kt가 이미 겪고 고친
      // 문제(readExistingFixedAlarms의 "> now"와 정확히 같은 기준으로 맞춤)와
      // 동일한 종류라, 여기도 유예 없이 정확히 "> now"로 통일함(아래 delete
      // 쿼리의 "date > ?" 경계와 반드시 같은 now를 써야 함).
      if (!alarmTime.isAfter(effectiveNow)) continue;

      byTime[template.time] = PendingFixedAlarm(
        dateTime: alarmTime,
        time: template.time,
        alarmTypeId: template.alarmTypeId,
        shiftType: shiftType,
        dayOffset: offset,
      );
    }
  }

  addFrom(sameDayShift, kAlarmDaySame);
  addFrom(nextDayShift, kAlarmDayBefore);
  addFrom(prevDayShift, kAlarmDayAfter);

  return byTime.values.toList();
}

/// 원본 근무일 [date]가 배정/변경되면, 그 알람이 전날/당일/다음날 중 무엇으로도
/// 등록될 수 있으므로 영향을 받는 실제 알람 날짜는 [date-1, date, date+1] 세 개임.
/// 근무 변경/일괄 배정 호출부가 공통으로 쓰는 헬퍼.
Set<DateTime> datesAffectedByShiftChange(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return {
    DateTime(d.year, d.month, d.day - 1),
    d,
    DateTime(d.year, d.month, d.day + 1),
  };
}

class ScheduledAlarmRef {
  final int id;
  final DateTime dateTime;
  final String label;
  ScheduledAlarmRef({required this.id, required this.dateTime, required this.label});
}

class RegenerateAlarmsResult {
  final List<int> cancelIds;
  final List<ScheduledAlarmRef> scheduled;
  RegenerateAlarmsResult({required this.cancelIds, required this.scheduled});
}

/// [dates]에 해당하는 실제 알람 날짜들의 고정 알람(type='fixed')을 전부 다시
/// 계산해서 델타를 적용함(기존 것은 이력에 남기고 삭제, 새로 계산된 것을 삽입).
/// 이미 열려 있는 트랜잭션(txn) 안에서 실행됨 - 호출부가 스케줄 저장 등 다른
/// DB 작업과 한 트랜잭션으로 같이 묶고 싶을 때 이 함수를 직접 씀
/// (schedule_provider.dart의 changeShiftWithAlarms). 트랜잭션을 새로 열어도
/// 상관없는 단순한 경우엔 아래 [regenerateFixedAlarmsForDates]를 쓸 것.
/// Native AlarmManager 취소/재등록은 이 함수가 하지 않음 - 트랜잭션 커밋 후
/// 호출부가 반환값(cancelIds/scheduled)으로 처리해야 함(이 프로젝트의 기존 관례 -
/// 트랜잭션 안에서 플랫폼 채널을 부르지 않음).
Future<RegenerateAlarmsResult> regenerateFixedAlarmsForDatesTxn({
  required DatabaseExecutor txn,
  required ShiftSchedule schedule,
  required Set<DateTime> dates,
}) async {
  final cancelIds = <int>[];
  final scheduled = <ScheduledAlarmRef>[];
  final now = DateTime.now();

  final templateMaps = await txn.query('shift_alarm_templates');
  final allTemplates = templateMaps.map((m) => AlarmTemplate.fromMap(m)).toList();

  for (final date in dates) {
    final dateStr = date.toIso8601String().split('T')[0];

    // 1단계: 이 날짜의 기존 고정 알람 삭제 + 이력 기록 (어떤 근무 소속이었든 전부 -
    // 새로 계산되는 값이 그 자리를 대체함).
    // ⭐ 2026-08-25 - CRITICAL FIX: "AND date > ?"(now)를 반드시 추가해야 함.
    // 예전(이 함수 이전의 단일 날짜 버전들)엔 이 시간 경계가 없어서, 지금 막
    // 울리고 있는(또는 방금 지나간) 알람도 "이 날짜의 알람"으로 걸려서 그냥
    // 지워졌음. 아래 computeDesiredFixedAlarmsForDate()는 과거 시각을 절대 다시
    // 만들지 않으므로(같은 now 기준 "> now"), 지워지기만 하고 재생성되지 않는
    // 알람이 생김 - 그 알람이 정확히 지금 화면에 떠서 울리는 중이라면, DB 행이
    // 사라진 채로 계속 울리다가 나중에 스누즈를 눌러도 AlarmActionHelper.snooze가
    // "알람 정보 없음"으로 조용히 실패함(사용자는 스누즈했다고 생각하는데 실제로는
    // 아무 것도 예약되지 않음). 이 날짜의 근무가 바뀌어서 알람이 무효화되더라도,
    // 이미 지금 울리고 있는 알람은 그 자체로 "처리 중"인 사건이라 건드리지 않는
    // 게 맞음 - 응답(끄기/스누즈/타임아웃)은 항상 AlarmActionHelper가 별도로
    // 책임지므로 여기서 손댈 필요도 없음.
    final existingRows = await txn.query(
      'alarms',
      where: 'date LIKE ? AND type = ? AND date > ?',
      whereArgs: ['$dateStr%', 'fixed', now.toIso8601String()],
    );
    for (final row in existingRows) {
      final alarm = Alarm.fromMap(row);
      cancelIds.add(alarm.id!);
      if (alarm.date != null) {
        await txn.insert('alarm_history', {
          'alarm_id': alarm.id,
          'scheduled_time': alarm.time,
          'scheduled_date': alarm.date!.toIso8601String(),
          'actual_ring_time': now.toIso8601String(),
          'dismiss_type': 'superseded',
          'snooze_count': 0,
          'shift_type': alarm.shiftType,
          'created_at': now.toIso8601String(),
          'day_offset': alarm.dayOffset,
        });
      }
      await txn.delete('alarms', where: 'id = ?', whereArgs: [alarm.id]);
    }

    // 2단계: 새로 계산해서 삽입 (+ 생성 이력 기록)
    final desired = computeDesiredFixedAlarmsForDate(
      date: date,
      schedule: schedule,
      allTemplates: allTemplates,
      now: now,
    );
    for (final item in desired) {
      final alarm = Alarm(
        time: item.time,
        date: item.dateTime,
        type: 'fixed',
        alarmTypeId: item.alarmTypeId,
        shiftType: item.shiftType,
        dayOffset: item.dayOffset,
      );
      final dbId = await txn.insert('alarms', alarm.toMap());
      await DatabaseService.instance.logAlarmCreation(txn, dbId, alarm, 'auto');
      scheduled.add(ScheduledAlarmRef(id: dbId, dateTime: item.dateTime, label: item.shiftType));
    }
  }

  return RegenerateAlarmsResult(cancelIds: cancelIds, scheduled: scheduled);
}

/// [regenerateFixedAlarmsForDatesTxn]을 새 트랜잭션 하나로 감싸서 실행하는
/// 편의 버전 - 알람 재계산만 단독으로 필요할 때(달력 일괄 배정 등) 씀.
Future<RegenerateAlarmsResult> regenerateFixedAlarmsForDates({
  required Database db,
  required ShiftSchedule schedule,
  required Set<DateTime> dates,
}) async {
  late final RegenerateAlarmsResult result;
  await db.transaction((txn) async {
    result = await regenerateFixedAlarmsForDatesTxn(txn: txn, schedule: schedule, dates: dates);
  });
  return result;
}
