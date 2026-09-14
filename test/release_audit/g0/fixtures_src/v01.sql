-- T01 DRAFT / NOT_RUN. Empty disposable database only. See README.md.
-- Historical source: 059bd255ac925dad6d338811ca25b5be0af6eedc:lib/services/database_service.dart
-- Origin: reconstructed; user_version=1.
BEGIN TRANSACTION;

CREATE TABLE alarm_types(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  emoji TEXT NOT NULL,
  sound_file TEXT NOT NULL,
  volume REAL NOT NULL,
  is_preset INTEGER NOT NULL
);

CREATE TABLE shift_schedule(
  id INTEGER PRIMARY KEY,
  is_regular INTEGER NOT NULL,
  pattern TEXT,
  today_index INTEGER,
  shift_types TEXT NOT NULL,
  start_date TEXT
);

CREATE TABLE alarms(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  time TEXT NOT NULL,
  date TEXT,
  type TEXT NOT NULL,
  alarm_type_id INTEGER NOT NULL,
  shift_type TEXT,
  FOREIGN KEY (alarm_type_id) REFERENCES alarm_types(id)
);

-- Synthetic user data; intentionally edited preset settings, not factory defaults.
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, is_preset) VALUES (1, 'Sound', 'S', 'alarmbell1', 0.43, 1);
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, is_preset) VALUES (2, 'Vibrate', 'V', '', 0.0, 1);
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, is_preset) VALUES (3, 'Silent', 'M', '', 0.0, 1);
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, is_preset) VALUES (41, 'Personal', 'P', 'alarmbell2', 0.35, 0);
INSERT INTO shift_schedule (id, is_regular, pattern, today_index, shift_types, start_date) VALUES (1, 1, 'Day,Night,Off', 0, 'Day,Night,Off', '2026-09-14T00:00:00.000');
INSERT INTO alarms (id, time, date, type, alarm_type_id, shift_type) VALUES (101, '06:30', '2026-09-15T06:30:00.000', 'fixed', 1, 'Day');
INSERT INTO alarms (id, time, date, type, alarm_type_id, shift_type) VALUES (102, '08:10', '2026-09-15T08:10:00.000', 'custom', 41, NULL);
INSERT INTO alarms (id, time, date, type, alarm_type_id, shift_type) VALUES (103, '06:35', '2026-09-15T06:35:00.000', 'snoozed', 2, 'Day');

PRAGMA user_version = 1;
COMMIT;
