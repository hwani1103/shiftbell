import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/models/backup_payload.dart';
import 'package:shiftbell/services/backup_validator.dart';

void main() {
  test('both repeated-hour history instants survive existing backup format', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('CREATE TABLE alarm_types(id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('CREATE TABLE alarm_history(alarm_id INTEGER, scheduled_date TEXT, scheduled_time TEXT, actual_ring_time TEXT, created_at TEXT, dismiss_type TEXT)');
      await db.execute('CREATE TABLE alarm_creation_log(alarm_id INTEGER, scheduled_date TEXT, scheduled_time TEXT, created_at TEXT, source TEXT)');
      final history = [
        for (final offset in ['-04:00', '-05:00']) {
          'alarm_id': 7,
          'scheduled_date': '2026-11-01T01:04:00$offset',
          'scheduled_time': '01:04',
          'actual_ring_time': '2026-11-01T01:04:02$offset',
          'created_at': '2026-11-01T01:04:02$offset',
          'dismiss_type': 'snoozed',
        },
      ];
      final payload = BackupPayload(schemaVersion: kBackupSchemaVersion,
          exportedAt: DateTime.utc(2026, 11, 2), appVersionName: '1.0.23',
          appVersionCode: 25, tables: {
            'alarm_types': [{'id': 1, 'name': 'Sound'}],
            'alarm_history': history,
            'alarm_creation_log': [for (final row in history) {
              'alarm_id': row['alarm_id'], 'scheduled_date': row['scheduled_date'],
              'scheduled_time': row['scheduled_time'], 'created_at': row['created_at'],
              'source': 'snoozed',
            }],
          }, preferences: {});
      final restored = BackupPayload.decode(payload.encode());
      expect(await BackupValidator.validate(restored, db), isEmpty);
      expect(restored.tables['alarm_history'], history);
      final dates = restored.tables['alarm_history']!
          .map((r) => DateTime.parse(r['scheduled_date'] as String)).toList();
      expect(dates[1].difference(dates[0]), const Duration(hours: 1));
    } finally {
      await db.close();
    }
  });
}
