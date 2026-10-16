package com.hwani1103.shiftbell

import android.database.sqlite.SQLiteDatabase

/** Compare instants with the same parser as the writers and Dart reader.
 * SQLite's 'utc' modifier chooses a different overlap for some legacy local
 * timestamps on Android. Never use it to decide whether sleep rows overlap.
 * Stream the small local sleep table; do not allocate an entire history list.
 */
internal object SleepRecordQueries {
    fun hasCovering(db: SQLiteDatabase, atMillis: Long): Boolean =
        db.query("sleep_records", arrayOf("start_time", "end_time"),
            null, null, null, null, null).use { cursor ->
            while (cursor.moveToNext()) {
                val start = SleepTimestamp.parse(cursor.getString(0)) ?: continue
                if (start > atMillis) continue
                if (cursor.isNull(1)) return@use true
                val end = SleepTimestamp.parse(cursor.getString(1)) ?: continue
                if (end >= atMillis) return@use true
            }
            false
        }

    fun hasStartingInWindow(db: SQLiteDatabase, from: Long, to: Long): Boolean =
        db.query("sleep_records", arrayOf("start_time"),
            null, null, null, null, null).use { cursor ->
            while (cursor.moveToNext()) {
                val start = SleepTimestamp.parse(cursor.getString(0)) ?: continue
                if (start >= from && start < to) return@use true
            }
            false
        }
}
