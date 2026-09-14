// lib/services/backup_validator.dart
//
// ⭐ 2026-09-14 (출시전 감사 G4 #19, #11/#12 import 적용) - 복원이 DB·설정·OS를 하나라도 바꾸기 **전에** 백업 내용을 검증.
// 문제가 하나라도 있으면 아무것도 바꾸지 않는다. 임의 테이블/컬럼을 그대로 실행하지 않고 현재 스키마(PRAGMA table_info)에
// 있는 것만 허용한다.
//
// 버전별 유효 데이터를 기준으로 판단 - 불규칙 근무의 빈 pattern, 진행 중 수면 후보의 null end_time 같은 정상 상태를
// 손상으로 보지 않는다. 템플릿이 지금 근무 목록에 없는 근무명을 가리키는 것(과거 이름 변경 잔재)은 갱신 엔진이 무시하는
// 무해한 상태라 거부하지 않는다.

import 'package:sqflite/sqflite.dart';

import '../models/backup_payload.dart';
import '../models/shift_schedule.dart';
import 'backup_policy.dart';

class BackupValidationException implements Exception {
  final List<String> issues;
  BackupValidationException(this.issues);
  @override
  String toString() => 'BackupValidationException(${issues.join('; ')})';
}

class _Column {
  final String name;
  final String type;
  final bool required;
  const _Column(this.name, this.type, this.required);
}

class BackupValidator {
  const BackupValidator._();

  static final _hm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  static final _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// 문제 목록을 돌려줌(비어 있으면 통과). [db]는 현재 스키마 확인용 - 읽기만 함.
  static Future<List<String>> validate(BackupPayload payload, DatabaseExecutor db) async {
    final issues = <String>[];
    if (payload.schemaVersion < 1 || payload.schemaVersion > kBackupSchemaVersion) {
      issues.add('unsupported schemaVersion ${payload.schemaVersion}');
      return issues;
    }

    final schema = await _readSchema(db);

    for (final entry in payload.tables.entries) {
      final table = entry.key;
      if (kBackupSystemTables.contains(table)) {
        issues.add('system table $table');
        continue;
      }
      final columns = schema[table];
      if (columns == null) continue; // 옛 버전에만 있던 테이블 - 적용하지 않음
      for (var i = 0; i < entry.value.length; i++) {
        _checkRow(table, i, entry.value[i], columns, issues);
      }
    }
    if (issues.isNotEmpty) return issues;

    final tables = payload.tables;
    final alarmTypes = tables['alarm_types'] ?? const [];
    if (alarmTypes.isEmpty) issues.add('alarm_types missing');
    final typeIds = <int>{};
    for (final row in alarmTypes) {
      final id = row['id'];
      if (id is! int || !typeIds.add(id)) issues.add('alarm_types invalid/duplicate id $id');
    }

    _checkShiftSchedule(tables['shift_schedule'] ?? const [], issues);

    for (final row in tables['shift_alarm_templates'] ?? const <Map<String, dynamic>>[]) {
      final shift = row['shift_type'];
      if (shift is! String || shift.trim().isEmpty || shift.contains(',')) issues.add('template shift_type invalid');
      if (!_isHm(row['time'])) issues.add('template time invalid ${row['time']}');
      if (!_isOffset(row['day_offset'] ?? 0)) issues.add('template day_offset invalid');
      if (!typeIds.contains(row['alarm_type_id'])) issues.add('template alarm_type_id unknown ${row['alarm_type_id']}');
    }

    final overrideKeys = <String>{};
    for (final row in tables['alarm_overrides'] ?? const <Map<String, dynamic>>[]) {
      final action = row['action'];
      final typeId = row['alarm_type_id'];
      if (action == 'skip') {
        if (typeId != null) issues.add('override skip with alarm_type_id');
      } else if (action == 'set_type') {
        if (!typeIds.contains(typeId)) issues.add('override set_type unknown type $typeId');
      } else {
        issues.add('override action invalid $action');
      }
      if (!_isOffset(row['day_offset'] ?? 0)) issues.add('override day_offset invalid');
      if (!_isDateTime(row['slot_time']) || !_isDate(row['origin_date'])) issues.add('override time invalid');
      if (!overrideKeys.add('${row['slot_time']}|${row['shift_type']}|${row['day_offset'] ?? 0}')) {
        issues.add('override duplicate slot');
      }
    }

    for (final row in tables[kBackupAlarmsTable] ?? const <Map<String, dynamic>>[]) {
      if (row['type'] != 'custom') issues.add('alarms row not custom (${row['type']})');
      if (!_isDateTime(row['date'])) issues.add('alarms date invalid');
      if (!_isHm(row['time'])) issues.add('alarms time invalid');
      if (!typeIds.contains(row['alarm_type_id'])) issues.add('alarms alarm_type_id unknown');
      if (row['id'] is! int) issues.add('alarms id missing');
    }

    for (final row in tables['sleep_records'] ?? const <Map<String, dynamic>>[]) {
      final start = row['start_time'] is String ? DateTime.tryParse(row['start_time'] as String) : null;
      final endRaw = row['end_time'];
      if (start == null) {
        issues.add('sleep start_time invalid');
      } else if (endRaw != null) {
        final end = endRaw is String ? DateTime.tryParse(endRaw) : null;
        if (end == null || end.isBefore(start)) issues.add('sleep end_time invalid');
      }
    }

    for (final row in tables['date_schedules'] ?? const <Map<String, dynamic>>[]) {
      final start = row['start_minutes'];
      final duration = row['duration_minutes'];
      if (!_isDate(row['date'])) issues.add('date_schedules date invalid');
      if (start is! int || start < 0 || start >= 24 * 60) issues.add('date_schedules start invalid');
      if (duration is! int || duration < 0) issues.add('date_schedules duration invalid');
    }

    for (final entry in payload.preferences.entries) {
      final v = entry.value;
      final ok = v is bool || v is int || v is double || v is String || (v is List && v.every((e) => e is String));
      if (!ok) issues.add('preference ${entry.key} unsupported type');
    }
    return issues;
  }

  /// 근무 일정 행이 있는지(복원할 게 있는지). 검증과 별개로 화면이 "빈 백업" 안내에 씀.
  static bool hasSchedule(BackupPayload payload) => (payload.tables['shift_schedule'] ?? const []).isNotEmpty;

  static void _checkShiftSchedule(List<Map<String, dynamic>> rows, List<String> issues) {
    if (rows.length > 1) {
      issues.add('shift_schedule has ${rows.length} rows');
      return;
    }
    if (rows.isEmpty) return;
    final row = rows.first;
    final ShiftSchedule schedule;
    try {
      schedule = ShiftSchedule.fromMap(row);
    } catch (e) {
      issues.add('shift_schedule unreadable');
      return;
    }
    final names = <String>[];
    for (final name in schedule.shiftTypes) {
      final issue = validateShiftName(name, otherNames: names);
      if (issue != null) issues.add('shift name "$name" ${issue.name}');
      names.add(name.trim());
    }
    if (schedule.isRegular) {
      final pattern = schedule.pattern ?? const <String>[];
      final today = schedule.todayIndex;
      if (pattern.isEmpty) issues.add('regular schedule without pattern');
      if (today == null || today < 0 || today >= pattern.length) issues.add('today_index out of range');
      if (schedule.startDate == null) issues.add('regular schedule without start_date');
      for (final p in pattern) {
        if (p != kUnsetShiftSentinel && !schedule.shiftTypes.contains(p)) issues.add('pattern entry "$p" not in shift list');
      }
    }
  }

  static void _checkRow(String table, int index, Map<String, dynamic> row, Map<String, _Column> columns, List<String> issues) {
    for (final key in row.keys) {
      final column = columns[key];
      if (column == null) {
        issues.add('$table[$index] unknown column $key');
        continue;
      }
      final value = row[key];
      if (value == null) continue;
      final type = column.type.toUpperCase();
      final ok = type.contains('INT')
          ? value is int
          : (type.contains('REAL') || type.contains('FLOA') || type.contains('DOUB'))
              ? value is num
              : type.contains('TEXT') || type.contains('CHAR')
                  ? value is String
                  : (value is num || value is String);
      if (!ok) issues.add('$table[$index].$key type mismatch');
    }
    for (final column in columns.values) {
      if (column.required && row[column.name] == null) issues.add('$table[$index] missing ${column.name}');
    }
  }

  static Future<Map<String, Map<String, _Column>>> _readSchema(DatabaseExecutor db) async {
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final schema = <String, Map<String, _Column>>{};
    for (final t in tables) {
      final name = t['name'] as String;
      if (kBackupSystemTables.contains(name)) continue;
      final info = await db.rawQuery('PRAGMA table_info("$name")');
      schema[name] = {
        for (final c in info)
          c['name'] as String: _Column(
            c['name'] as String,
            (c['type'] as String?) ?? '',
            (c['notnull'] as int? ?? 0) == 1 && c['dflt_value'] == null && (c['pk'] as int? ?? 0) == 0,
          ),
      };
    }
    return schema;
  }

  static bool _isHm(Object? v) => v is String && _hm.hasMatch(v);
  static bool _isOffset(Object? v) => v is int && v >= -1 && v <= 1;
  static bool _isDateTime(Object? v) => v is String && DateTime.tryParse(v) != null;
  static bool _isDate(Object? v) {
    if (v is! String || !_dateKey.hasMatch(v)) return false;
    final parsed = DateTime.tryParse(v);
    return parsed != null && parsed.toIso8601String().startsWith(v);
  }
}
