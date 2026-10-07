package com.hwani1103.shiftbell

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import java.io.File
import java.time.Instant
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
class TimezoneConsumedAlarmTest {
    private val originalZone = TimeZone.getDefault()
    private lateinit var context: Context
    private lateinit var db: SQLiteDatabase

    @Before fun setup() {
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
        context = ApplicationProvider.getApplicationContext()
        val dc = context.createDeviceProtectedStorageContext()
        dc.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit().clear().commit()
        dc.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit()
            .putLong("last_alarm_refresh", System.currentTimeMillis())
            .putInt(AlarmRefreshEngine.KEY_REFRESH_POLICY_VERSION, AlarmRefreshEngine.REFRESH_POLICY_VERSION).commit()
        val path = dc.getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) File(path.path + suffix).delete()
        path.parentFile?.mkdirs()
        File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(path, true)
        db = DatabaseHelper.getInstance(context).writableDatabase
        for (table in listOf("alarms", "alarm_history", "alarm_creation_log", "alarm_overrides",
            "shift_schedule", "shift_alarm_templates", "fixed_alarm_consumptions")) db.delete(table, null, null)
        db.insertOrThrow("shift_schedule", null, ContentValues().apply {
            put("id", 1); put("is_regular", 0)
            put("assigned_dates", "{\"2026-10-05\":\"Night\",\"2026-10-06\":\"Night\"}")
        })
        for (time in listOf("16:40", "17:10")) db.insertOrThrow("shift_alarm_templates", null, ContentValues().apply {
            put("shift_type", "Night"); put("time", time); put("alarm_type_id", 3); put("day_offset", 0)
        })
    }

    @After fun teardown() {
        TimeZone.setDefault(originalZone)
        RingingAlarmTracker.resetMemoryForTest()
        DatabaseHelper.resetInstanceForTest()
    }

    private fun seedEnded() {
        db.execSQL("INSERT INTO alarm_creation_log(alarm_id,scheduled_date,scheduled_time,shift_type,alarm_type_id,source,created_at,day_offset) VALUES(43,'2026-10-05T16:40:00','16:40','Night',3,'auto','2026-10-01T00:00:00',0)")
        db.execSQL("INSERT INTO alarm_history(alarm_id,scheduled_date,scheduled_time,shift_type,actual_ring_time,dismiss_type,created_at,day_offset) VALUES(43,'2026-10-05T16:40:00','16:40','Night','2026-10-05T16:40:34+09:00','swiped','2026-10-05T16:40:34+09:00',0)")
    }

    private fun slots(): List<String> {
        val result = mutableListOf<String>()
        db.rawQuery("SELECT substr(date,1,16) FROM alarms ORDER BY date", null).use { c ->
            while (c.moveToNext()) result += c.getString(0)
        }
        return result
    }

    private fun refreshInHonolulu() {
        TimeZone.setDefault(TimeZone.getTimeZone("Pacific/Honolulu"))
        AlarmRefreshEngine.doRefresh(context, scheduleNativeAlarmOverride = { _, _, _, _ -> },
            nowMillis = Instant.parse("2026-10-06T02:20:00Z").toEpochMilli())
    }

    @Test fun endedSeoulSlotDoesNotReappearWithNewIdInHonolulu() {
        seedEnded()
        refreshInHonolulu()
        assertFalse("An ended occurrence must not be recreated", "2026-10-05T16:40" in slots())
        assertEquals(listOf("2026-10-05T17:10", "2026-10-06T16:40", "2026-10-06T17:10"), slots())
    }

    @Test fun unhandledSlotsStillGenerateNormally() {
        refreshInHonolulu()
        assertEquals(listOf("2026-10-05T16:40", "2026-10-05T17:10", "2026-10-06T16:40", "2026-10-06T17:10"), slots())
    }

    private fun seedFixed(slot: String = "2026-10-05T16:40:00") {
        db.execSQL("INSERT INTO alarms(id,time,date,type,alarm_type_id,shift_type,day_offset,fixed_slot_time) VALUES(43,'16:40','2026-10-05T16:40:00','fixed',3,'Night',0,?)", arrayOf(slot))
    }

    private fun scalar(sql: String): Int = db.rawQuery(sql, null).use { it.moveToFirst(); it.getInt(0) }

    @Test fun nativeDismissAtomicallyRecordsOccurrenceWithoutDependingOnCreationLog() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"))
        seedFixed()
        AlarmActionHelper.dismiss(context, 43, "swiped")
        assertEquals(0, scalar("SELECT count(*) FROM alarms WHERE id=43"))
        assertEquals(1, scalar("SELECT count(*) FROM fixed_alarm_consumptions WHERE slot_time='2026-10-05T16:40:00'"))
        db.delete("alarm_history", null, null) // visible history is independent
        refreshInHonolulu()
        assertFalse("2026-10-05T16:40" in slots())
        assertTrue("2026-10-06T16:40" in slots())
    }

    @Test fun nativeSnoozeConsumesOriginalButPreservesAbsoluteRering() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"))
        seedFixed()
        val target = Instant.parse("2026-10-06T02:55:00Z").toEpochMilli()
        val result = AlarmActionHelper.snoozeAt(context, 43, target,
            scheduleFn = { _, _, _, _ -> })
        assertTrue(result is SnoozeExecution.Scheduled)
        refreshInHonolulu()
        assertEquals(1, scalar("SELECT count(*) FROM alarms WHERE id=43 AND type='snoozed'"))
        db.rawQuery("SELECT date,fixed_slot_time FROM alarms WHERE id=43", null).use { c ->
            assertTrue(c.moveToFirst())
            assertEquals(target, AlarmWakeScheduler.parse(c.getString(0)))
            assertEquals("2026-10-05T16:40:00", c.getString(1))
        }
        assertEquals(0, scalar("SELECT count(*) FROM alarms WHERE type='fixed' AND date LIKE '2026-10-05T16:40%'"))
    }

    @Test fun replacementAndCustomHistoryDoNotSuppressFixedAlarm() {
        seedEnded()
        db.execSQL("UPDATE alarm_history SET dismiss_type='superseded'")
        refreshInHonolulu()
        assertEquals(4, slots().size)
        db.delete("alarms", null, null)
        db.execSQL("UPDATE alarm_history SET dismiss_type='swiped'")
        db.execSQL("UPDATE alarm_creation_log SET source='manual' WHERE alarm_id=43")
        refreshInHonolulu()
        assertEquals(4, slots().size)
    }

    @Test fun legacySameSlotIdReuseWithCustomEvidenceCannotSuppressNormalFixed() {
        seedEnded()
        db.execSQL("INSERT INTO alarm_creation_log(alarm_id,scheduled_date,scheduled_time,shift_type,alarm_type_id,source,created_at,day_offset) VALUES(43,'2026-10-05T16:40:00','16:40','Night',3,'custom_preset','2026-10-05T15:00:00',0)")
        refreshInHonolulu()
        assertEquals(4, slots().size)
        assertEquals(0, scalar("SELECT count(*) FROM fixed_alarm_consumptions"))
    }

    @Test fun consumedRecordFailureCannotCommitSnoozeOrEndHistory() {
        seedFixed()
        db.execSQL("CREATE TRIGGER reject_consumption BEFORE INSERT ON fixed_alarm_consumptions BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        try {
            val result = AlarmActionHelper.snoozeAt(context, 43,
                Instant.parse("2026-10-06T02:55:00Z").toEpochMilli(), scheduleFn = { _, _, _, _ -> fail("OS before commit") })
            assertTrue(result is SnoozeExecution.DbFailed)
            assertEquals(1, scalar("SELECT count(*) FROM alarms WHERE id=43 AND type='fixed'"))
            assertEquals(0, scalar("SELECT count(*) FROM alarm_history"))
            assertEquals(0, scalar("SELECT count(*) FROM fixed_alarm_consumptions"))
        } finally { db.execSQL("DROP TRIGGER reject_consumption") }
    }

    @Test fun nominalGapSlotIsRetainedInsteadOfResolvedClockForEveryDayOffset() {
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        for (offset in listOf(-1, 0, 1)) {
            val day = java.time.LocalDate.parse("2026-03-08").minusDays(offset.toLong()).toString()
            val schedule = AlarmRefreshEngine.ScheduleData(false, emptyList(), 0, 0, mapOf(day to "Night"))
            val templates = mapOf("Night" to listOf(AlarmRefreshEngine.TemplateEntry("02:30", 3, offset)))
            val now = Instant.parse("2026-03-08T05:00:00Z").toEpochMilli()
            val candidate = AlarmRefreshEngine.computeDesiredAlarms(schedule, templates, nowMillis = now).single()
            assertEquals("03:30", candidate.time)
            assertEquals("2026-03-08T02:30:00", candidate.fixedSlotTime)
            val consumed = setOf(AlarmRefreshEngine.slotKey(candidate.fixedSlotTime, "Night", offset))
            assertTrue(AlarmRefreshEngine.computeDesiredAlarms(schedule, templates, nowMillis = now,
                consumedOccurrences = consumed).isEmpty())
        }
    }
}
