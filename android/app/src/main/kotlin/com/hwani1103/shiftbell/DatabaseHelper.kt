// android/app/src/main/kotlin/com/hwani1103/shiftbell/DatabaseHelper.kt

package com.hwani1103.shiftbell

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.util.Log

class DatabaseHelper private constructor(private val appContext: Context) : SQLiteOpenHelper(
    appContext,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    companion object {
        private const val DATABASE_NAME = "shiftbell.db"
        // ⭐ CRITICAL FIX: 반드시 database_service.dart의 `version:`과 정확히 같은 값이어야 함.
        // 예전엔 13(Flutter는 14)이었는데 - SQLiteOpenHelper는 onUpgrade/onDowngrade가
        // 빈 함수라도, 여는 순간 무조건 db.setVersion(DATABASE_VERSION)을 실행해버림.
        // 그래서 예전 버전(예: v12) DB를 Native가 Flutter보다 먼저 열면, 실제 마이그레이션은
        // 하나도 안 하면서 파일 버전만 13으로 찍어버렸고, 그 뒤 Flutter가 열 때 "12→14
        // 정상 마이그레이션"이 아니라 "13→14"만 실행돼서 v13 미만 구간의 마이그레이션
        // (alarm_creation_log 테이블 생성 등)이 영구적으로 스킵될 수 있었음. 두 값이
        // 항상 일치해야 이런 무의미한 버전 찍힘 자체가 무해해짐(찍어봐야 같은 값).
        // ⚠️ Flutter DB 버전을 올릴 때마다 이 값도 반드시 같이 올릴 것.
        // ⭐ 2026-08-12: 친구공유 커밋(DB v16, friends 테이블 추가)에서 database_service.dart의
        // version:은 16으로 올렸는데 이 값은 15로 남아있었음 - 정확히 위 주석이 경고하던
        // 그 사고가 재발한 것. SQLiteOpenHelper의 onDowngrade는 오버라이드 안 하면 기본
        // 구현이 예외를 던지는데(newVersion(15) < oldVersion(16)이면 "다운그레이드"로 판정),
        // Flutter가 한 번이라도 먼저 열어서 DB 파일이 v16으로 올라간 뒤부턴 위젯(Native가
        // DatabaseHelper로 여는 모든 경로)이 DB를 열 때마다 이 예외로 실패 → readSchedule()이
        // catch해서 null 반환 → "근무 스케줄을 먼저 설정해주세요"가 스케줄 존재 여부와
        // 무관하게 항상 뜸. 위젯이 "친구공유 버전 도입 즈음부터" 안 됐다는 사용자 증언과
        // 정확히 일치함.
        // ⭐ 2026-08-13: 친구공유 v1(Firestore) 전환으로 friends 테이블 스키마가 바뀌면서
        // database_service.dart의 version:이 17로 다시 올라감 - 같은 커밋에서 이 값도 같이 올림.
        // ⭐ 2026-08-20: "근무명 색상 변경" 기능 복원(custom_shift_colors 컬럼 추가)으로
        // database_service.dart의 version:이 18로 올라갔는데, 이 값을 같이 안 올려서 정확히
        // 위 주석이 세 번째로 경고하던 그 사고가 또 재발함(2026-08-12, 이번이 두 번째
        // 재발). "근무명 색상 변경 적용한 버전부터 위젯이 갑자기 안 됨(항상 '근무
        // 스케줄을 먼저 설정해주세요') 증상으로 발견 - disk=18, native=17이라
        // isDatabaseReady()가 항상 false를 반환해 위젯이 스케줄 유무와 무관하게 영원히
        // "없음"으로 봤던 것. Flutter DB 버전 올릴 때 이 값도 반드시 같이 올릴 것 (재발
        // 방지책은 project_alarm_reliability_overhaul 메모리 참고).
        // ⭐ 2026-08-27 - 일정관리 탭 영구 저장(date_schedules 테이블 신설)으로
        // database_service.dart의 version:이 20으로 올라가서 같이 올림. Native는 이
        // 테이블을 아직 안 읽지만(위젯에 일정 표시 기능 없음), 그래도 반드시 같이
        // 올려야 함 - "Native가 새 컬럼/테이블을 안 쓰니까 안 올려도 된다"가 정확히
        // 세 번 재발했던 그 착각임 (DB_스키마_변경_가이드.md 참고).
        // ⭐ 2026-08-31 - 컨디션 매니저(condition_shift_times 테이블 신설)로
        // database_service.dart의 version:이 21로 올라가서 같이 올림. Native는 이
        // 테이블을 전혀 안 읽음(컨디션 매니저는 Flutter 전용 기능) - 그래도 위와
        // 동일한 이유로 반드시 같이 올림.
        // ⭐ 2026-08-31(2차) - 실제 수면 기록/자동 추정(sleep_records/
        // sleep_expected_bedtime 테이블 신설)으로 version:이 22로 올라가서 같이
        // 올림. 이번엔 Native가 이 테이블들을 직접 읽고 쓴다(SleepDetectionReceiver.kt/
        // SleepWidgetActionReceiver.kt) - 수면기록_자동추정_설계.md 참고.
        // ⭐ 2026-08-31(3차) - "D번 요구사항"(일정관리 탭 일정 생성 팝업 5분
        // 미세조정)에서 처음엔 date_schedules.slot_minutes 컬럼(v23)을 추가했으나,
        // 그 값이 사용자 확인 결과 startMinutes만으로 매번 계산 가능한 순수
        // 파생값으로 정정되어(date_schedule.dart의 computeSlotMinutes 참고)
        // 저장할 필요 자체가 없어짐 - 그 마이그레이션을 되돌려서 다시 22.
        // ⭐ 2026-09-12 - "일정에 맞춰서 알림받기" 실제 구현(그동안 date_schedules에
        // notify_enabled/notify_offset_minutes 컬럼도, 예약 로직도 없이 UI만 있던
        // 목업이었음 - 전체근무표_개선안_및_일정알림_설계메모.md 2장 참고). 위 되돌린
        // v23과 번호는 같지만 내용은 다름(그땐 slot_minutes, 이번엔 notify_* 컬럼).
        // 이번엔 Native가 date_schedules를 직접 읽는다(ScheduleNotificationScheduler.kt -
        // 재부팅 시 AlarmManager 알람이 전부 사라지므로 DirectBootReceiver에서 재예약
        // 필요) - v20/v21의 "Native 미사용" 전제가 이 테이블에 한해 끝남.
        // ⭐ 2026-09-14 (G0, 출시전_코드감사_검토결과_v4 #1/#8/#31) - v24(alarm_overrides,
        // 개별 알람 예외). 그리고 이번부터 Native도 직접 마이그레이션한다: 위 사고들의
        // 뿌리는 "Native는 Flutter가 올려줄 때까지 DB를 못 쓴다"는 구조였고, 그 때문에
        // 업데이트 후 앱을 안 열거나 잠금 해제 전에 재부팅하면 알람 설정/스누즈/이력을
        // 못 읽었음(C01). 이제 onUpgrade가 Flutter와 같은 SQL 원본(assets/db/migrations.json)을
        // DbMigrationRunner로 실행함. 이 값은 여전히 database_service.dart의 version:,
        // migrations.json의 targetVersion과 같아야 하고 checkDartKotlinSync가 빌드 때 검사함.
        private const val DATABASE_VERSION = 24
        private const val TAG = "DatabaseHelper"

        @Volatile
        private var INSTANCE: DatabaseHelper? = null

        // ⭐ Device Protected Context 사용
        // ⭐ FIX: >= N 분기에서도 applicationContext를 먼저 거치도록 함 - 안 그러면
        // MainActivity가 최초 호출자일 때 이 프로세스 생명주기 내내 살아있는 싱글턴이
        // Activity 인스턴스를 계속 붙들고 있게 됨(메모리 누수).
        fun getInstance(context: Context): DatabaseHelper {
            return INSTANCE ?: synchronized(this) {
                val actualContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    context.applicationContext.createDeviceProtectedStorageContext()
                } else {
                    context.applicationContext
                }

                INSTANCE ?: DatabaseHelper(actualContext).also {
                    INSTANCE = it
                }
            }
        }

        // ⭐ 2026-09-12 - 테스트 전용. Robolectric은 테스트 메서드마다 native SQLite
        // 연결 풀을 새로 초기화하지만, 이 Kotlin companion object의 정적 INSTANCE는
        // JVM 프로세스/클래스로더 생명주기를 따라가서 테스트 메서드 사이에도 그대로
        // 남는다 - 그 결과 이전 테스트에서 이미 무효화된 커넥션 포인터를 든 채인
        // 낡은 DatabaseHelper 객체를 다음 테스트가 그대로 재사용하다가
        // "Illegal connection pointer" 오류로 깨짐(AlarmRefreshEngineH2Test.kt에서
        // 실제로 겪음). 프로덕션 코드 경로는 이 함수를 전혀 호출하지 않음 - 테스트의
        // @Before/@After에서만 호출해서 매 테스트마다 새 인스턴스로 시작하게 함.
        internal fun resetInstanceForTest() {
            try {
                INSTANCE?.close()
            } catch (e: Exception) {
                // 이미 깨진 연결을 닫으려다 나는 예외는 무시 - 테스트 격리가 목적이지
                // 정상 종료 여부가 중요한 게 아님.
            }
            INSTANCE = null
        }
    }

    // ⭐ 2026-09-14 (G0) - 예전엔 빈 함수였음. SQLiteOpenHelper는 user_version이 0인 파일을
    // 열면 onCreate 뒤에 버전을 최신으로 찍는데, Native는 테이블을 만들지 않으므로 "테이블이
    // 하나도 없는 최신 버전 DB"가 생길 수 있었음(아래 databaseFileExists() 주석의 사고).
    // 신규 설치 DB 생성은 Flutter(database_service.dart _onCreate) 전담 - 여기서는 예외를 던져
    // 트랜잭션째 롤백시킴(버전도 안 찍힘). isDatabaseReady()가 파일 없음/버전 0을 먼저
    // 걸러내므로 정상 경로에서는 호출되지 않음.
    override fun onCreate(db: SQLiteDatabase) {
        throw DbMigrationException("Native는 DB를 새로 만들지 않음(user_version=0) - Flutter가 생성해야 함")
    }

    // ⭐ 2026-09-14 (G0, v4 #1) - 예전엔 빈 함수라 "마이그레이션 없이 버전만 찍힘" 위험 때문에
    // 게이트가 정확히 같은 버전일 때만 열었음. 이제 Flutter와 같은 SQL 원본을 실행함.
    // SQLiteOpenHelper는 이 호출과 setVersion()을 한 트랜잭션(BEGIN EXCLUSIVE)으로 묶으므로
    // 스키마와 버전이 함께 성공하거나 함께 롤백됨. 실패하면 예외가 그대로 나가서 해당 DB
    // 접근만 실패(호출부의 기존 fail-safe 동작)하고, 버전이 낮게 남아 다음 접근 때 재시도됨.
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // SQLiteOpenHelper는 oldVersion을 트랜잭션(쓰기 잠금) 밖에서 읽음 - 그사이 Flutter가
        // 먼저 올렸을 수 있으므로 잠금을 잡은 지금 다시 읽어서 그 값 기준으로 진행.
        // (sqflite는 스스로 잠금 안에서 다시 읽으므로 반대 방향은 이미 안전함.)
        val current = db.version
        if (current == newVersion) {
            Log.i(TAG, "⏭️ 잠금 획득 사이 이미 v${newVersion}으로 올라가 있음(Flutter가 먼저 실행) - 건너뜀")
            return
        }
        if (current > newVersion) {
            throw DbMigrationException("잠금 획득 후 확인한 버전(v$current)이 Native(v$newVersion)보다 높음 - 다운그레이드 금지")
        }
        if (current != oldVersion) {
            Log.w(TAG, "⚠️ 버전이 잠금 전후로 다름(v$oldVersion → v$current) - v$current 기준으로 진행")
        }
        Log.i(TAG, "🔧 Native 마이그레이션 시작 v$current → v$newVersion")
        DbMigrationRunner.migrate(db, DbMigrationScript.load(appContext), current, newVersion)
        Log.i(TAG, "✅ Native 마이그레이션 완료 v$current → v$newVersion")
    }

    // ⭐ 2026-09-14 (G0, v4 #1) - 예전엔 경고 로그만 남기고 무시해서, 더 높은 버전 DB를 열면
    // SQLiteOpenHelper가 버전을 낮게 찍어버릴 수 있었음. 예외로 막아 버전을 건드리지 않음.
    override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        throw DbMigrationException("DB 다운그레이드 금지: disk v$oldVersion > native v$newVersion")
    }

    // ⭐ WAL 모드 활성화 (동시 읽기/쓰기 허용)
    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.enableWriteAheadLogging()
        Log.d(TAG, "✅ WAL 모드 활성화")
    }

    // ⭐ 2026-09-14 (G0, v4 #1-7/#8) - 버전은 최신인데 컬럼/테이블/인덱스가 빠진 DB(과거 Dart가
    // ALTER 실패를 삼키던 시절에 생겼을 수 있음)를 Native가 먼저 열면 onUpgrade가 안 불리므로
    // 여기서 비파괴 repair만 실행함. 과거 마이그레이션 재실행은 절대 안 함(v17 DROP friends 등).
    // 없는 게 없으면 읽기만 하고 끝남. SQL 원본 자체를 못 읽는 경우(자산 누락)는 복구만
    // 건너뛰고 DB는 계속 쓰게 둠 - 복구 불가가 알람 재생까지 막으면 안 됨. 복구 SQL 실행
    // 실패는 그대로 던짐(해당 접근만 실패, 다음 접근 때 재시도).
    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        val script = try {
            DbMigrationScript.load(appContext)
        } catch (e: Exception) {
            Log.e(TAG, "❌ SQL 원본을 못 읽어 스키마 복구 건너뜀: ${e.message}")
            return
        }
        DbMigrationRunner.repair(db, script)
    }

    // ⭐ CRITICAL FIX: DB 파일이 실제로 디스크에 있는지 확인. Flutter(sqflite)가 신규 설치
    // DB의 생성(테이블 생성)을 전담하는데, Native가 파일이 생기기도 전에
    // readableDatabase/writableDatabase를 먼저 건드리면 SQLiteOpenHelper가 "새 파일을
    // 만들어야 하는 쪽"이 되어버림 - 예전 Native의 onCreate()는 비어있어서 테이블이 하나도
    // 없는 빈 파일이 생기고, 그 파일의 버전만 최신으로 찍혔음. 그 다음 Flutter가 이 파일을
    // 열면 "새로 만들기"가 아니라 "업그레이드"로 오판해서 기본 테이블을 만드는 _onCreate를
    // 통째로 건너뛰었고, 설치 직후 첫 실행이 스플래시에서 멈춘 것처럼 보이다가 프로세스가
    // 죽고 재시작을 반복했음(실제 기기 logcat에서 확인한 레이스). 지금은 onCreate가 예외라
    // 빈 파일에 버전이 찍히진 않지만, 파일 자체를 만들지 않도록 이 가드는 그대로 유지함.
    // 파일이 아직 없으면 Native는 아무것도 하지 않고 조용히 스킵 - 이 시점엔 스케줄/알람이
    // 애초에 없는 게 정상(온보딩 전)이라 "데이터 없음"으로 처리하는 게 맞음.
    fun databaseFileExists(): Boolean {
        return appContext.getDatabasePath(DATABASE_NAME).exists()
    }

    // ⭐ SQLiteOpenHelper를 거치지 않는 별도 연결로 디스크의 실제 버전을 먼저 확인.
    // ⭐ CRITICAL FIX #2: OPEN_READONLY로 열었었는데, 이 DB는 WAL 모드라 별도 연결을
    // 읽기 전용으로 여는 게 -wal/-shm 파일 접근 문제로 실패하는 경우가 있음(기기별로
    // 다름). READWRITE로 열면(원본 파일과 같은 WAL 상태를 공유하는 정상적인 추가 연결이라)
    // 이 문제가 없음.
    // ⭐ 2026-09-14 (G0, v4 #1-5) - 확인 실패 시 예전엔 "최신 버전"이라고 가정(fail-open)했는데,
    // 그러면 실제로 낮은 버전 DB도 최신인 척 통과할 수 있었음. 이제 null을 반환하고, 판단은
    // 헬퍼의 실제 open에 맡김(낮으면 onUpgrade가 마이그레이션, 0/더 높으면 onCreate/onDowngrade가
    // 예외 → 해당 호출만 실패). 확인 실패가 핵심 기능을 영구 차단하지 않는다는 원래 의도는 유지.
    private fun onDiskVersion(): Int? {
        return try {
            SQLiteDatabase.openDatabase(
                appContext.getDatabasePath(DATABASE_NAME).path,
                null,
                SQLiteDatabase.OPEN_READWRITE
            ).use { it.version }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ 디스크 DB 버전 확인 실패 - 최신으로 가정하지 않고 헬퍼 open에서 판단: ${e.message}")
            null
        }
    }

    // ⭐ 2026-09-14 (G0, v4 #1-5) - 게이트 교체. 예전엔 "디스크 버전 == DATABASE_VERSION"일 때만
    // 열었고(Flutter가 마이그레이션을 끝낼 때까지 Native 전면 차단), 이게 C01의 원인이었음.
    //  - 파일 없음 → 스킵(Flutter가 신규 생성 전)
    //  - 버전 0 → 스킵(Flutter가 신규 생성 중이거나 비정상 파일 - Native는 만들지 않음)
    //  - 디스크 > Native → 스킵(다운그레이드 방지)
    //  - 디스크 < Native → 진행(헬퍼 open 안에서 onUpgrade가 마이그레이션)
    //  - 같음 / 확인 실패 → 진행
    private fun isDatabaseReady(): Boolean {
        if (!databaseFileExists()) {
            Log.d(TAG, "⏭️ DB 파일 아직 없음(Flutter가 아직 생성 전) - Native는 생성하지 않고 스킵")
            return false
        }
        val disk = onDiskVersion() ?: return true
        return when {
            disk == 0 -> {
                Log.w(TAG, "⏭️ DB user_version=0(Flutter 신규 생성 중이거나 비정상) - Native는 생성하지 않고 스킵")
                false
            }
            disk > DATABASE_VERSION -> {
                Log.w(TAG, "⏭️ 디스크 DB(v$disk)가 Native(v$DATABASE_VERSION)보다 높음 - 다운그레이드 방지로 스킵")
                false
            }
            disk < DATABASE_VERSION -> {
                Log.i(TAG, "🔧 디스크 DB v$disk < Native v$DATABASE_VERSION - 열면서 마이그레이션 진행")
                true
            }
            else -> true
        }
    }

    // ⭐ 재시도 로직이 포함된 안전한 DB 접근
    fun getReadableDatabaseWithRetry(maxRetries: Int = 3): SQLiteDatabase? {
        if (!isDatabaseReady()) return null
        var retries = 0
        while (retries < maxRetries) {
            try {
                return readableDatabase
            } catch (e: Exception) {
                retries++
                Log.w(TAG, "⚠️ DB 읽기 시도 $retries/$maxRetries 실패: ${e.message}")
                if (retries < maxRetries) {
                    Thread.sleep(100L * retries)  // 100ms, 200ms, 300ms 대기
                }
            }
        }
        Log.e(TAG, "❌ DB 읽기 최종 실패")
        return null
    }

    fun getWritableDatabaseWithRetry(maxRetries: Int = 3): SQLiteDatabase? {
        if (!isDatabaseReady()) return null
        var retries = 0
        while (retries < maxRetries) {
            try {
                return writableDatabase
            } catch (e: Exception) {
                retries++
                Log.w(TAG, "⚠️ DB 쓰기 시도 $retries/$maxRetries 실패: ${e.message}")
                if (retries < maxRetries) {
                    Thread.sleep(100L * retries)
                }
            }
        }
        Log.e(TAG, "❌ DB 쓰기 최종 실패")
        return null
    }

    // ⭐ 중복 알람 체크: 동일한 시각에 다른 알람이 이미 등록되어 있는지 확인
    // ⭐ CRITICAL FIX: Context를 받아 내부적으로 커넥션을 열고 닫는 방식이었는데,
    // DatabaseHelper가 싱글턴이라 이미 열려있는 커넥션(getWritableDatabase로 연 것)과
    // 같은 커넥션을 공유함. 이 함수가 끝나면서 그 커넥션을 닫아버리면, 이 함수를
    // "이미 DB를 열어둔 상태"에서 호출한 쪽(AlarmActionHelper.snooze 등)이 그 다음
    // 작업(트랜잭션 등)을 이미 닫힌 커넥션으로 시도하다 예외가 나서 조용히 실패했음
    // (스누즈를 눌러도 DB/이력이 하나도 안 남던 버그의 원인). 그래서 커넥션을 직접
    // 열고 닫지 않고, 호출부가 이미 갖고 있는 db를 그대로 재사용하도록 바꿈.
    fun isTimeConflict(db: SQLiteDatabase, targetTimestamp: Long, excludeId: Int? = null): Boolean {
        var cursor: android.database.Cursor? = null

        return try {
            val dateStr = java.text.SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                java.util.Locale.getDefault()
            ).format(java.util.Date(targetTimestamp))

            cursor = if (excludeId != null) {
                db.query(
                    "alarms",
                    arrayOf("id"),
                    "date = ? AND id != ?",
                    arrayOf(dateStr, excludeId.toString()),
                    null, null, null
                )
            } else {
                db.query(
                    "alarms",
                    arrayOf("id"),
                    "date = ?",
                    arrayOf(dateStr),
                    null, null, null
                )
            }

            cursor.count > 0
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ 시간 충돌 체크 실패", e)
            false
        } finally {
            cursor?.close()
        }
    }

}
