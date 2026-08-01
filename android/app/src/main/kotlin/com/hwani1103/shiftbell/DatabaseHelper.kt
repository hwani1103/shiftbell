// android/app/src/main/kotlin/com/example/shiftbell/DatabaseHelper.kt

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
        private const val DATABASE_VERSION = 14
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
    }

    override fun onCreate(db: SQLiteDatabase) {
        // Flutter에서 관리하므로 비워둠
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Flutter에서 관리하므로 비워둠
    }

    override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Flutter가 이미 업그레이드한 DB를 Native에서 열 때 에러 방지
        Log.w(TAG, "⚠️ DB 버전 다운그레이드 무시: $oldVersion → $newVersion")
    }

    // ⭐ WAL 모드 활성화 (동시 읽기/쓰기 허용)
    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.enableWriteAheadLogging()
        Log.d(TAG, "✅ WAL 모드 활성화")
    }

    // ⭐ CRITICAL FIX: DB 파일이 실제로 디스크에 있는지 확인. Flutter(sqflite)가 이
    // DB의 스키마(테이블 생성)를 전담하는데, Native가 파일이 생기기도 전에
    // readableDatabase/writableDatabase를 먼저 건드리면 SQLiteOpenHelper가 "새 파일을
    // 만들어야 하는 쪽"이 되어버림 - Native의 onCreate()는 비어있어서(Flutter가 관리하므로)
    // 테이블이 하나도 없는 빈 파일이 생기고, 그 파일의 버전만 DATABASE_VERSION(13)으로
    // 찍힘. 그 다음 Flutter가 이 파일을 열면 "새로 만들기"가 아니라 "13→14 업그레이드"로
    // 오판해서, 기본 테이블(alarms/alarm_types/shift_schedule 등)을 만드는 _onCreate를
    // 통째로 건너뛰고 v14 증분 마이그레이션(date_overtime 테이블 추가)만 실행함. 그 결과
    // 기본 테이블이 하나도 없는 DB가 되고, 뒤이은 방어 로직(onOpen의 재생성 체크)이
    // "테이블 없음"을 감지해 _onCreate를 다시 시도하지만, 이미 date_overtime은 만들어져
    // 있어서 "테이블이 이미 존재함" 예외로 앱 초기화 자체가 죽어버림 - 설치 직후 첫 실행이
    // 스플래시 화면에서 멈춘 것처럼 보이다가 프로세스가 죽고 재시작을 반복하던 원인이
    // 바로 이 레이스였음 (실제 기기 logcat에서 이 정확한 예외 체인을 확인함).
    // 파일이 아직 없으면 Native는 아무것도 하지 않고 조용히 스킵 - 이 시점엔 스케줄/알람이
    // 애초에 없는 게 정상(온보딩 전)이라 "데이터 없음"으로 처리하는 게 맞음.
    fun databaseFileExists(): Boolean {
        return appContext.getDatabasePath(DATABASE_NAME).exists()
    }

    // ⭐ CRITICAL FIX: 파일이 "존재"하는 것만으로는 안전하지 않음 - 존재하지만 아직
    // Flutter가 최신 버전까지 마이그레이션을 안 끝낸 상태(예: 방금 업데이트한 구버전
    // 사용자의 옛 DB)일 수 있음. 그 상태에서 Native가 SQLiteOpenHelper로 열면
    // onUpgrade가 비어있어도 db.setVersion(DATABASE_VERSION)이 실행되면서 실제
    // 마이그레이션 없이 버전만 최신으로 찍혀버려서, 뒤이어 Flutter가 열 때 "이미 최신"
    // 으로 오판해 자기 마이그레이션을 통째로 건너뛸 수 있음. 그래서 SQLiteOpenHelper를
    // 아예 거치지 않는 별도의 읽기 전용 연결로 디스크의 실제 버전을 먼저 확인하고,
    // 정확히 DATABASE_VERSION과 같을 때만(=Flutter가 이미 완전히 마이그레이션 끝낸
    // 상태) 진행함. 다르면 Native는 아무것도 안 하고 Flutter가 먼저 열 때까지 기다림.
    // ⭐ CRITICAL FIX #2: OPEN_READONLY로 열었었는데, 이 DB는 WAL 모드라 별도 연결을
    // 읽기 전용으로 여는 게 -wal/-shm 파일 접근 문제로 실패하는 경우가 있음(기기별로
    // 다름). 그러면 catch가 매번 -1을 반환하고, -1은 DATABASE_VERSION과 절대 같을 수
    // 없어서 isDatabaseReady()가 영원히 false → Native의 모든 DB 쓰기(갱신 엔진 포함)가
    // 영구 차단됨. 실제로 이 버그 때문에 자정이 지나도, 20분 전 체크가 돌아도, 앱을
    // 열어도 10일치 알람이 전혀 안 늘어나는 증상이 발생함. READWRITE로 열면(원본 파일과
    // 같은 WAL 상태를 공유하는 정상적인 추가 연결이라) 이 문제가 없음.
    private fun onDiskVersion(): Int {
        return try {
            SQLiteDatabase.openDatabase(
                appContext.getDatabasePath(DATABASE_NAME).path,
                null,
                SQLiteDatabase.OPEN_READWRITE
            ).use { it.version }
        } catch (e: Exception) {
            // ⭐ CRITICAL FIX #3: 이 확인 자체가 실패해도 fail-closed(영구 차단)가 아니라
            // fail-open(그냥 진행)으로 감. 버전 불일치 레이스는 드문 엣지케이스인데,
            // 그걸 막으려던 안전장치가 고장 나서 핵심 기능(알람 갱신)을 영구히 막아버리면
            // 훨씬 더 나쁨 - 안전장치는 실패해도 원래 기능엔 지장 없어야 함.
            Log.w(TAG, "⚠️ 디스크 DB 버전 확인 실패 - 체크 건너뛰고 진행: ${e.message}")
            DATABASE_VERSION
        }
    }

    private fun isDatabaseReady(): Boolean {
        if (!databaseFileExists()) {
            Log.d(TAG, "⏭️ DB 파일 아직 없음(Flutter가 아직 생성 전) - Native는 생성하지 않고 스킵")
            return false
        }
        val disk = onDiskVersion()
        if (disk != DATABASE_VERSION) {
            Log.w(TAG, "⏭️ DB 버전 불일치(disk=$disk, native=$DATABASE_VERSION) - Flutter 마이그레이션 전까지 스킵")
            return false
        }
        return true
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