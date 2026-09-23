// lib/models/custom_alarm_preset.dart
//
// ⭐ 2026-09-23 (1.0.24 B) - 달력 상단 "커스텀 알람" 5칸. 한 칸 = 시각 + 알람 종류(alarm_types의 1=소리+진동, 2=진동, 3=무음).
// 이 값은 "재사용할 틀"일 뿐이고, 날짜에 할당하는 순간 alarms 테이블에 type='custom' 1회 알람이 생긴다
// (custom_alarm_service.dart). 틀 자체는 SharedPreferences(설정값)라 DB 마이그레이션이 필요 없고,
// 백업·복원에는 설정 키로 자동 포함된다(backup_policy.dart kBackupPreferenceTypes에 등록).

import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;

/// 프리셋 칸 수(요구사항: 5개 고정).
const int kCustomAlarmPresetCount = 5;

/// SharedPreferences 키 - JSON 문자열(길이 5 배열).
const String kCustomAlarmPresetsPrefKey = 'custom_alarm_presets';

class CustomAlarmPreset {
  /// 'HH:mm'. null이면 빈 칸.
  final String? time;
  final int alarmTypeId;

  const CustomAlarmPreset({this.time, this.alarmTypeId = 1});

  static const empty = CustomAlarmPreset();

  bool get isEmpty => time == null;

  TimeOfDay? get timeOfDay {
    final t = time;
    if (t == null) return null;
    final parts = t.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  CustomAlarmPreset copyWith({String? time, bool clearTime = false, int? alarmTypeId}) => CustomAlarmPreset(
        time: clearTime ? null : (time ?? this.time),
        alarmTypeId: alarmTypeId ?? this.alarmTypeId,
      );

  Map<String, dynamic> toJson() => {'time': time, 'alarmTypeId': alarmTypeId};

  /// 손상·편집된 값에도 앱이 죽지 않게 - 알 수 없는 값은 빈 칸/기본 종류로.
  static CustomAlarmPreset fromJson(Object? json) {
    if (json is! Map) return empty;
    final rawType = json['alarmTypeId'];
    final type = rawType is int && rawType >= 1 && rawType <= 3 ? rawType : 1;
    final rawTime = json['time'];
    final preset = CustomAlarmPreset(time: rawTime is String ? rawTime : null, alarmTypeId: type);
    return preset.time != null && preset.timeOfDay == null ? CustomAlarmPreset(alarmTypeId: type) : preset;
  }

  /// 저장 문자열 → 항상 길이 [kCustomAlarmPresetCount]인 목록.
  static List<CustomAlarmPreset> decodeList(String? raw) {
    List<Object?> items = const [];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) items = decoded;
      } catch (_) {}
    }
    return List<CustomAlarmPreset>.generate(
      kCustomAlarmPresetCount,
      (i) => i < items.length ? fromJson(items[i]) : empty,
    );
  }

  static String encodeList(List<CustomAlarmPreset> presets) =>
      jsonEncode(presets.take(kCustomAlarmPresetCount).map((p) => p.toJson()).toList());

  @override
  bool operator ==(Object other) =>
      other is CustomAlarmPreset && other.time == time && other.alarmTypeId == alarmTypeId;

  @override
  int get hashCode => Object.hash(time, alarmTypeId);
}
