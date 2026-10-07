package com.hwani1103.shiftbell

import android.database.Cursor
import android.database.sqlite.SQLiteDatabase

/** Nominal wall slot + shift + day offset. Never use an ID/epoch as identity.
 * Keep the query/terminal policy aligned with fixed_alarm_occurrence.dart. */
internal object FixedAlarmOccurrence {
    private const val TERMINALS = "'swiped','timeout','snoozed','snooze_skipped_existing_alarm','superseded_by_next_alarm'"

    fun readConsumed(db: SQLiteDatabase, start: String, end: String): Set<String> {
        db.execSQL("""
            INSERT OR IGNORE INTO fixed_alarm_consumptions
              (slot_time, shift_type, day_offset, recorded_at)
            SELECT slot_time, shift_type, day_offset, ? FROM (
            SELECT fixed_slot_time AS slot_time, shift_type, day_offset
            FROM alarm_history
            WHERE fixed_slot_time >= ? AND fixed_slot_time < ?
              AND dismiss_type IN ($TERMINALS)
            UNION
            SELECT substr(h.scheduled_date, 1, 16) || ':00' AS slot_time,
              h.shift_type, h.day_offset
            FROM alarm_history h
            WHERE h.fixed_slot_time IS NULL
              AND h.scheduled_date >= ? AND h.scheduled_date < ?
              AND h.dismiss_type IN ($TERMINALS)
              AND EXISTS (
                SELECT 1 FROM alarm_creation_log c
                WHERE c.alarm_id = h.alarm_id AND c.source = 'auto'
                  AND substr(c.scheduled_date, 1, 19) = substr(h.scheduled_date, 1, 19)
                  AND c.scheduled_time = h.scheduled_time
                  AND c.shift_type = h.shift_type AND c.day_offset = h.day_offset
              )
              AND NOT EXISTS (
                SELECT 1 FROM alarm_creation_log c
                WHERE c.alarm_id = h.alarm_id AND c.source != 'auto'
                  AND substr(c.scheduled_date, 1, 19) = substr(h.scheduled_date, 1, 19)
                  AND c.scheduled_time = h.scheduled_time
                  AND c.shift_type = h.shift_type AND c.day_offset = h.day_offset
              )
            ) WHERE shift_type IS NOT NULL
        """.trimIndent(), arrayOf(java.time.Instant.now().toString(), start, end, start, end))
        val result = mutableSetOf<String>()
        db.rawQuery("SELECT slot_time,shift_type,day_offset FROM fixed_alarm_consumptions WHERE slot_time >= ? AND slot_time < ?",
            arrayOf(start, end)).use { cursor ->
            while (cursor.moveToNext()) {
                if (!cursor.isNull(0) && !cursor.isNull(1))
                    result += AlarmRefreshEngine.slotKey(cursor.getString(0), cursor.getString(1), cursor.getInt(2))
            }
        }
        return result
    }

    fun record(db: SQLiteDatabase, slot: String?, shift: String, offset: Int, reason: String) {
        if (slot == null || reason !in setOf("swiped", "timeout", "snoozed",
                "snooze_skipped_existing_alarm", "superseded_by_next_alarm")) return
        db.execSQL("INSERT OR IGNORE INTO fixed_alarm_consumptions(slot_time,shift_type,day_offset,recorded_at) VALUES(?,?,?,?)",
            arrayOf<Any>(slot, shift, offset, java.time.Instant.now().toString()))
    }

    fun fromRow(row: Cursor): String? {
        val type = row.getString(row.getColumnIndexOrThrow("type"))
        if (type != "fixed" && type != "snoozed") return null
        val explicit = row.getString(row.getColumnIndexOrThrow("fixed_slot_time"))
        if (explicit != null) return explicit
        if (type != "fixed") return null
        val date = row.getString(row.getColumnIndexOrThrow("date")) ?: return null
        return if (date.length >= 16) date.substring(0, 16) + ":00" else null
    }
}
