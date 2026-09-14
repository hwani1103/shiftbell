-- T01 DRAFT / NOT_RUN. Empty disposable database only. See README.md.
-- Historical source: 65867d6cfe4b3d042d57f75f9516b14cedf2fbff:lib/services/database_service.dart
-- Origin: historical_onCreate; user_version=17.
BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS alarm_types(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  emoji TEXT NOT NULL,
  sound_file TEXT NOT NULL,
  volume REAL NOT NULL,
  vibration_strength INTEGER DEFAULT 2,
  is_preset INTEGER NOT NULL,
  duration INTEGER DEFAULT 10
);

CREATE TABLE IF NOT EXISTS shift_schedule(
  id INTEGER PRIMARY KEY,
  is_regular INTEGER NOT NULL,
  pattern TEXT,
  today_index INTEGER,
  shift_types TEXT NOT NULL,
  active_shift_types TEXT,
  start_date TEXT,
  shift_colors TEXT,
  assigned_dates TEXT,
  shift_durations TEXT
);

CREATE TABLE IF NOT EXISTS alarms(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  time TEXT NOT NULL,
  date TEXT,
  type TEXT NOT NULL,
  alarm_type_id INTEGER NOT NULL,
  shift_type TEXT,
  FOREIGN KEY (alarm_type_id) REFERENCES alarm_types(id)
);

CREATE TABLE IF NOT EXISTS shift_alarm_templates(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  shift_type TEXT NOT NULL,
  time TEXT NOT NULL,
  alarm_type_id INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS alarm_history(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alarm_id INTEGER NOT NULL,
  scheduled_time TEXT NOT NULL,
  scheduled_date TEXT NOT NULL,
  actual_ring_time TEXT NOT NULL,
  dismiss_type TEXT NOT NULL,
  snooze_count INTEGER DEFAULT 0,
  shift_type TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS date_memos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  memo_text TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_date_memos_date ON date_memos(date);

CREATE TABLE IF NOT EXISTS alarm_creation_log(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alarm_id INTEGER NOT NULL,
  scheduled_date TEXT NOT NULL,
  scheduled_time TEXT NOT NULL,
  shift_type TEXT,
  alarm_type_id INTEGER,
  source TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_creation_log_alarm_id ON alarm_creation_log(alarm_id);

CREATE INDEX IF NOT EXISTS idx_creation_log_created_at ON alarm_creation_log(created_at);

CREATE TABLE IF NOT EXISTS date_overtime(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  minutes INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_date_overtime_date ON date_overtime(date);

CREATE TABLE IF NOT EXISTS friends(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  owner_id TEXT NOT NULL UNIQUE,
  data_json TEXT,
  added_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Synthetic user data; intentionally edited preset settings, not factory defaults.
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, vibration_strength, is_preset, duration) VALUES (1, 'Sound', 'S', 'alarmbell1', 0.43, 1, 1, 7);
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, vibration_strength, is_preset, duration) VALUES (2, 'Vibrate', 'V', '', 0.0, 1, 1, 7);
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, vibration_strength, is_preset, duration) VALUES (3, 'Silent', 'M', '', 0.0, 1, 1, 7);
INSERT INTO alarm_types (id, name, emoji, sound_file, volume, vibration_strength, is_preset, duration) VALUES (41, 'Personal', 'P', 'alarmbell2', 0.35, 1, 0, 7);
INSERT INTO shift_schedule (id, is_regular, pattern, today_index, shift_types, active_shift_types, start_date, shift_colors, assigned_dates, shift_durations) VALUES (1, 1, 'Day,Night,Off', 0, 'Day,Night,Off', 'Day,Night', '2026-09-14T00:00:00.000', '{"Day":4280391411,"Night":4288423856}', '{"2026-09-16":"Night"}', '{"Day":480,"Night":600}');
INSERT INTO alarms (id, time, date, type, alarm_type_id, shift_type) VALUES (101, '06:30', '2026-09-15T06:30:00.000', 'fixed', 1, 'Day');
INSERT INTO alarms (id, time, date, type, alarm_type_id, shift_type) VALUES (102, '08:10', '2026-09-15T08:10:00.000', 'custom', 41, NULL);
INSERT INTO alarms (id, time, date, type, alarm_type_id, shift_type) VALUES (103, '06:35', '2026-09-15T06:35:00.000', 'snoozed', 2, 'Day');
INSERT INTO shift_alarm_templates (id, shift_type, time, alarm_type_id) VALUES (201, 'Day', '06:30', 1);
INSERT INTO shift_alarm_templates (id, shift_type, time, alarm_type_id) VALUES (202, 'Night', '22:30', 41);
INSERT INTO alarm_history (id, alarm_id, scheduled_time, scheduled_date, actual_ring_time, dismiss_type, snooze_count, shift_type, created_at) VALUES (301, 999, '06:30', '2026-08-10', '2026-08-10T06:30:00.000', 'snoozed', 2, 'Day', '2026-08-10T06:30:00.000');
INSERT INTO date_memos (id, date, memo_text, order_index, created_at) VALUES (401, '2026-09-15', 'Shift handover / O''Brien', 0, '2026-09-14T05:00:00.000');
INSERT INTO date_memos (id, date, memo_text, order_index, created_at) VALUES (402, '2026-09-15', 'Bring uniform', 1, '2026-09-14T05:00:00.000');
INSERT INTO alarm_creation_log (id, alarm_id, scheduled_date, scheduled_time, shift_type, alarm_type_id, source, created_at) VALUES (501, 999, '2026-08-10', '06:30', 'Day', 1, 'flutter', '2026-08-10T06:30:00.000');
INSERT INTO date_overtime (id, date, minutes, updated_at) VALUES (601, '2026-09-14', 90, '2026-09-14T05:00:00.000');
INSERT INTO friends (id, name, owner_id, data_json, added_at, updated_at) VALUES (701, 'Cached coworker', 'fixture-owner-a', '{"isRegular":true,"pattern":["Day","Night","Off"],"shiftTypes":["Day","Night","Off"],"todayIndex":0,"startDate":"2026-09-14T00:00:00.000"}', '2026-08-10T06:30:00.000', '2026-09-14T05:00:00.000');
INSERT INTO friends (id, name, owner_id, data_json, added_at, updated_at) VALUES (702, 'Not fetched', 'fixture-owner-b', NULL, '2026-09-14T05:00:00.000', '2026-09-14T05:00:00.000');

PRAGMA user_version = 17;
COMMIT;
