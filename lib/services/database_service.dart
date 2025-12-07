// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import '../models/alarm_type.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import '../models/alarm_template.dart';
import 'dart:convert';
import 'dart:async';
import '../models/alarm_history.dart';
import '../models/date_memo.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  static Database? _database;
  static Completer<Database>? _initCompleter;
  static const platform = MethodChannel('com.example.shiftbell/alarm');

  // ⭐ HIGH-2 수정: Completer 패턴으로 Race Condition 완전 해결
  Future<Database> get database async {
    if (_database != null) return _database!;

    // 이미 초기화 중이면 같은 Future를 기다림
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
      return _database!;
    } catch (e, stackTrace) {
      _initCompleter!.completeError(e, stackTrace);
      rethrow;
    } finally {
      _initCompleter = null;
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
      version: 12,  // v12: date_memos 테이블 추가
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

    // ⭐ 신규: 날짜별 메모 테이블
  await db.execute('''
    CREATE TABLE date_memos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      memo_text TEXT NOT NULL,
      order_index INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute('CREATE INDEX idx_date_memos_date ON date_memos(date)');

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

  // v11: 진동/무음 기본값 최종 강제 적용
  if (oldVersion < 11) {
    await db.execute("UPDATE alarm_types SET vibration_strength = 3, duration = 3 WHERE id = 2");
    await db.execute("UPDATE alarm_types SET duration = 3 WHERE id = 3");
    print('✅ DB 업그레이드 완료 (v$oldVersion → v11): 진동/무음 기본값 최종 적용');
  }

  // v12: 날짜별 메모 테이블 추가
  if (oldVersion < 12) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS date_memos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        memo_text TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_date_memos_date ON date_memos(date)');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v12): date_memos 테이블 추가');
  }
}

  // ⭐ 프리셋 기본값 강제 확인/수정 (settings_tab 초기화 시 호출)
  Future<void> ensurePresetDefaults() async {
    final db = await database;
    try {
      // 프리셋 데이터가 있는지 확인
      var presetCheck = await db.rawQuery("SELECT COUNT(*) as cnt FROM alarm_types WHERE is_preset = 1");
      int presetCount = Sqflite.firstIntValue(presetCheck) ?? 0;

      if (presetCount == 0) {
        print('⚠️ 프리셋 없음 - settings_tab에서 초기화 예정');
        return;
      }

      // 단일 트랜잭션으로 모든 UPDATE 실행 (락 충돌 최소화)
      await db.transaction((txn) async {
        // 소리(id=1): alarmbell1, 70%, 강하게, 3분
        await txn.execute('''
          UPDATE alarm_types SET
            sound_file = CASE WHEN sound_file = 'loud' OR sound_file = 'soft' THEN 'alarmbell1' ELSE sound_file END,
            volume = CASE WHEN volume = 1.0 THEN 0.7 ELSE volume END,
            vibration_strength = CASE WHEN vibration_strength = 2 THEN 3 ELSE vibration_strength END,
            duration = CASE WHEN duration = 10 OR duration = 5 THEN 3 ELSE duration END
          WHERE id = 1 AND is_preset = 1
        ''');

        // 진동(id=2): 강하게, 3분
        await txn.execute('''
          UPDATE alarm_types SET
            vibration_strength = CASE WHEN vibration_strength = 2 OR vibration_strength = 1 THEN 3 ELSE vibration_strength END,
            duration = CASE WHEN duration = 10 OR duration = 5 THEN 3 ELSE duration END
          WHERE id = 2 AND is_preset = 1
        ''');

        // 무음(id=3): 3분
        await txn.execute('''
          UPDATE alarm_types SET
            duration = CASE WHEN duration = 10 OR duration = 5 THEN 3 ELSE duration END
          WHERE id = 3 AND is_preset = 1
        ''');
      });

      print('✅ 프리셋 기본값 확인 완료');
    } catch (e) {
      print('⚠️ 프리셋 기본값 확인 중 오류: $e');
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

    // ⭐ 이력 기록: 알람 정보 먼저 읽기
    try {
      final alarmMaps = await db.query(
        'alarms',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (alarmMaps.isNotEmpty) {
        final alarmMap = alarmMaps.first;
        final scheduledDate = alarmMap['date'] as String?;
        final scheduledTime = alarmMap['time'] as String?;
        final shiftType = alarmMap['shift_type'] as String?;

        // alarm_history에 '사용자 삭제' 기록 추가
        if (scheduledDate != null && scheduledTime != null) {
          await db.insert('alarm_history', {
            'alarm_id': id,
            'scheduled_time': scheduledTime,
            'scheduled_date': scheduledDate,
            'actual_ring_time': DateTime.now().toIso8601String(),
            'dismiss_type': 'deleted_by_user',
            'snooze_count': 0,
            'shift_type': shiftType,
            'created_at': DateTime.now().toIso8601String(),
          });
          print('✅ alarm_history에 "사용자 삭제" 기록 추가: ID=$id');
        }
      }
    } catch (e) {
      print('⚠️ 알람 이력 기록 실패: $e');
    }

    // 알람 삭제
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

    // ⭐ 모든 알람 삭제 + 관련 이력도 삭제
    // (사용자는 DB 내부 동작을 알 필요 없음. 전체 삭제는 클린 스타트)
    await db.delete('alarms');
    print('🗑️ 모든 알람 삭제 완료');

    await db.delete('alarm_history');
    print('🗑️ 모든 알람 이력 삭제 완료');
  }

  // ⭐ 신규: 모든 알람 템플릿 삭제
  Future<void> deleteAllAlarmTemplates() async {
    final db = await database;
    await db.delete('shift_alarm_templates');
    print('🗑️ 모든 알람 템플릿 삭제 완료');
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

  // ⭐ 근무명 변경 (알람, 템플릿, 이력 테이블 모두 업데이트)
  Future<void> updateShiftNames(Map<String, String> renamedShifts) async {
    if (renamedShifts.isEmpty) return;

    final db = await database;

    for (var entry in renamedShifts.entries) {
      final oldName = entry.key;
      final newName = entry.value;

      // 1. alarms 테이블의 shift_type 업데이트
      await db.update(
        'alarms',
        {'shift_type': newName},
        where: 'shift_type = ?',
        whereArgs: [oldName],
      );

      // 2. shift_alarm_templates 테이블의 shift_type 업데이트
      await db.update(
        'shift_alarm_templates',
        {'shift_type': newName},
        where: 'shift_type = ?',
        whereArgs: [oldName],
      );

      // 3. alarm_history 테이블의 shift_type 업데이트
      await db.update(
        'alarm_history',
        {'shift_type': newName},
        where: 'shift_type = ?',
        whereArgs: [oldName],
      );

      print('✅ 근무명 변경: $oldName → $newName');
    }
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

// ⭐ 신규: 특정 알람 ID 이력 조회
Future<List<AlarmHistory>> getAlarmHistoryByAlarmId(int alarmId) async {
  final db = await database;
  final maps = await db.query(
    'alarm_history',
    where: 'alarm_id = ?',
    whereArgs: [alarmId],
    orderBy: 'created_at DESC',
    limit: 1, // 가장 최근 이력 1개만
  );
  return maps.map((map) => AlarmHistory.fromMap(map)).toList();
}

// ⭐ 신규: 모든 알람 이력 조회 (날짜순 정렬)
Future<List<AlarmHistory>> getAllAlarmHistory() async {
  final db = await database;
  final maps = await db.query(
    'alarm_history',
    orderBy: 'scheduled_date ASC, scheduled_time ASC, created_at DESC',
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

// ===== 메모 관련 메서드 =====

// ⭐ 메모 생성 (최대 3개 체크)
Future<int?> createMemo(String date, String memoText) async {
  final db = await database;

  return await db.transaction((txn) async {
    // 해당 날짜의 메모 개수 확인
    final count = Sqflite.firstIntValue(
      await txn.rawQuery(
        'SELECT COUNT(*) FROM date_memos WHERE date = ?',
        [date],
      ),
    ) ?? 0;

    if (count >= 3) {
      print('⚠️ 메모는 하루에 최대 3개까지만 가능합니다.');
      return null;
    }

    // 다음 order_index 계산 (0, 1, 2)
    final maxOrder = Sqflite.firstIntValue(
      await txn.rawQuery(
        'SELECT MAX(order_index) FROM date_memos WHERE date = ?',
        [date],
      ),
    );
    final nextOrder = (maxOrder ?? -1) + 1;

    return await txn.insert('date_memos', {
      'date': date,
      'memo_text': memoText,
      'order_index': nextOrder,
      'created_at': DateTime.now().toIso8601String(),
    });
  });
}

// ⭐ 특정 날짜의 모든 메모 조회 (order_index 순)
Future<List<DateMemo>> getMemosForDate(String date) async {
  final db = await database;
  final maps = await db.query(
    'date_memos',
    where: 'date = ?',
    whereArgs: [date],
    orderBy: 'order_index ASC',
  );
  return maps.map((map) => DateMemo.fromMap(map)).toList();
}

// ⭐ 기간의 메모들 조회 (달력 표시용)
Future<Map<String, List<DateMemo>>> getMemosForDateRange(
  DateTime startDate,
  DateTime endDate,
) async {
  final db = await database;
  final startStr = startDate.toIso8601String().split('T')[0];
  final endStr = endDate.toIso8601String().split('T')[0];

  final maps = await db.query(
    'date_memos',
    where: 'date >= ? AND date <= ?',
    whereArgs: [startStr, endStr],
    orderBy: 'date ASC, order_index ASC',
  );

  // 날짜별로 그룹화
  final Map<String, List<DateMemo>> result = {};
  for (var map in maps) {
    final memo = DateMemo.fromMap(map);
    if (!result.containsKey(memo.date)) {
      result[memo.date] = [];
    }
    result[memo.date]!.add(memo);
  }

  return result;
}

// ⭐ 메모 수정
Future<int> updateMemo(int id, String memoText) async {
  final db = await database;
  return await db.update(
    'date_memos',
    {'memo_text': memoText},
    where: 'id = ?',
    whereArgs: [id],
  );
}

// ⭐ 메모 삭제 + order_index 재정렬
Future<void> deleteMemo(int id) async {
  final db = await database;

  await db.transaction((txn) async {
    // 삭제할 메모 정보 가져오기
    final memoMaps = await txn.query(
      'date_memos',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (memoMaps.isEmpty) return;

    final memo = DateMemo.fromMap(memoMaps.first);

    // 삭제
    await txn.delete(
      'date_memos',
      where: 'id = ?',
      whereArgs: [id],
    );

    // 같은 날짜의 나머지 메모들의 order_index 재정렬
    await txn.rawUpdate('''
      UPDATE date_memos
      SET order_index = order_index - 1
      WHERE date = ? AND order_index > ?
    ''', [memo.date, memo.orderIndex]);
  });

  print('✅ 메모 삭제 및 재정렬 완료');
}

// ⭐ 메모 순서 변경
Future<void> reorderMemos(String date, List<int> memoIds) async {
  if (memoIds.length > 3) {
    print('⚠️ 메모는 최대 3개까지만 가능합니다.');
    return;
  }

  final db = await database;
  await db.transaction((txn) async {
    for (int i = 0; i < memoIds.length; i++) {
      await txn.update(
        'date_memos',
        {'order_index': i},
        where: 'id = ? AND date = ?',
        whereArgs: [memoIds[i], date],
      );
    }
  });

  print('✅ 메모 순서 변경 완료');
}

// ⭐ 10일 이상 지난 알람 이력 자동 삭제
Future<void> deleteOldAlarmHistory() async {
  try {
    final db = await database;

    // 10일 전 날짜 계산
    final cutoffDate = DateTime.now().subtract(Duration(days: 10));
    final cutoffDateStr = cutoffDate.toIso8601String();

    // 10일 이상 지난 이력 삭제
    final deletedCount = await db.delete(
      'alarm_history',
      where: 'created_at < ?',
      whereArgs: [cutoffDateStr],
    );

    if (deletedCount > 0) {
      print('🗑️ 10일 이상 지난 알람 이력 ${deletedCount}개 삭제 완료');
    }
  } catch (e) {
    print('⚠️ 오래된 알람 이력 삭제 실패: $e');
  }
}

// ⭐ 테스트용: 모든 알람 이력 삭제
Future<void> deleteAllAlarmHistory() async {
  try {
    final db = await database;
    final deletedCount = await db.delete('alarm_history');
    print('🗑️ 모든 알람 이력 ${deletedCount}개 삭제 완료 (테스트)');
  } catch (e) {
    print('⚠️ 알람 이력 전체 삭제 실패: $e');
    rethrow;
  }
}

}