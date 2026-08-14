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
  static const platform = MethodChannel('com.hwani1103.shiftbell/alarm');

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
      version: 17,  // v17: friends 테이블을 Firestore ownerId 기반으로 재설계 (친구공유_v1_스펙.md)
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

  // ⭐ CRITICAL FIX: 모든 CREATE TABLE/INDEX에 IF NOT EXISTS를 붙여서 이 함수가 두 번
  // 실행돼도(예: onOpen의 "테이블 없음 감지 시 재생성" 방어 로직이 호출할 때) 절대
  // "테이블이 이미 존재함" 예외로 죽지 않게 함. 프리셋 삽입도 이미 있으면 무시하도록
  // conflictAlgorithm.ignore 사용. 실제로 Native/Flutter DB 버전 불일치 레이스로 이
  // 함수가 두 번 불려서 "table date_overtime already exists"로 앱이 죽은 적이 있었음.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarm_types(
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
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarms(
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
      CREATE TABLE IF NOT EXISTS shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');

    // ⭐ 신규: 알람 이력 테이블
  await db.execute('''
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
    )
  ''');

    // ⭐ 신규: 날짜별 메모 테이블
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

    // ⭐ 신규: 알람 생성 이력 원장 (append-only, 절대 UPDATE/DELETE 안 함)
    // 알람이 생성되는 "그 순간"에 무조건 기록 → 나중에 alarms/alarm_history에서
    // 뭔가 사라져도 "생성은 됐었다"는 사실 자체는 여기서 확인 가능
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarm_creation_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL,
        scheduled_date TEXT NOT NULL,
        scheduled_time TEXT NOT NULL,
        shift_type TEXT,
        alarm_type_id INTEGER,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_creation_log_alarm_id ON alarm_creation_log(alarm_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_creation_log_created_at ON alarm_creation_log(created_at)');

    // ⭐ 신규: 날짜별 OT(추가근무) 누적 시간
    await db.execute('''
      CREATE TABLE IF NOT EXISTS date_overtime(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        minutes INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_date_overtime_date ON date_overtime(date)');

    // ⭐ 친구 공유 - Firestore ownerId로 친구를 등록해두고, 마지막으로 성공 조회한
    // 스케줄만 오프라인 대비용 캐시로 저장 (data_json은 nullable - fetch 전엔 없음).
    // 친구공유_v1_스펙.md 참고.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS friends(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_id TEXT NOT NULL UNIQUE,
        data_json TEXT,
        added_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    for (var type in AlarmType.presets) {
      await db.insert('alarm_types', type.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
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

  // v13: 알람 생성 이력 원장 추가
  if (oldVersion < 13) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarm_creation_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL,
        scheduled_date TEXT NOT NULL,
        scheduled_time TEXT NOT NULL,
        shift_type TEXT,
        alarm_type_id INTEGER,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_creation_log_alarm_id ON alarm_creation_log(alarm_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_creation_log_created_at ON alarm_creation_log(created_at)');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v13): alarm_creation_log 테이블 추가');
  }

  // v14: 날짜별 OT(추가근무) 누적 시간 추가
  if (oldVersion < 14) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS date_overtime(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        minutes INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_date_overtime_date ON date_overtime(date)');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v14): date_overtime 테이블 추가');
  }

  // v15: 근무별 기본 근로시간(shift_durations) 컬럼 추가
  if (oldVersion < 15) {
    try {
      await db.execute('ALTER TABLE shift_schedule ADD COLUMN shift_durations TEXT');
    } catch (e) {
      // ⭐ IF NOT EXISTS가 없는 ALTER문이라, 혹시 이미 컬럼이 있으면(드문 재시도 등)
      // 예외 대신 조용히 넘어가게 방어
      print('⚠️ shift_durations 컬럼 추가 스킵(이미 존재 가능성): $e');
    }
    print('✅ DB 업그레이드 완료 (v$oldVersion → v15): shift_schedule.shift_durations 컬럼 추가');
  }

  // v16: 친구 공유 코드 저장 테이블 추가
  if (oldVersion < 16) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS friends(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        data_json TEXT NOT NULL,
        has_memos INTEGER NOT NULL,
        added_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v16): friends 테이블 추가');
  }

  // v17: 친구공유 v1(Firestore) 전환 - friends 테이블을 owner_id 기반으로 재설계.
  // ⭐ 아직 정식 출시 전 기능(베타 단계, 실사용자 스냅샷 데이터 없음)이라 기존
  // data_json(전체 스냅샷)을 마이그레이션하지 않고 통째로 새로 만듦 - alarm_history
  // 등과 달리 friends 테이블은 영구보존 대상이 아님([[history-permanence]] 무관).
  if (oldVersion < 17) {
    await db.execute('DROP TABLE IF EXISTS friends');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS friends(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_id TEXT NOT NULL UNIQUE,
        data_json TEXT,
        added_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v17): friends 테이블을 Firestore ownerId 기반으로 재설계');
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
  
  Future<int> insertAlarm(Alarm alarm, {String source = 'manual'}) async {
    final db = await database;
    return await db.transaction((txn) async {
      final id = await txn.insert('alarms', alarm.toMap());
      await logAlarmCreation(txn, id, alarm, source);
      return id;
    });
  }

  // ⭐ 알람 생성 이력 원장에 기록 (append-only). 알람을 삽입하는 모든 경로(달력 팝업의
  // 날짜별 근무 변경 등 자체 트랜잭션을 여는 곳 포함)에서 재사용할 수 있게 public으로 노출.
  // 호출부가 이미 트랜잭션 안에 있으므로 여기선 그냥 insert만 함.
  Future<void> logAlarmCreation(DatabaseExecutor txn, int alarmId, Alarm alarm, String source) async {
    if (alarm.date == null) return;
    final dateStr = alarm.date!.toIso8601String();
    await txn.insert('alarm_creation_log', {
      'alarm_id': alarmId,
      'scheduled_date': dateStr,
      'scheduled_time': alarm.time,
      'shift_type': alarm.shiftType,
      'alarm_type_id': alarm.alarmTypeId,
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ⭐ 생성 이력 조회 (알람이 사라졌어도 "생성은 됐었는지" 확인용)
  Future<List<Map<String, dynamic>>> getAlarmCreationLog({int limit = 200}) async {
    final db = await database;
    return db.query('alarm_creation_log', orderBy: 'created_at DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getCreationLogForAlarm(int alarmId) async {
    final db = await database;
    return db.query('alarm_creation_log', where: 'alarm_id = ?', whereArgs: [alarmId], orderBy: 'created_at DESC');
  }

  // ⭐ alarm_creation_log는 의도적으로 자동 삭제 로직이 없음.
  // 알람이 나중에 어떤 이유로든(사용자 삭제/버그) 사라져도 "생성됐다는 사실"은
  // 항상 남아있어야 한다는 요구사항이라 여기엔 cleanup 함수를 안 둠.

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
  
  /// 알람 삭제
  /// [createHistory]: false면 이력 생성 없이 삭제만 (달력/다음알람탭에서 삭제 시)
  /// [dismissType]: 이력 생성 시 사용 (swiped, cancelled_before_ring 등)
  // ⭐ 이력 insert와 alarms delete를 하나의 트랜잭션으로 묶음 - 예전엔 두 개의
  // 독립적인 await 호출이라, 그 사이(이력은 이미 기록됐는데 삭제는 아직 안 된)
  // 아주 좁은 순간에 프로세스가 죽으면 "이력엔 취소됐다고 나오는데 alarms
  // 테이블엔 그대로 남아있고, 네이티브 알람도 안 취소된" 상태가 될 수 있었음
  // (그 알람이 실제로 다시 울릴 수 있음 - CustomAlarmReceiver의 "DB에 없으면
  // 재생 안 함" 방어도 이 경우엔 못 걸러냄, DB에 여전히 있으니까). 트랜잭션으로
  // 묶으면 크래시가 나도 SQLite가 전부 롤백해서 "취소 자체가 없었던 상태"로
  // 돌아가므로 이 모순이 원천적으로 안 생김.
  // ⭐ 이력 기록 실패 시(드묾) 동작은 그대로 유지 - catch에서 삼키고 삭제는
  // 트랜잭션 안에서 계속 진행함(기존과 동일한 fail-open, 새로운 실패 모드 없음).
  Future<int> deleteAlarm(int id, {String dismissType = 'cancelled_before_ring', bool createHistory = true}) async {
    final db = await database;
    late final int deletedCount;

    await db.transaction((txn) async {
      // ⭐ 이력 기록: createHistory가 true일 때만
      if (createHistory) {
        try {
          final alarmMaps = await txn.query(
            'alarms',
            where: 'id = ?',
            whereArgs: [id],
          );

          if (alarmMaps.isNotEmpty) {
            final alarmMap = alarmMaps.first;
            final scheduledDate = alarmMap['date'] as String?;
            final scheduledTime = alarmMap['time'] as String?;
            final shiftType = alarmMap['shift_type'] as String?;

            // alarm_history에 이력 추가 (dismiss_type 파라미터 사용)
            if (scheduledDate != null && scheduledTime != null) {
              await txn.insert('alarm_history', {
                'alarm_id': id,
                'scheduled_time': scheduledTime,
                'scheduled_date': scheduledDate,
                'actual_ring_time': DateTime.now().toIso8601String(),
                'dismiss_type': dismissType,  // ⭐ 파라미터 사용
                'snooze_count': 0,
                'shift_type': shiftType,
                'created_at': DateTime.now().toIso8601String(),
              });
              final historyText = dismissType == 'swiped' ? '알람 확인' : '알람 제거';
              print('✅ alarm_history에 "$historyText" 기록 추가: ID=$id');
            }
          }
        } catch (e) {
          print('⚠️ 알람 이력 기록 실패: $e');
        }
      } else {
        print('ℹ️ 알람 삭제 (이력 생성 안 함): ID=$id');
      }

      // 알람 삭제
      deletedCount = await txn.delete(
        'alarms',
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    return deletedCount;
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

  Future<void> insertAlarmsInBatch(List<Alarm> alarms, {String source = 'auto'}) async {
    final db = await database;

    await db.transaction((txn) async {
      for (var alarm in alarms) {
        final id = await txn.insert('alarms', alarm.toMap());
        await logAlarmCreation(txn, id, alarm, source);
      }
    });

    print('✅ ${alarms.length}개 알람 일괄 등록 완료 (생성 이력 기록됨)');
  }

  // ⭐ 전체 초기화(설정 리셋/온보딩 재시작)에서도 이력은 절대 지우지 않음.
  // 예전엔 "클린 스타트"라는 이유로 alarm_history까지 같이 지웠는데,
  // 이력은 사용자 입장에서 "내가 알람을 놓쳤는지 안 놓쳤는지"를 증명하는
  // 기록이라 스케줄을 초기화한다고 해서 같이 사라지면 안 됨.
  // ⭐ deleteAllAlarmsOnly()와 동일하게, 지워지는 각 알람도 이력에 남김(superseded)
  // - 나중에 "이 시점에 알람이 왜 사라졌지" 추적 가능해야 함.
  Future<void> deleteAllAlarms() async {
    final db = await database;

    await db.transaction((txn) async {
      final toRemove = await txn.query('alarms');
      final now = DateTime.now().toIso8601String();

      for (final row in toRemove) {
        final date = row['date'] as String?;
        final time = row['time'] as String?;
        if (date != null && time != null) {
          await txn.insert('alarm_history', {
            'alarm_id': row['id'],
            'scheduled_time': time,
            'scheduled_date': date,
            'actual_ring_time': now,
            'dismiss_type': 'superseded',
            'snooze_count': 0,
            'shift_type': row['shift_type'],
            'created_at': now,
          });
        }
      }

      await txn.delete('alarms');
    });

    print('🗑️ 모든 알람 삭제 완료 (이력 기록 후 삭제)');
  }

  // ⭐ 자동 생성분(type='fixed')만 삭제 (이력은 유지, 스누즈 중인 알람은 절대 건드리지 않음)
  // - 자동 갱신/패턴 변경 시 사용. 삭제되는 각 알람은 이력에 남김 (superseded)
  Future<void> deleteAllAlarmsOnly() async {
    final db = await database;

    await db.transaction((txn) async {
      final toRemove = await txn.query('alarms', where: "type = ?", whereArgs: ['fixed']);
      final now = DateTime.now().toIso8601String();

      for (final row in toRemove) {
        final date = row['date'] as String?;
        final time = row['time'] as String?;
        if (date != null && time != null) {
          await txn.insert('alarm_history', {
            'alarm_id': row['id'],
            'scheduled_time': time,
            'scheduled_date': date,
            'actual_ring_time': now,
            'dismiss_type': 'superseded',
            'snooze_count': 0,
            'shift_type': row['shift_type'],
            'created_at': now,
          });
        }
      }

      await txn.delete('alarms', where: "type = ?", whereArgs: ['fixed']);
    });

    print('🗑️ 자동 생성 알람 삭제 완료 (스누즈 중인 알람 보호, 이력 유지)');
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

  // ⭐ "고정 알람 수정" 저장 전용: 전체 삭제 + 재삽입을 하나의 트랜잭션으로 묶음.
  // 예전엔 deleteAllAlarmTemplates()와 각 insertAlarmTemplate() 호출이 전부
  // 별개였는데, 그 사이(특히 알람이 여러 개라 반복 삽입이 오래 걸릴 때)에 Native
  // 갱신 엔진이 하필 그 순간 끼어들면 "일부 근무만 템플릿이 텅 빈" 상태를 그대로
  // 읽어서, 아직 안 지워진(옛) 알람을 엉뚱하게 재등록하거나 취소해버릴 수 있었음.
  // 하나의 트랜잭션으로 묶으면 다른 커넥션(Native 포함)에서는 "삭제 전 전체" 또는
  // "삭제+삽입 후 전체" 둘 중 하나만 보이고, 중간의 텅 빈 상태는 절대 보이지 않음.
  Future<void> replaceAllAlarmTemplates(List<Map<String, dynamic>> templates) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('shift_alarm_templates');
      for (final t in templates) {
        await txn.insert('shift_alarm_templates', t);
      }
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

  // ⭐ 근무명 변경 - alarms/shift_alarm_templates/alarm_history/alarm_creation_log
  // 4개 테이블의 shift_type과 shift_schedule 행(패턴/색상/근무변경 등) 전부를 하나의
  // 트랜잭션으로 묶어서 원자적으로 갱신함.
  // ⭐ 예전엔 이 DB 갱신(구 updateShiftNames())과 scheduleProvider.saveSchedule()
  // (별도 호출)이 서로 다른 시점에 실행돼서, 그 사이 크래시가 나면 "알람 테이블은
  // 새 이름인데 스케줄 패턴은 옛 이름"인 모순된 상태가 될 수 있었음 - 이제 호출부
  // (settings_tab.dart)가 이 메서드 하나만 부르면 됨.
  // ⭐ alarm_creation_log도 이번에 추가함 - 예전엔 이 테이블만 빠져있어서, 근무명을
  // 한 번이라도 바꾸면 영구 보존되는 생성 로그가 옛 이름으로 계속 남아 alarm_history
  // (새 이름)와 대조가 안 맞는 문제가 있었음.
  Future<void> renameShiftAtomic({
    required Map<String, String> renamedShifts,
    required ShiftSchedule newSchedule,
  }) async {
    if (renamedShifts.isEmpty) return;

    final db = await database;

    await db.transaction((txn) async {
      for (var entry in renamedShifts.entries) {
        final oldName = entry.key;
        final newName = entry.value;

        // 1. alarms 테이블의 shift_type 업데이트
        await txn.update(
          'alarms',
          {'shift_type': newName},
          where: 'shift_type = ?',
          whereArgs: [oldName],
        );

        // 2. shift_alarm_templates 테이블의 shift_type 업데이트
        await txn.update(
          'shift_alarm_templates',
          {'shift_type': newName},
          where: 'shift_type = ?',
          whereArgs: [oldName],
        );

        // 3. alarm_history 테이블의 shift_type 업데이트
        await txn.update(
          'alarm_history',
          {'shift_type': newName},
          where: 'shift_type = ?',
          whereArgs: [oldName],
        );

        // 4. alarm_creation_log 테이블의 shift_type 업데이트 (영구 보존 로그 - 예전엔 빠져있었음)
        await txn.update(
          'alarm_creation_log',
          {'shift_type': newName},
          where: 'shift_type = ?',
          whereArgs: [oldName],
        );

        print('✅ 근무명 변경(원자적): $oldName → $newName');
      }

      // 5. shift_schedule 행(패턴/근무명 목록/색상/근무변경/근로시간) 업데이트
      await txn.update(
        'shift_schedule',
        newSchedule.toMap(),
        where: 'id = ?',
        whereArgs: [newSchedule.id],
      );
    });
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

// ===== OT(추가근무) 관련 메서드 =====

// ⭐ 특정 날짜의 OT를 30분 단위로 증감 (0 밑으로는 안 내려감, 0이 되면 row 자체를 지움)
Future<int> adjustOvertime(String date, int deltaMinutes) async {
  final db = await database;
  return await db.transaction((txn) async {
    final rows = await txn.query('date_overtime', where: 'date = ?', whereArgs: [date]);
    final current = rows.isNotEmpty ? (rows.first['minutes'] as int) : 0;
    final newTotal = (current + deltaMinutes).clamp(0, 24 * 60);

    if (newTotal <= 0) {
      if (rows.isNotEmpty) {
        await txn.delete('date_overtime', where: 'date = ?', whereArgs: [date]);
      }
    } else {
      final now = DateTime.now().toIso8601String();
      if (rows.isNotEmpty) {
        await txn.update(
          'date_overtime',
          {'minutes': newTotal, 'updated_at': now},
          where: 'date = ?',
          whereArgs: [date],
        );
      } else {
        await txn.insert('date_overtime', {
          'date': date,
          'minutes': newTotal,
          'updated_at': now,
        });
      }
    }

    return newTotal;
  });
}

// ⭐ 특정 날짜의 OT 조회 (없으면 0)
Future<int> getOvertimeForDate(String date) async {
  final db = await database;
  final rows = await db.query('date_overtime', where: 'date = ?', whereArgs: [date]);
  if (rows.isEmpty) return 0;
  return rows.first['minutes'] as int;
}

// ⭐ 기간의 OT 전부 조회 (0인 날짜는 애초에 row가 없으므로 결과에 없음)
Future<Map<String, int>> getOvertimeForRange(DateTime startDate, DateTime endDate) async {
  final db = await database;
  final startStr = startDate.toIso8601String().split('T')[0];
  final endStr = endDate.toIso8601String().split('T')[0];

  final rows = await db.query(
    'date_overtime',
    where: 'date >= ? AND date <= ?',
    whereArgs: [startStr, endStr],
    orderBy: 'date ASC',
  );

  final result = <String, int>{};
  for (var row in rows) {
    result[row['date'] as String] = row['minutes'] as int;
  }
  return result;
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

// ⭐ "설정 초기화" 전용 예외: 다른 모든 삭제 경로는 이력(alarm_history)과 생성
// 로그(alarm_creation_log)를 영구 보존하지만, 사용자가 명시적으로 스케줄 자체를
// 완전히 새로 시작하는 "초기화" 버튼을 누른 경우에는 이력도 함께 지움 - 새 스케줄로
// 다시 시작하는데 이전 근무 패턴의 이력이 남아있으면 오히려 혼란스러움.
Future<void> resetAllAlarmHistoryAndLog() async {
  final db = await database;
  await db.transaction((txn) async {
    await txn.delete('alarm_history');
    await txn.delete('alarm_creation_log');
  });
  print('🗑️ 알람 이력 + 생성 로그 전체 삭제 완료 (설정 초기화)');
}

// ===== 친구 공유 관련 메서드 =====
// ⭐ 친구공유 v1(Firestore) - friends 테이블은 "누구를 등록했는지"(owner_id)와 마지막
// 조회 결과 캐시(data_json, 오프라인 대비용)만 들고 있음. 실제 최신 데이터는 항상
// FriendSyncService.fetchByOwnerId()로 Firestore에서 다시 받아옴 (friend_provider.dart 참고).

Future<int> insertFriend({required String name, required String ownerId, String? dataJson}) async {
  final db = await database;
  final now = DateTime.now().toIso8601String();
  return await db.insert('friends', {
    'name': name,
    'owner_id': ownerId,
    'data_json': dataJson,
    'added_at': now,
    'updated_at': now,
  });
}

Future<List<Map<String, dynamic>>> getAllFriends() async {
  final db = await database;
  return db.query('friends', orderBy: 'name ASC');
}

Future<int> deleteFriend(int id) async {
  final db = await database;
  return await db.delete('friends', where: 'id = ?', whereArgs: [id]);
}

// ⭐ Firestore에서 새로 fetch한 결과로 캐시 갱신 (같은 친구 id 유지, 데이터만 교체)
Future<int> updateFriendData(int id, {required String dataJson}) async {
  final db = await database;
  return await db.update(
    'friends',
    {
      'data_json': dataJson,
      'updated_at': DateTime.now().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<int> renameFriend(int id, String name) async {
  final db = await database;
  return await db.update('friends', {'name': name}, where: 'id = ?', whereArgs: [id]);
}

}