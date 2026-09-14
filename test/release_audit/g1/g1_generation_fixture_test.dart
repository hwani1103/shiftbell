// 출시전 감사 G1 #26(P1)/#31 - Dart 생성 계산을 T11a 독립 fixture와 비교
// (test/release_audit/g1/fixtures/generation_cases.json, Codex 작성 - contracts §2·v4 #26/#31만 근거).
// Kotlin 쪽 같은 fixture: android/app/src/test/.../G1GenerationFixtureTest.kt - 두 구현이 같은 기대값을 내야 함.
//
// 창(오늘~오늘+9일)의 각 울림 날짜에 computeDesiredFixedAlarmsForDate를 호출해 합친 결과를 정규 슬롯
// (slot_time, shift_type, day_offset, alarm_type_id)로 투영해 비교. fixture 시각은 기기 로컬 시각으로 해석
// (Asia/Seoul 기준 fixture - 창 안에 서머타임 전환이 없는 시간대에서는 결과가 같음).
// 조회 실패·diff·보호 대상 케이스는 Kotlin 엔진 테스트(G1GenerationEngineTest)가 맡음.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/alarm_limits.dart';
import 'package:shiftbell/models/alarm_template.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/alarm_generation_service.dart';

void main() {
  final root = jsonDecode(File('test/release_audit/g1/fixtures/generation_cases.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (root['cases'] as List).cast<Map<String, dynamic>>();
  final reviewRoot = jsonDecode(
    File('test/release_audit/g1/fixtures/review_fixture_additions.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  cases.addAll((reviewRoot['cases'] as List).cast<Map<String, dynamic>>());

  ShiftSchedule scheduleOf(Map<String, dynamic> s) {
    final assigned = (s['assigned_dates'] as Map?)?.map((k, v) => MapEntry(k as String, v as String));
    if (s['mode'] == 'regular') {
      final pattern = (s['pattern'] as List).cast<String>();
      return ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: s['today_index'] as int,
        shiftTypes: pattern.toSet().toList(),
        startDate: DateTime.parse(s['start_date'] as String),
        assignedDates: assigned,
      );
    }
    return ShiftSchedule(isRegular: false, shiftTypes: const [], assignedDates: assigned);
  }

  test('fixture 창 크기가 제품 상수와 같다', () {
    expect(root['window_days_including_today'], kAlarmRefreshWindowDays);
  });

  for (final c in cases) {
    if (c['template_query_result'] == 'error' || c['expected_generation_slots'] == null) continue;

    test('#26 #31 생성 계산 fixture ${c['id']}', () {
      final now = DateTime.parse(c['now'] as String);
      final templates = (c['templates'] as List).cast<Map<String, dynamic>>().map((t) => AlarmTemplate(
            shiftType: t['shift_type'] as String,
            time: t['time'] as String,
            alarmTypeId: t['alarm_type_id'] as int,
            dayOffset: t['day_offset'] as int,
          )).toList();
      final overrides = {
        for (final o in (c['overrides'] as List).cast<Map<String, dynamic>>())
          alarmSlotKey(o['slot_time'] as String, o['shift_type'] as String, o['day_offset'] as int):
              AlarmOverrideEntry(action: o['action'] as String, alarmTypeId: o['alarm_type_id'] as int?),
      };
      final schedule = scheduleOf(c['schedule'] as Map<String, dynamic>);

      final actual = <String>[];
      for (var i = 0; i < kAlarmRefreshWindowDays; i++) {
        final date = DateTime(now.year, now.month, now.day + i);
        for (final a in computeDesiredFixedAlarmsForDate(
          date: date,
          schedule: schedule,
          allTemplates: templates,
          now: now,
          overrides: overrides,
        )) {
          actual.add('${alarmSlotTime(a.dateTime)}|${a.shiftType}|${a.dayOffset}|type=${a.alarmTypeId}');
        }
      }
      final expected = (c['expected_generation_slots'] as List).cast<Map<String, dynamic>>()
          .map((e) => '${e['slot_time']}|${e['shift_type']}|${e['day_offset']}|type=${e['alarm_type_id']}')
          .toList();

      expect(actual..sort(), expected..sort());
    });
  }
}
