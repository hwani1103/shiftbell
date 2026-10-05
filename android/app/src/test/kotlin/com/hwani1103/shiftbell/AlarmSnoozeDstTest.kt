package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.content.ContentValues
import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File
import java.time.Instant
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(instrumentedPackages = ["com.hwani1103.shiftbell.AlarmActionHelper"])
class AlarmSnoozeDstTest {
    private val originalZone = TimeZone.getDefault()
    private val context: Context = ApplicationProvider.getApplicationContext()

    @After fun cleanup() {
        TimeZone.setDefault(originalZone)
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
    }

    private fun prepare(zone: String, now: String): Long {
        TimeZone.setDefault(TimeZone.getTimeZone(zone))
        val instant = Instant.parse(now).toEpochMilli()
        assertTrue(SystemClock.setCurrentTimeMillis(instant))
        assertEquals(instant, SystemClock.uptimeMillis())
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
        val device = context.createDeviceProtectedStorageContext()
        device.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit()
            .clear().putLong("last_alarm_refresh", instant)
            .putInt(AlarmRefreshEngine.KEY_REFRESH_POLICY_VERSION, AlarmRefreshEngine.REFRESH_POLICY_VERSION)
            .commit()
        val file = device.getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) File(file.path + suffix).delete()
        file.parentFile?.mkdirs()
        File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(file, overwrite = true)
        insert(7, AlarmInstant.format(instant))
        return instant
    }

    private fun insert(id: Int, date: String) {
        DatabaseHelper.getInstance(context).writableDatabase.insertOrThrow("alarms", null, ContentValues().apply {
            put("id", id); put("time", date.substring(11, 16)); put("date", date)
            put("type", "snoozed"); put("alarm_type_id", 1); put("shift_type", "Night"); put("day_offset", 0)
        })
    }

    private fun verify(zone: String, now: String, expected: String) {
        val started = prepare(zone, now)
        val result = AlarmActionHelper.snooze(context, 7, 5)
        assertNotNull(result)
        assertNull(result!!.collisionMessage)
        val db = DatabaseHelper.getInstance(context).writableDatabase
        val stored = db.rawQuery("SELECT date FROM alarms WHERE id = 7", null).use {
            assertTrue(it.moveToFirst()); it.getString(0)
        }
        assertEquals(expected, stored)
        val target = started + 300_000L
        assertEquals(target, AlarmWakeScheduler.parse(stored))
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val wakeTimes = shadowOf(manager).scheduledAlarms.filter {
            it.operation?.let { operation -> shadowOf(operation).savedIntent.data?.toString() } == "shiftbell://alarm/7"
        }.map { it.triggerAtMs }
        assertEquals(listOf(target), wakeTimes)
        db.rawQuery("SELECT scheduled_date, actual_ring_time FROM alarm_history WHERE alarm_id = 7", null).use {
            assertTrue(it.moveToFirst())
            assertEquals(started, AlarmWakeScheduler.parse(it.getString(0)))
            assertEquals(started, AlarmWakeScheduler.parse(it.getString(1)))
        }
        // Re-reading/rearming in another time zone must not reinterpret a snooze.
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"))
        assertEquals(AlarmWakeScheduler.Outcome.SCHEDULED,
            AlarmWakeScheduler.scheduleIfCurrent(context, db, 7, target, "Night"))
        assertEquals(AlarmWakeScheduler.ReceiveDecision.RING,
            AlarmWakeScheduler.decideOnReceive(context, 7, target))
    }

    @Test fun newYorkFirstHour() = verify("America/New_York", "2026-11-01T04:59:00Z", "2026-11-01T01:04:00-04:00")
    @Test fun newYorkClockBack() = verify("America/New_York", "2026-11-01T05:58:00Z", "2026-11-01T01:03:00-05:00")
    @Test fun londonFirstHour() = verify("Europe/London", "2026-10-24T23:59:00Z", "2026-10-25T01:04:00+01:00")
    @Test fun londonClockBack() = verify("Europe/London", "2026-10-25T00:58:00Z", "2026-10-25T01:03:00Z")
    @Test fun springJump() = verify("America/New_York", "2026-03-08T06:58:00Z", "2026-03-08T03:03:00-04:00")
    @Test fun ordinarySeoul() = verify("Asia/Seoul", "2026-10-01T21:58:00Z", "2026-10-02T07:03:00+09:00")

    @Test fun sameClockDifferentOccurrenceDoesNotCollide() {
        prepare("America/New_York", "2026-11-01T04:59:00Z")
        insert(8, "2026-11-01T01:04:00-05:00")
        assertNull(AlarmActionHelper.snooze(context, 7, 5)!!.collisionMessage)
    }

    @Test fun sameInstantDifferentOffsetStillCollides() {
        prepare("America/New_York", "2026-11-01T04:59:00Z")
        insert(8, "2026-11-01T05:04:00Z")
        assertNotNull(AlarmActionHelper.snooze(context, 7, 5)!!.collisionMessage)
    }
}
