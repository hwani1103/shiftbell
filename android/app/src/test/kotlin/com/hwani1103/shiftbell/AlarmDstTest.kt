package com.hwani1103.shiftbell

import org.json.JSONArray
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class AlarmDstTest {
    private val originalZone = TimeZone.getDefault()
    @After fun restoreZone() { TimeZone.setDefault(originalZone) }

    @Test fun sharedFixturesAgreeAcrossGenerationStorageAndDayOffsets() {
        val cases = JSONArray(File(G0TestSupport.repoRoot, "test/fixtures/alarm_dst_cases.json").readText())
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val zone = ZoneId.of(c.getString("zone"))
            TimeZone.setDefault(TimeZone.getTimeZone(zone))
            val wall = LocalDateTime.parse(c.getString("wall"))
            val expected = Instant.parse(c.getString("utc")).toEpochMilli()
            assertEquals(c.toString(), expected, AlarmWallTime.resolve(wall.year, wall.monthValue,
                wall.dayOfMonth, wall.hour, wall.minute))
            assertEquals(expected, AlarmWakeScheduler.parse(c.getString("wall")))
            for (offset in listOf(-1, 0, 1)) {
                val schedule = AlarmRefreshEngine.ScheduleData(false, emptyList(), 0, 0,
                    mapOf(wall.toLocalDate().minusDays(offset.toLong()).toString() to "Night"))
                val templates = mapOf("Night" to listOf(AlarmRefreshEngine.TemplateEntry(
                    c.getString("wall").substring(11, 16), 1, offset)))
                val alarms = AlarmRefreshEngine.computeDesiredAlarms(schedule, templates,
                    emptyMap(), expected - 8 * 60 * 60 * 1000)
                assertEquals("$c offset=$offset", 1, alarms.size)
                assertEquals(expected, alarms.single().timestamp)
                assertEquals(c.getString("clock"), alarms.single().time)
                assertEquals(expected, AlarmWakeScheduler.parse(alarms.single().dateStr))
                assertEquals(offset, alarms.single().dayOffset)
            }
        }
    }

    @Test fun gapCollisionProducesOneAlarmAndRepeatedHourUsesTheFutureOccurrence() {
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        fun generate(day: String, times: List<String>, now: String) =
            AlarmRefreshEngine.computeDesiredAlarms(
                AlarmRefreshEngine.ScheduleData(false, emptyList(), 0, 0, mapOf(day to "Night")),
                mapOf("Night" to times.map { AlarmRefreshEngine.TemplateEntry(it, 1, 0) }),
                emptyMap(), Instant.parse(now).toEpochMilli())
        val spring = generate("2026-03-08", listOf("02:30", "03:30"), "2026-03-08T05:00:00Z")
        assertEquals(1, spring.size)
        assertEquals(Instant.parse("2026-03-08T07:30:00Z").toEpochMilli(), spring.single().timestamp)
        assertEquals(1, generate("2026-11-01", listOf("01:30"), "2026-11-01T05:45:00Z").size)
        assertTrue(generate("2026-11-01", listOf("01:30"), "2026-11-01T06:30:00Z").isEmpty())
    }

    @Test fun changingTimeZoneKeepsLocalClockAndChangesScheduledInstant() {
        val wall = "2026-12-15T09:00:00"
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        val ny = AlarmWakeScheduler.parse(wall)
        TimeZone.setDefault(TimeZone.getTimeZone("Europe/London"))
        val london = AlarmWakeScheduler.parse(wall)
        assertEquals(Instant.parse("2026-12-15T14:00:00Z").toEpochMilli(), ny)
        assertEquals(Instant.parse("2026-12-15T09:00:00Z").toEpochMilli(), london)
    }
}
