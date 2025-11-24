// android/app/src/main/kotlin/com/example/shiftbell/DatabaseHelper.kt

package com.example.shiftbell

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
        private const val DATABASE_VERSION = 6
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
}