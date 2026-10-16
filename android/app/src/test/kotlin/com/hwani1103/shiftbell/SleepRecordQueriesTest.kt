package com.hwani1103.shiftbell

import android.database.sqlite.SQLiteDatabase
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class SleepRecordQueriesTest {
    @Test fun legacyAndOffsetRowsUseTheSameRepeatedClockOccurrence() {
        val old = TimeZone.getDefault()
        try {
            for ((zone, local, suffix) in listOf(
                Triple("America/New_York", "2026-11-01T01:30:00", "-05:00"),
                Triple("Europe/Berlin", "2026-10-25T02:30:00", "+01:00"),
                Triple("Europe/London", "2026-10-25T01:30:00", "+00:00"),
                Triple("Australia/Lord_Howe", "2026-04-05T01:45:00", "+10:30")
            )) {
                TimeZone.setDefault(TimeZone.getTimeZone(zone))
                val expected = SleepTimestamp.parse(local + suffix)!!
                assertEquals(zone, expected, SleepTimestamp.parse(local))
                assertEquals(zone, expected, SleepTimestamp.parse(local + ".000000"))
                for (stored in listOf(local, local + suffix)) {
                    SQLiteDatabase.create(null).use { db ->
                        db.execSQL("CREATE TABLE sleep_records(start_time TEXT, end_time TEXT)")
                        db.execSQL("INSERT INTO sleep_records VALUES (?, NULL)", arrayOf(stored))
                        assertFalse(zone, SleepRecordQueries.hasCovering(db, expected - 1))
                        assertTrue(zone, SleepRecordQueries.hasCovering(db, expected))
                        assertTrue(zone, SleepRecordQueries.hasStartingInWindow(db, expected, expected + 1))
                        assertFalse(zone, SleepRecordQueries.hasStartingInWindow(db, expected - 1, expected))
                    }
                }
            }
        } finally { TimeZone.setDefault(old) }
    }
}
