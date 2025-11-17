import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/alarm_type.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import '../models/alarm_template.dart';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();
  
  static Database? _database;
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'shiftbell.db');
    
    return await openDatabase(
      path,
      version: 2,  // ⭐ 버전 업
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // alarm_types 테이블
    await db.execute('''
      CREATE TABLE alarm_types(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sound_file TEXT NOT NULL,
        volume REAL NOT NULL,
        is_preset INTEGER NOT NULL
      )
    ''');
    
    // shift_schedule 테이블 (⭐ shift_colors 추가)
    await db.execute('''
      CREATE TABLE shift_schedule(
        id INTEGER PRIMARY KEY,
        is_regular INTEGER NOT NULL,
        pattern TEXT,
        today_index INTEGER,
        shift_types TEXT NOT NULL,
        start_date TEXT,
        shift_colors TEXT
      )
    ''');

    // alarms 테이블
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
    
    // ⭐ shift_alarm_templates 테이블 (신규)
    await db.execute('''
      CREATE TABLE shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');
    
    // 기본 알람 타입 3개 삽입
    for (var type in AlarmType.presets) {
      await db.insert('alarm_types', type.toMap());
    }
    
    print('✅ 데이터베이스 초기화 완료');
  }
  
  // ⭐ 버전 업그레이드 (기존 DB에 컬럼/테이블 추가)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // shift_colors 컬럼 추가
      await db.execute('ALTER TABLE shift_schedule ADD COLUMN shift_colors TEXT');
      
      // shift_alarm_templates 테이블 추가
      await db.execute('''
        CREATE TABLE shift_alarm_templates(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_type TEXT NOT NULL,
          time TEXT NOT NULL,
          alarm_type_id INTEGER NOT NULL
        )
      ''');
      
      print('✅ DB 업그레이드 완료 (v$oldVersion → v$newVersion)');
    }
  }
  
  // === AlarmType CRUD ===
  
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
  
  // === Alarm CRUD ===
  
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
  
  // === AlarmTemplate CRUD (⭐ 신규) ===
  
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
}