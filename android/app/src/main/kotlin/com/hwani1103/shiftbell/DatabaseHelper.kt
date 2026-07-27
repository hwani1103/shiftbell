// android/app/src/main/kotlin/com/example/shiftbell/DatabaseHelper.kt

package com.hwani1103.shiftbell

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.util.Log

class DatabaseHelper private constructor(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    companion object {
        private const val DATABASE_NAME = "shiftbell.db"
        private const val DATABASE_VERSION = 13  // Flutter와 동일하게 유지
        private const val TAG = "DatabaseHelper"

        @Volatile
        private var INSTANCE: DatabaseHelper? = null

        // ⭐ Device Protected Context 사용
        fun getInstance(context: Context): DatabaseHelper {
            return INSTANCE ?: synchronized(this) {
                val actualContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    context.createDeviceProtectedStorageContext()
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

    // ⭐ 재시도 로직이 포함된 안전한 DB 접근
    fun getReadableDatabaseWithRetry(maxRetries: Int = 3): SQLiteDatabase? {
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