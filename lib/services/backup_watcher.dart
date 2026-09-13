// lib/services/backup_watcher.dart
//
// ⭐ 사용자 데이터 백업("A번 요구사항") - 자동 백업(Layer 3). 설계(백업복구_설계.md
// 5장)대로 "모든 변경마다 파일을 다시 쓰지 않는다" - SQLite의 `PRAGMA data_version`
// (같은 DB 파일을 다른 커넥션에서 열어도, 그 사이 누군가(Dart든 Native든) 뭔가를
// 썼으면 값이 바뀌는 카운터)로 "저장할 필요가 있는지"만 가볍게 확인하고, 실제로
// 바뀐 게 있을 때만 파일을 씀. main.dart가 앱이 background로 전환되는 시점에만
// 이걸 호출함(_MyAppState.didChangeAppLifecycleState) - 매 화면 전환마다 도는 게
// 아니라 훨씬 드묾.
//
// 설정 탭의 "지금 백업" 버튼(수동)도 이 클래스의 backupNow(force: true)를 그대로
// 씀 - 자동/수동이 같은 코드 경로를 타므로 "마지막 백업 시각" 표시가 항상 정확함.
//
// ⚠️ 이 파일도 알람/근무패턴 로직을 전혀 참조하지 않는다(backup_service.dart와
// 동일 원칙) - DatabaseService.database(연결)만 재사용하고 그 안의 알람 관련
// 메서드는 하나도 안 부름.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'backup_service.dart';
import 'backup_storage_service.dart';
import 'database_service.dart';

class BackupWatcher {
  BackupWatcher._();
  static final BackupWatcher instance = BackupWatcher._();

  static const _kLastDataVersionKey = 'backup_last_data_version';
  static const _kLastSavedAtKey = 'backup_last_saved_at';

  /// 백업을 시도한다. [force]가 false(기본, 자동 트리거용)면 마지막 백업 이후
  /// 데이터가 실제로 안 바뀌었으면 아무것도 안 하고 성공으로 취급(스킵도 성공).
  /// [force]가 true(수동 "지금 백업" 버튼용)면 변경 여부와 무관하게 항상 씀.
  Future<bool> backupNow({bool force = false}) async {
    // ⭐ 2026-09-11(사용자 신고 - "자동백업이 실제로 안 되고 있다, 폴더에 예전
    // 파일 하나만 있다") - 이 함수는 실패해도 절대 앱 사용을 막으면 안 돼서
    // 지금까지 모든 실패를 조용히 삼켰는데, 그 결과 "정말 실패하는지, 왜
    // 실패하는지"를 아무도 알 수 없었다. debugPrint는 release 빌드에서도
    // logcat에 그대로 찍히므로(단지 화면엔 안 보일 뿐) 이 로그들만으로 다음
    // 실사용/logcat 캡처에서 정확한 실패 지점을 특정할 수 있게 함 - 동작 자체는
    // 전혀 안 바뀜(로그만 추가).
    try {
      final db = await DatabaseService.instance.database;

      // ⭐ 2026-09-04 - H3 수정(전체_코드_점검_리포트_2026-09-04.md). `PRAGMA
      // data_version`은 "같은 커넥션이 만든 커밋"에는 반응하지 않는다(SQLite
      // 공식 동작) - 앱이 평소 쓰기에도 쓰는 이 커넥션(db)에서 그대로 조회하면
      // Flutter UI에서만 데이터를 바꾼 경우(가장 흔한 패턴) 카운터가 절대 안
      // 바뀌어서 자동 백업이 계속 스킵됨. 별도의 짧은 읽기 전용 커넥션으로 열어서
      // 조회하고 즉시 닫는다.
      final currentVersion = await _readDataVersion(db.path);

      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final lastVersion = prefs.getInt(_kLastDataVersionKey);
        debugPrint('🗄️ [backup] 자동 체크: last=$lastVersion current=$currentVersion');
        if (lastVersion == currentVersion) {
          debugPrint('🗄️ [backup] 스킵 - 데이터 변경 없음');
          return true; // 변경 없음 - 스킵
        }

        // ⭐ 2026-09-01 - "복구하기를 눌러도 계속 빈 백업만 나온다" 버그를
        // 추적하다 추가한 안전장치. 자동 백업(force=false)은 앱이 background로
        // 갈 때마다(설정 탭 진입 전, 온보딩/권한 화면 중, 초기화 직후 등) 조건
        // 없이 발동될 수 있는데, 그 시점에 마침 근무 일정이 비어있으면(아직
        // 설정 전, 또는 방금 "초기화"한 직후) 이전에 저장해둔 "진짜" 백업을
        // 빈 스냅샷으로 조용히 덮어써버린다 - 유일한 백업 파일 하나만 유지하는
        // 설계(백업복구_설계.md 8장)라 한 번 덮이면 예전 데이터는 영영 복구
        // 불가능해진다. 그래서 자동 트리거일 때만 "근무 일정이 비어있으면
        // 아예 쓰지 않고 스킵"하도록 막는다 - 수동 "지금 백업"(force=true)은
        // 사용자가 설정 탭에서 직접 누른 명시적 행동이라 그대로 존중해서 막지
        // 않음(그 화면엔 애초에 일정이 있어야 도달 가능하기도 함).
        final scheduleRows = await db.query('shift_schedule', limit: 1);
        if (scheduleRows.isEmpty) {
          debugPrint('🗄️ [backup] 스킵 - shift_schedule 비어있음');
          return true; // 백업할 유효한 근무 일정 없음 - 스킵
        }
      }

      debugPrint('🗄️ [backup] 쓰기 시작(force=$force)');
      final payload = await BackupService.instance.exportAll();
      final wrote = await BackupStorageService.instance.write(payload.encode());
      debugPrint('🗄️ [backup] 쓰기 결과: $wrote (테이블 ${payload.tables.length}개, 행 ${payload.totalRowCount}개)');
      if (!wrote) return false;

      await prefs.setInt(_kLastDataVersionKey, currentVersion);
      await prefs.setString(_kLastSavedAtKey, DateTime.now().toIso8601String());
      return true;
    } catch (e, st) {
      // ⭐ 백업(특히 자동 트리거) 실패가 앱 사용을 방해하면 안 됨 - 조용히
      // 실패하되, 이제는 최소한 로그로는 남김(위 주석 참고).
      debugPrint('🗄️ [backup] ❌ 예외로 실패: $e\n$st');
      return false;
    }
  }

  /// 앱의 쓰기 커넥션과 별도로 짧게 여는 읽기 전용 커넥션에서 `data_version`을
  /// 읽는다(H3 - 위 backupNow() 주석 참고). 실패하면 예외를 그대로 던져서
  /// 호출부의 catch가 "백업 스킵"으로 처리하게 둔다(조용히 실패해도 무해함).
  ///
  /// ⚠️⚠️ 2026-09-05 - CRITICAL FIX: singleInstance: false를 반드시 넘겨야 함.
  /// sqflite는 openDatabase/openReadOnlyDatabase를 같은 path로 부르면 기본값
  /// (singleInstance: true)일 때 "이미 열려있는 커넥션을 그대로 재사용"한다
  /// (sqflite_common의 factory_mixin.dart - path별 전역 레지스트리에서 기존
  /// helper를 찾아 그 sqfliteDatabase를 그대로 반환, 참조 카운트 없음). 즉 이
  /// 함수가 연 "읽기 전용 커넥션"이 사실은 DatabaseService.database가 쓰는 바로
  /// 그 커넥션이었고, 아래 close()가 그 공유 커넥션을 실제로 네이티브 레벨에서
  /// 닫아버렸음 - 그 순간부터 앱이 죽을 때까지 모든 DB 접근이
  /// DatabaseException(database_closed)로 실패하는 심각한 회귀였음(H3 수정
  /// 당일 발견 - 컨디션/일정관리 탭을 오가거나 앱이 백그라운드로 한 번만 가도
  /// 재현됨). singleInstance: false를 주면 이 전역 레지스트리를 아예 안 타고
  /// 진짜 독립된 커넥션을 여니 안전하게 닫을 수 있음(네이티브 Kotlin
  /// DatabaseHelper도 이미 별도 커넥션으로 같은 파일에 동시 접근하고 있어서,
  /// SQLite 파일 하나에 여러 커넥션이 동시에 붙는 것 자체는 이 앱의 기존
  /// 설계와 같은 패턴).
  Future<int> _readDataVersion(String path) async {
    // ⭐ 2026-09-11 - 자동 트리거(AppLifecycleState.paused)는 하필 앱이 막
    // 배경으로 전환되는 순간이라, 그 직전에 진행 중이던 쓰기 트랜잭션과 아주
    // 드물게 겹쳐 "database is locked" 예외가 날 수 있음(이 창은 짧아서
    // 한 번만 재시도해도 대부분 해소됨). 여기서 조용히 실패시키면 그 백그라운드
    // 전환 한 번의 백업만 스킵되는데, 어차피 위 backupNow()의 콜드 스타트
    // 트리거가 다음 실행 때 다시 시도하므로 완전히 유실되진 않지만, 가능하면
    // 그 자리에서 한 번 더 시도해 성공률을 높인다.
    for (var attempt = 0; attempt < 2; attempt++) {
      Database? versionDb;
      try {
        versionDb = await openReadOnlyDatabase(path, singleInstance: false);
        final rows = await versionDb.rawQuery('PRAGMA data_version');
        return rows.first['data_version'] as int;
      } catch (e) {
        if (attempt == 1) rethrow;
        await Future.delayed(const Duration(milliseconds: 200));
      } finally {
        await versionDb?.close();
      }
    }
    throw StateError('unreachable');
  }

  /// 설정 탭에 "마지막 백업: OOOO" 표시용.
  Future<DateTime?> lastSavedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kLastSavedAtKey);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }
}
