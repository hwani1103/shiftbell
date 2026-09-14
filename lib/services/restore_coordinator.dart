// lib/services/restore_coordinator.dart
//
// ⭐ 2026-09-14 (출시전 감사 G4 #9/#19/#25, G2-03·G3 #2 연결) - 백업 복원을 단계 기록·잠금·재시도 가능한 작업으로 실행.
// 설계: 출시전_수정작업_그룹별_실행계획_및_세션인계_2026-09-14.md G4 "복원 설계" 1~18, v4 #9·#19·#25.
//
// 단계: validated → locked → os_cleared → db_applied → prefs_applied → os_reconciled → (잠금 해제·기록 삭제)
//  1. 검증(BackupValidator)이 모든 변경보다 먼저. 실패면 아무것도 안 바꿈.
//  2. 검증 통과 내용을 Device Protected 저장소에 작업 사본 + 지문으로 저장. 이후 단계는 원본(다운로드 폴더) 대신 사본 사용.
//  3. 잠금: 네이티브 RestoreGate(토큰 = prefs + 프로세스 메모리). 갱신 엔진·재시도·일정 재예약·수면 감지/위젯은 미룸,
//     알람 재생·끄기·스누즈·타임아웃은 막지 않음. 이 owner의 최종 재조정은 토큰으로 통과.
//  4. os_cleared: 진행 중 알람(울림 + 미래 스누즈)의 재생 설정 스냅샷 → 그 ID를 뺀 옛 기상 알람·일정 알림 예약 취소.
//  5. db_applied: 한 트랜잭션. 원본 테이블은 백업 내용으로 교체(백업에 없는 테이블은 비움 - 구버전 백업에 alarm_overrides가
//     없으면 옛 예외가 남지 않게), 영구 이력은 자연키로 중복 제외 병합(절대 비우지 않음), alarms는 진행 중 행을 **원래 ID로**
//     이월 + 백업 custom 행 삽입. ID가 겹치면 **백업 custom 쪽**이 새 ID를 받고, {백업ID: 새ID}는 트랜잭션 전에 작업 기록에 저장해
//     재시도에서 같은 값을 씀. 트랜잭션 안에서 이월 대상이 늘어 새 충돌이 생기면 롤백 후 매핑을 늘려 다시 시도.
//  6. prefs_applied: 백업 설정 중 허용 키만 반영(친구공유 7키·설치별 키 제외). 쓰기 실패는 실패로 처리.
//  7. os_reconciled: 네이티브가 fixed 재계산 + 미래 custom·snoozed 명시 재예약 + 복원된 탭 설정으로 일정 알림 재예약.
//  완료 뒤(잠금 해제 후): Guard 재확인·위젯 갱신·친구공유 onRestoreCompleted(active면 현재 UID·회차로 dirty 재업로드).
//
// DB 교체는 트랜잭션이라 재실행해도 결과가 같음(원본 테이블은 같은 사본으로 다시 채움, 이력은 자연키로 중복 제외, 매핑은 기록 재사용).
// 중간 실패 시: 현재 DB 기준으로 OS 예약을 다시 맞춘 뒤(예약이 취소된 채 남지 않게) 잠금을 풀고 작업 기록은 남김 → 앱을 열면
// 이어서 완료 / 지금 데이터로 계속 선택(RestoreInterruptedScreen). 프로세스가 죽으면 네이티브가 죽은 잠금을 풀고 알림을 띄움.
// DB·설정·OS 전체가 하나의 트랜잭션이라는 뜻은 아니다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/platform_channel.dart';
import '../models/backup_payload.dart';
import 'backup_policy.dart';
import 'backup_validator.dart';
import 'database_service.dart';
import 'friend_sync_service.dart';
import 'widget_refresh_service.dart';

enum RestorePhase { validated, locked, osCleared, dbApplied, prefsApplied, osReconciled }

class RestoreJob {
  final String id;
  final String copyPath;
  final String fingerprint;
  final bool overwrite;
  final String createdAt;
  RestorePhase phase;
  final Map<int, int> idMap;

  RestoreJob({
    required this.id,
    required this.copyPath,
    required this.fingerprint,
    required this.overwrite,
    required this.createdAt,
    required this.phase,
    required this.idMap,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'copyPath': copyPath,
        'fingerprint': fingerprint,
        'overwrite': overwrite,
        'createdAt': createdAt,
        'phase': phase.name,
        'idMap': idMap.map((k, v) => MapEntry(k.toString(), v)),
      };

  static RestoreJob fromJson(Map<String, dynamic> json) => RestoreJob(
        id: json['id'] as String,
        copyPath: json['copyPath'] as String,
        fingerprint: json['fingerprint'] as String,
        overwrite: json['overwrite'] as bool,
        createdAt: json['createdAt'] as String,
        phase: RestorePhase.values.byName(json['phase'] as String),
        idMap: (json['idMap'] as Map).map((k, v) => MapEntry(int.parse(k as String), v as int)),
      );
}

/// 복원이 끝까지 가지 못함. 작업 기록은 남아 있고 OS 예약은 현재 DB 기준으로 다시 맞춰져 있음.
class RestoreIncompleteException implements Exception {
  final Object cause;
  RestoreIncompleteException(this.cause);
  @override
  String toString() => 'RestoreIncompleteException($cause)';
}

/// 이어서 할 작업 사본이 없거나 손상됨 - 현재 DB 기준으로 정리하고 작업을 끝냄.
class RestoreCopyLostException implements Exception {}

class _MappingChanged implements Exception {}

class RestoreCoordinator {
  RestoreCoordinator._();
  static final RestoreCoordinator instance = RestoreCoordinator._();

  static const _channel = kAlarmChannel;
  static const _jobFileName = 'job.json';
  static const _historyKeys = {
    'alarm_history': ['alarm_id', 'scheduled_date', 'scheduled_time', 'actual_ring_time', 'dismiss_type'],
    'alarm_creation_log': ['alarm_id', 'scheduled_date', 'scheduled_time', 'source', 'created_at'],
  };

  bool _running = false;

  // ── 공개 API ─────────────────────────────────────────────────────

  /// 새 복원. 검증 실패면 [BackupValidationException](아무것도 바뀌지 않음).
  /// 중간 실패면 [RestoreIncompleteException](작업 기록 유지, 예약은 현재 DB 기준으로 재조정됨).
  Future<void> start(BackupPayload payload, {required bool overwrite}) async {
    if (_running) throw StateError('restore already running');
    if (await hasPendingJob()) throw StateError('pending restore job exists');
    final db = await DatabaseService.instance.database;
    final issues = await BackupValidator.validate(payload, db);
    if (issues.isNotEmpty) {
      debugPrint('🧯 [restore] 검증 실패: $issues');
      throw BackupValidationException(issues);
    }

    final dir = await _workDir();
    final id = _newToken();
    final content = payload.encode();
    final fingerprint = contentFingerprint(content);
    final copy = File(p.join(dir.path, 'copy_$id.json'));
    try {
      await copy.writeAsString(content, flush: true);
      if (contentFingerprint(await copy.readAsString()) != fingerprint) {
        throw const FileSystemException('restore copy fingerprint mismatch');
      }
      await _saveJob(RestoreJob(
        id: id,
        copyPath: copy.path,
        fingerprint: fingerprint,
        overwrite: overwrite,
        createdAt: DateTime.now().toIso8601String(),
        phase: RestorePhase.validated,
        idMap: {},
      ));
    } catch (e) {
      // 사본/기록 저장 실패 - 아직 DB·설정·OS는 그대로
      try {
        if (await copy.exists()) await copy.delete();
        await _deleteJobFile();
      } catch (_) {}
      rethrow;
    }
    final job = (await loadPendingJob())!;
    await _run(job, payload);
  }

  Future<bool> hasPendingJob() async {
    try {
      return (await _jobFile()).exists();
    } catch (_) {
      return false;
    }
  }

  /// 중단된 복원 작업(앱 시작 시 확인). 기록이 읽을 수 없게 손상됐으면 null이 아니라 사본 없는 작업으로 취급해 정리 대상.
  Future<RestoreJob?> loadPendingJob() async {
    final file = await _jobFile();
    if (!await file.exists()) return null;
    try {
      return RestoreJob.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🧯 [restore] 작업 기록 손상: $e');
      return RestoreJob(
        id: 'corrupt',
        copyPath: '',
        fingerprint: '',
        overwrite: true,
        createdAt: '',
        phase: RestorePhase.validated,
        idMap: {},
      );
    }
  }

  /// 네이티브가 죽은 잠금을 정리하며 남긴 "중단됨" 표시를 읽고 지움(알림 게시용 플래그).
  Future<bool> consumeInterruptedFlag() async {
    try {
      return await _channel.invokeMethod<bool>('restoreConsumeInterrupted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 중단된 작업을 같은 사본·매핑으로 이어서 완료. 사본이 없거나 지문이 다르면 [safeEnd] 후 [RestoreCopyLostException].
  Future<void> resume() async {
    final job = await loadPendingJob();
    if (job == null) return;
    final payload = await _readCopy(job);
    if (payload == null) {
      await safeEnd();
      throw RestoreCopyLostException();
    }
    await _run(job, payload);
  }

  /// 이어서 하지 않고 지금 데이터로 계속 사용: 현재 DB 기준 OS 재조정 → 작업 기록·사본 삭제.
  Future<void> safeEnd() async {
    final token = _newToken();
    final locked = await _acquire(token);
    try {
      if (locked) await _reconcile(token);
    } catch (e) {
      debugPrint('🧯 [restore] 안전 종료 재조정 실패: $e');
    } finally {
      if (locked) await _release(token);
    }
    await _deleteJob(await loadPendingJob());
    await _afterUnlock();
  }

  // ── 실행 ────────────────────────────────────────────────────────

  Future<void> _run(RestoreJob job, BackupPayload payload) async {
    if (_running) throw StateError('restore already running');
    _running = true;
    final token = _newToken();
    try {
      if (!await _acquire(token)) throw StateError('restore lock not acquired');
      try {
        await _advance(job, RestorePhase.locked, () async {});
        await _advance(job, RestorePhase.osCleared, () async {
          final carry = await _prepareCarry(token);
          await _channel.invokeMethod('restoreClearOs', {'token': token, 'keepIds': carry.carryIds.toList()});
        });
        await _advance(job, RestorePhase.dbApplied, () => _applyDb(job, payload, token));
        await _advance(job, RestorePhase.prefsApplied, () => _applyPrefs(payload));
        await _advance(job, RestorePhase.osReconciled, () => _reconcile(token));
      } catch (e, st) {
        debugPrint('🧯 [restore] 단계 실패(${job.phase.name} 이후): $e\n$st');
        try {
          await _reconcile(token); // 예약이 취소된 채 남지 않게 현재 DB 기준으로 다시 맞춤
        } catch (e2) {
          debugPrint('🧯 [restore] 실패 후 재조정도 실패: $e2');
        }
        await _release(token);
        await _afterUnlock();
        throw RestoreIncompleteException(e);
      }
      await _release(token);
      await _deleteJob(job);
      await _afterUnlock();
    } finally {
      _running = false;
    }
  }

  Future<void> _advance(RestoreJob job, RestorePhase target, Future<void> Function() step) async {
    if (job.phase.index >= target.index) return;
    await step();
    job.phase = target;
    await _saveJob(job);
  }

  Future<({int? activeRingId, Set<int> carryIds})> _prepareCarry(String token) async {
    final res = await _channel.invokeMethod<Map>('restorePrepareCarryOver', {'token': token});
    final ids = ((res?['carryIds'] as List?) ?? const []).map((e) => e as int).toSet();
    return (activeRingId: res?['activeRingId'] as int?, carryIds: ids);
  }

  Future<void> _applyDb(RestoreJob job, BackupPayload payload, String token) async {
    final db = await DatabaseService.instance.database;
    for (var attempt = 0;; attempt++) {
      // 매 시도 전에 진행 중 알람 스냅샷을 다시 확인(그 사이 새로 스누즈된 알람 포함 - 이미 있는 스냅샷은 유지)
      final carry = await _prepareCarry(token);
      await _extendIdMap(db, job, payload, carry.activeRingId);
      try {
        await db.transaction((txn) => _replaceInTxn(txn, job, payload, carry.activeRingId));
        return;
      } on _MappingChanged {
        if (attempt >= 2) rethrow;
        debugPrint('🧯 [restore] 트랜잭션 중 진행 중 알람이 늘어 ID 매핑 재계산');
      }
    }
  }

  /// 백업 custom 알람 ID가 이 기기의 진행 중 알람 ID와 겹치면 백업 쪽에 새 ID 배정. 기존 매핑은 유지(재시도 결과 고정).
  Future<void> _extendIdMap(DatabaseExecutor db, RestoreJob job, BackupPayload payload, int? activeRingId) async {
    final backupIds = (payload.tables[kBackupAlarmsTable] ?? const []).map((r) => r['id'] as int).toList()..sort();
    final carry = await _carryIds(db, activeRingId);
    final seqRows = await db.rawQuery("SELECT seq FROM sqlite_sequence WHERE name = 'alarms'");
    var next = [
      ...backupIds,
      ...carry,
      ...job.idMap.values,
      if (seqRows.isNotEmpty) (seqRows.first['seq'] as int? ?? 0),
      0,
    ].reduce(max) + 1;
    var changed = false;
    for (final id in backupIds) {
      if (job.idMap.containsKey(id)) continue;
      if (carry.contains(id)) {
        job.idMap[id] = next++;
        changed = true;
      }
    }
    if (changed) await _saveJob(job);
  }

  Future<Set<int>> _carryIds(DatabaseExecutor db, int? activeRingId) async {
    final rows = await db.rawQuery(
      "SELECT id FROM alarms WHERE (type = 'snoozed' AND date > ?) OR id = ?",
      [_nowDbString(), activeRingId ?? -1],
    );
    return rows.map((r) => r['id'] as int).toSet();
  }

  Future<void> _replaceInTxn(Transaction txn, RestoreJob job, BackupPayload payload, int? activeRingId) async {
    final carry = await _carryIds(txn, activeRingId);
    final backupAlarms = payload.tables[kBackupAlarmsTable] ?? const <Map<String, dynamic>>[];
    for (final row in backupAlarms) {
      final target = job.idMap[row['id'] as int] ?? row['id'] as int;
      if (carry.contains(target)) throw _MappingChanged();
    }
    final carryRows = carry.isEmpty
        ? const <Map<String, Object?>>[]
        : await txn.query('alarms', where: 'id IN (${List.filled(carry.length, '?').join(',')})', whereArgs: carry.toList());

    final tableRows = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final known = tableRows.map((r) => r['name'] as String).toSet();

    // 원본 테이블: 백업 시점 상태로 교체(백업에 없는 테이블은 비움)
    for (final table in known.where(isReplaceableSourceTable)) {
      await txn.delete(table);
      for (final row in payload.tables[table] ?? const <Map<String, dynamic>>[]) {
        await txn.insert(table, row);
      }
    }

    // 영구 이력: 자연키 기준 중복 제외 병합 - 기존 행은 절대 지우지 않음
    for (final entry in _historyKeys.entries) {
      if (!known.contains(entry.key)) continue;
      final keyCols = entry.value;
      final existing = await txn.query(entry.key, columns: keyCols);
      final seen = existing.map((r) => keyCols.map((c) => '${r[c]}').join('')).toSet();
      for (final row in payload.tables[entry.key] ?? const <Map<String, dynamic>>[]) {
        final key = keyCols.map((c) => '${row[c]}').join('');
        if (!seen.add(key)) continue;
        final copy = Map<String, dynamic>.from(row)..remove('id');
        await txn.insert(entry.key, copy);
      }
    }

    // alarms: 진행 중 행은 원래 ID 그대로 이월, 백업의 미래 custom은 (필요하면 매핑된) ID로 삽입
    await txn.delete('alarms');
    for (final row in carryRows) {
      await txn.insert('alarms', row);
    }
    final now = _nowDbString();
    for (final row in backupAlarms) {
      final date = row['date'] as String?;
      if (date == null || date.compareTo(now) <= 0) continue;
      final copy = Map<String, dynamic>.from(row)..['id'] = job.idMap[row['id'] as int] ?? row['id'];
      await txn.insert('alarms', copy);
    }
  }

  Future<void> _applyPrefs(BackupPayload payload) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in payload.preferences.entries) {
      if (!isBackupPreferenceKey(entry.key)) continue;
      final value = entry.value;
      final bool ok;
      if (value is bool) {
        ok = await prefs.setBool(entry.key, value);
      } else if (value is int) {
        ok = await prefs.setInt(entry.key, value);
      } else if (value is double) {
        ok = await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        ok = await prefs.setString(entry.key, value);
      } else if (value is List) {
        ok = await prefs.setStringList(entry.key, value.cast<String>());
      } else {
        continue;
      }
      if (!ok) throw StateError('preference write failed: ${entry.key}');
    }
  }

  Future<void> _reconcile(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final tabEnabled = prefs.getBool('schedule_tab_enabled') ?? true;
    await _channel.invokeMethod('restoreReconcileOs', {'token': token, 'scheduleTabEnabled': tabEnabled});
  }

  /// 잠금 해제 뒤(일반 writer 허용 상태)에만 하는 후속 동작.
  Future<void> _afterUnlock() async {
    try {
      await _channel.invokeMethod('triggerGuardCheck');
    } catch (e) {
      debugPrint('🧯 [restore] Guard 재확인 실패: $e');
    }
    try {
      await WidgetRefreshService.refresh();
    } catch (_) {}
    try {
      final schedule = await DatabaseService.instance.getShiftSchedule();
      await FriendSyncService.instance.onRestoreCompleted(schedule);
    } catch (e) {
      debugPrint('🧯 [restore] 친구공유 복원 후 재시도 실패(무시): $e');
    }
  }

  // ── 저장소 ──────────────────────────────────────────────────────

  Future<Directory> _workDir() async {
    final db = await DatabaseService.instance.database;
    final dir = Directory(p.join(p.dirname(db.path), 'restore_work'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _jobFile() async => File(p.join((await _workDir()).path, _jobFileName));

  Future<void> _saveJob(RestoreJob job) async {
    final file = await _jobFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(job.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<void> _deleteJobFile() async {
    final file = await _jobFile();
    if (await file.exists()) await file.delete();
  }

  Future<void> _deleteJob(RestoreJob? job) async {
    try {
      if (job != null && job.copyPath.isNotEmpty) {
        final copy = File(job.copyPath);
        if (await copy.exists()) await copy.delete();
      }
      await _deleteJobFile();
      // 남은 사본 파일(기록 없이 남은 것)도 정리
      final dir = await _workDir();
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('copy_')) await entity.delete();
      }
    } catch (e) {
      debugPrint('🧯 [restore] 작업 정리 실패(다음 시작 때 다시 시도): $e');
    }
  }

  Future<BackupPayload?> _readCopy(RestoreJob job) async {
    if (job.copyPath.isEmpty) return null;
    try {
      final file = File(job.copyPath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (contentFingerprint(content) != job.fingerprint) return null;
      return BackupPayload.decode(content);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _acquire(String token) async =>
      await _channel.invokeMethod<bool>('restoreAcquireLock', {'token': token}) ?? false;

  Future<void> _release(String token) async {
    try {
      await _channel.invokeMethod('restoreReleaseLock', {'token': token});
    } catch (e) {
      debugPrint('🧯 [restore] 잠금 해제 실패: $e');
    }
  }

  static String _newToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// alarms.date와 같은 형식(초 단위, 로케일 무관)의 현재 시각 문자열.
  static String _nowDbString() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year.toString().padLeft(4, '0')}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }
}
