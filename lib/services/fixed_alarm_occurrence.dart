import 'package:sqflite/sqflite.dart';

/// An occurrence is a nominal local slot, shift and day offset, never a DB ID
/// or an epoch. Keep this query/terminal policy aligned with FixedAlarmOccurrence.
const _terminalKinds = "'swiped','timeout','snoozed',"
    "'snooze_skipped_existing_alarm','superseded_by_next_alarm'";

String fixedOccurrenceKey(String slot, String shift, int offset) =>
    '$slot|$shift|$offset';

const _historySelection = '''
    SELECT fixed_slot_time AS slot_time, shift_type, day_offset
    FROM alarm_history
    WHERE fixed_slot_time >= ? AND fixed_slot_time < ?
      AND dismiss_type IN ($_terminalKinds)
    UNION
    SELECT substr(h.scheduled_date, 1, 16) || ':00' AS slot_time,
      h.shift_type, h.day_offset
    FROM alarm_history h
    WHERE h.fixed_slot_time IS NULL
      AND h.scheduled_date >= ? AND h.scheduled_date < ?
      AND h.dismiss_type IN ($_terminalKinds)
      AND EXISTS (
        SELECT 1 FROM alarm_creation_log c
        WHERE c.alarm_id = h.alarm_id AND c.source = 'auto'
          AND substr(c.scheduled_date, 1, 19) = substr(h.scheduled_date, 1, 19)
          AND c.scheduled_time = h.scheduled_time
          AND c.shift_type = h.shift_type AND c.day_offset = h.day_offset
      )
      AND NOT EXISTS (
        SELECT 1 FROM alarm_creation_log c
        WHERE c.alarm_id = h.alarm_id AND c.source != 'auto'
          AND substr(c.scheduled_date, 1, 19) = substr(h.scheduled_date, 1, 19)
          AND c.scheduled_time = h.scheduled_time
          AND c.shift_type = h.shift_type AND c.day_offset = h.day_offset
      )
  ''';

/// Migrate reliable old/imported history before it can be cleared by the user.
/// Call inside the caller's transaction when combined with another write.
Future<void> materializeConsumedHistory(DatabaseExecutor db,
    {String start = '0000', String end = '9999'}) async {
  await db.rawInsert('''INSERT OR IGNORE INTO fixed_alarm_consumptions
    (slot_time, shift_type, day_offset, recorded_at)
    SELECT slot_time, shift_type, day_offset, ? FROM ($_historySelection)
    WHERE shift_type IS NOT NULL''',
    [DateTime.now().toUtc().toIso8601String(), start, end, start, end]);
}

Future<Set<String>> readConsumedFixedOccurrences(
    DatabaseExecutor db, String start, String end) async {
  await materializeConsumedHistory(db, start: start, end: end);
  final rows = await db.query('fixed_alarm_consumptions',
      columns: ['slot_time', 'shift_type', 'day_offset'],
      where: 'slot_time >= ? AND slot_time < ?', whereArgs: [start, end]);
  return {
    for (final row in rows)
      if (row['slot_time'] is String && row['shift_type'] is String)
        fixedOccurrenceKey(row['slot_time'] as String,
            row['shift_type'] as String, row['day_offset'] as int),
  };
}

Future<void> recordFixedConsumption(DatabaseExecutor db,
    Map<String, Object?> row, String dismissType) async {
  if (!const {'swiped', 'timeout', 'snoozed', 'snooze_skipped_existing_alarm',
    'superseded_by_next_alarm'}.contains(dismissType)) return;
  final slot = fixedSlotFromRow(row);
  final shift = row['shift_type'] as String?;
  if (slot == null || shift == null) return;
  await db.insert('fixed_alarm_consumptions', {
    'slot_time': slot, 'shift_type': shift, 'day_offset': row['day_offset'] ?? 0,
    'recorded_at': DateTime.now().toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

/// Carry an explicit origin through snoozes. Only legacy fixed rows may use
/// their stored wall clock as fallback; a custom/snoozed date is not an origin.
String? fixedSlotFromRow(Map<String, Object?> row) {
  if (row['type'] != 'fixed' && row['type'] != 'snoozed') return null;
  final explicit = row['fixed_slot_time'] as String?;
  if (explicit != null) return explicit;
  final date = row['date'] as String?;
  if (row['type'] != 'fixed' || date == null || date.length < 16) return null;
  return '${date.substring(0, 16)}:00';
}
