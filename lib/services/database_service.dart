// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import '../models/alarm_type.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import '../models/alarm_template.dart';
import 'dart:convert';
import '../models/alarm_history.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  static Database? _database;
  static bool _isInitializing = false;
  static const platform = MethodChannel('com.example.shiftbell/alarm');

  // ⭐ Race Condition 방지: 동시 초기화 요청 시 대기
  Future<Database> get database async {
    if (_database != null) return _database!;

    // 이미 초기화 중이면 완료될 때까지 대기
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (_database != null) return _database!;
    }

    _isInitializing = true;
    try {
      _database = await _initDatabase();
      return _database!;
    } finally {
      _isInitializing = false;
    }
  }
  
  Future<Database> _initDatabase() async {
    // ⭐ Device Protected 경로 사용
    String path;
    try {
      final deviceProtectedPath = await platform.invokeMethod('getDeviceProtectedStoragePath');
      path = deviceProtectedPath as String;
      print('✅ Device Protected DB 경로: $path');
    } catch (e) {
      // Fallback: 일반 경로
      path = join(await getDatabasesPath(), 'shiftbell.db');
      print('⚠️ 일반 DB 경로 사용: $path');
    }
    
    return await openDatabase(
      path,
      version: 10,  // v10: sound_file 강제 업데이트
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        var result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='shift_schedule'"
        );
        
        if (result.isEmpty) {
          print('⚠️ 테이블 없음 - 재생성 중...');
          await _onCreate(db, 4);
          print('✅ 테이블 생성 완료');
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE alarm_types(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sound_file TEXT NOT NULL,
        volume REAL NOT NULL,
        vibration_strength INTEGER DEFAULT 2,
        is_preset INTEGER NOT NULL,
        duration INTEGER DEFAULT 10
      )
    ''');
    
    await db.execute('''
      CREATE TABLE shift_schedule(
        id INTEGER PRIMARY KEY,
        is_regular INTEGER NOT NULL,
        pattern TEXT,
        today_index INTEGER,
        shift_types TEXT NOT NULL,
        active_shift_types TEXT,
        start_date TEXT,
        shift_colors TEXT,
        assigned_dates TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE alarms(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT NOT NULL,
        date TEXT,
        type TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL,
        shift_type TEXT,
        FOREIGN KEY (alarm_type_id) REFERENCES alarm_types(id)
      )
    ''');
    
    await db.execute('''
      CREATE TABLE shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');

    // ⭐ 신규: 알람 이력 테이블
  await db.execute('''
    CREATE TABLE alarm_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      alarm_id INTEGER NOT NULL,
      scheduled_time TEXT NOT NULL,
      scheduled_date TEXT NOT NULL,
      actual_ring_time TEXT NOT NULL,
      dismiss_type TEXT NOT NULL,
      snooze_count INTEGER DEFAULT 0,
      shift_type TEXT,
      created_at TEXT NOT NULL
    )
  ''');
    
    for (var type in AlarmType.presets) {
      await db.insert('alarm_types', type.toMap());
    }
    
    print('✅ 데이터베이스 초기화 완료');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE shift_schedule ADD COLUMN shift_colors TEXT');
    
    await db.execute('''
      CREATE TABLE shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');
    
    print('✅ DB 업그레이드 완료 (v$oldVersion → v2)');
  }
  
  if (oldVersion < 3) {
    await db.execute('ALTER TABLE shift_schedule ADD COLUMN assigned_dates TEXT');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v3)');
  }
  
  if (oldVersion < 4) {
    await db.execute('ALTER TABLE shift_schedule ADD COLUMN active_shift_types TEXT');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v4)');
  }

  if (oldVersion < 5) {
    await db.execute('''
      CREATE TABLE alarm_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL,
        scheduled_time TEXT NOT NULL,
        scheduled_date TEXT NOT NULL,
        actual_ring_time TEXT NOT NULL,
        dismiss_type TEXT NOT NULL,
        snooze_count INTEGER DEFAULT 0,
        shift_type TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v5)');
  }
  
  if (oldVersion < 6) {
    await db.execute('ALTER TABLE alarm_types ADD COLUMN duration INTEGER DEFAULT 10');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v6)');
  }

  if (oldVersion < 7) {
    await db.execute('ALTER TABLE alarm_types ADD COLUMN vibration_strength INTEGER DEFAULT 2');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v7)');
  }

  // v8: 기본값 변경 (알람벨1, 70%, 강하게, 3분)
  if (oldVersion < 8) {
    // 소리 타입 (id=1): alarmbell1, 70%, 강하게, 3분
    await db.execute('''
      UPDATE alarm_types SET
        sound_file = 'alarmbell1',
        volume = 0.7,
        vibration_strength = 3,
        duration = 3
      WHERE id = 1
    ''');

    // 진동 타입 (id=2): 강하게, 3분
    await db.execute('''
      UPDATE alarm_types SET
        vibration_strength = 3,
        duration = 3
      WHERE id = 2
    ''');

    // 무음 타입 (id=3): 3분
    await db.execute('''
      UPDATE alarm_types SET
        duration = 3
      WHERE id = 3
    ''');

    print('✅ DB 업그레이드 완료 (v$oldVersion → v8): 기본값 마이그레이션');
  }

  // v9: 진동/무음 기본값 재적용 (강하게, 3분)
  if (oldVersion < 9) {
    // 진동 타입 (id=2): 강하게, 3분
    await db.execute('''
      UPDATE alarm_types SET
        vibration_strength = 3,
        duration = 3
      WHERE id = 2
    ''');

    // 무음 타입 (id=3): 3분
    await db.execute('''
      UPDATE alarm_types SET
        duration = 3
      WHERE id = 3
    ''');

    print('✅ DB 업그레이드 완료 (v$oldVersion → v9): 진동/무음 기본값 재적용');
  }

  // v10: 소리 타입 sound_file 강제 업데이트 (loud → alarmbell1)
  if (oldVersion < 10) {
    await db.execute('''
      UPDATE alarm_types SET
        sound_file = 'alarmbell1',
        volume = 0.7,
        vibration_strength = 3,
        duration = 3
      WHERE id = 1
    ''');

    // 진동/무음도 재확인
    await db.execute('''
      UPDATE alarm_types SET
        vibration_strength = 3,
        duration = 3
      WHERE id = 2
    ''');

    await db.execute('''
      UPDATE alarm_types SET
        duration = 3
      WHERE id = 3
    ''');

    print('✅ DB 업그레이드 완료 (v$oldVersion → v10): sound_file=alarmbell1 강제 적용');
  }
} 
  
  // === 기존 메서드들 유지 ===
  
  Future<List<AlarmType>> getAllAlarmTypes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('alarm_types');
    return maps.map((map) => AlarmType.fromMap(map)).toList();
  }
  
  Future<AlarmType?> getAlarmType(int id) async {
    final db = await database;
    final maps = await db.query(
      'alarm_types',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return AlarmType.fromMap(maps.first);
  }
  
  Future<int> insertAlarmType(AlarmType type) async {
    final db = await database;
    return await db.insert('alarm_types', type.toMap());
  }
  
  Future<int> deleteAlarmType(int id) async {
    final db = await database;
    return await db.delete(
      'alarm_types',
      where: 'id = ? AND is_preset = 0',
      whereArgs: [id],
    );
  }
  
  Future<int> insertAlarm(Alarm alarm) async {
    final db = await database;
    return await db.insert('alarms', alarm.toMap());
  }
  
  Future<List<Alarm>> getAllAlarms() async {
    final db = await database;
    final maps = await db.query('alarms');
    return maps.map((map) => Alarm.fromMap(map)).toList();
  }
  
  Future<List<Alarm>> getAlarmsByDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final maps = await db.query(
      'alarms',
      where: 'date LIKE ?',
      whereArgs: ['$dateStr%'],
    );
    return maps.map((map) => Alarm.fromMap(map)).toList();
  }
  
  Future<List<Alarm>> getNextAlarms({int limit = 10}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final maps = await db.query(
      'alarms',
      where: 'date > ?',
      whereArgs: [now],
      orderBy: 'date ASC',
      limit: limit,
    );
    return maps.map((map) => Alarm.fromMap(map)).toList();
  }
  
  Future<int> updateAlarm(Alarm alarm) async {
    final db = await database;
    return await db.update(
      'alarms',
      alarm.toMap(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }
  
  Future<int> deleteAlarm(int id) async {
    final db = await database;
    return await db.delete(
      'alarms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<int> saveShiftSchedule(ShiftSchedule schedule) async {
    final db = await database;
    return await db.insert(
      'shift_schedule',
      schedule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ShiftSchedule?> getShiftSchedule() async {
    final db = await database;
    final maps = await db.query('shift_schedule', limit: 1);
    if (maps.isEmpty) return null;
    return ShiftSchedule.fromMap(maps.first);
  }

  Future<int> updateShiftSchedule(ShiftSchedule schedule) async {
    final db = await database;
    return await db.update(
      'shift_schedule',
      schedule.toMap(),
      where: 'id = ?',
      whereArgs: [schedule.id],
    );
  }

  Future<void> insertAlarmsInBatch(List<Alarm> alarms) async {
    final db = await database;
    final batch = db.batch();
    
    for (var alarm in alarms) {
      batch.insert('alarms', alarm.toMap());
    }
    
    await batch.commit(noResult: true);
    print('✅ ${alarms.length}개 알람 일괄 등록 완료');
  }

  Future<void> deleteAllAlarms() async {
    final db = await database;
    await db.delete('alarms');
    print('🗑️ 모든 알람 삭제 완료');
  }
  
  Future<int> insertAlarmTemplate({
    required String shiftType,
    required String time,
    required int alarmTypeId,
  }) async {
    final db = await database;
    return await db.insert('shift_alarm_templates', {
      'shift_type': shiftType,
      'time': time,
      'alarm_type_id': alarmTypeId,
    });
  }
  
  Future<List<AlarmTemplate>> getAlarmTemplates(String shiftType) async {
    final db = await database;
    final maps = await db.query(
      'shift_alarm_templates',
      where: 'shift_type = ?',
      whereArgs: [shiftType],
    );
    return maps.map((m) => AlarmTemplate.fromMap(m)).toList();
  }
  
  Future<List<AlarmTemplate>> getAllAlarmTemplates() async {
    final db = await database;
    final maps = await db.query('shift_alarm_templates');
    return maps.map((m) => AlarmTemplate.fromMap(m)).toList();
  }
  
  Future<int> deleteAlarmTemplate(int id) async {
    final db = await database;
    return await db.delete(
      'shift_alarm_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> deleteAllAlarmTemplates() async {
    final db = await database;
    await db.delete('shift_alarm_templates');
    print('🗑️ 모든 알람 템플릿 삭제 완료');
  }

  // ⭐ 신규: 알람 이력 조회
Future<List<AlarmHistory>> getAlarmHistory({int limit = 50}) async {
  final db = await database;
  final maps = await db.query(
    'alarm_history',
    orderBy: 'created_at DESC',
    limit: limit,
  );
  return maps.map((map) => AlarmHistory.fromMap(map)).toList();
}

// ⭐ 신규: 특정 날짜 이력 조회
Future<List<AlarmHistory>> getAlarmHistoryByDate(DateTime date) async {
  final db = await database;
  final dateStr = date.toIso8601String().split('T')[0];
  final maps = await db.query(
    'alarm_history',
    where: 'scheduled_date LIKE ?',
    whereArgs: ['$dateStr%'],
    orderBy: 'actual_ring_time DESC',
  );
  return maps.map((map) => AlarmHistory.fromMap(map)).toList();
}

// ⭐ 신규: 이력 통계
Future<Map<String, dynamic>> getAlarmStatistics() async {
  final db = await database;
  
  final total = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM alarm_history')
  ) ?? 0;
  
  final swiped = Sqflite.firstIntValue(
    await db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE dismiss_type = 'swiped'")
  ) ?? 0;
  
  final snoozed = Sqflite.firstIntValue(
    await db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE dismiss_type = 'snoozed'")
  ) ?? 0;
  
  final timeout = Sqflite.firstIntValue(
    await db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE dismiss_type = 'timeout'")
  ) ?? 0;
  
  final avgSnooze = Sqflite.firstIntValue(
    await db.rawQuery('SELECT AVG(snooze_count) FROM alarm_history WHERE snooze_count > 0')
  ) ?? 0;
  
  return {
    'total': total,
    'swiped': swiped,
    'snoozed': snoozed,
    'timeout': timeout,
    'avgSnooze': avgSnooze,
  };
}

// ⭐ 신규: 오래된 이력 삭제 (한 달 이상)
Future<void> deleteOldHistory(DateTime beforeDate) async {
  final db = await database;
  final dateStr = beforeDate.toIso8601String();
  await db.delete(
    'alarm_history',
    where: 'created_at < ?',
    whereArgs: [dateStr],
  );
}

// ⭐ 신규: 모든 이력 삭제
Future<void> clearAlarmHistory() async {
  final db = await database;
  await db.delete('alarm_history');
}

}