package com.hwani1103.shiftbell
import org.junit.Assert.*
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale
class OperationsSnapshotTest {
  private val now=SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ",Locale.US).parse("2026-10-11T12:00:00.000+0900")!!.time
  @Test fun boundedEventsDoNotExposePayload() {
    val line="2026-10-11T11:00:00.000+0900 | ALARM_FIRED | alarmId=secret label=private"
    val text=listOf(line,line,"2026-10-11T11:00:00.000+0900 | SYSTEM_EVENT | action=BOOT_COMPLETED", "2026-10-11T11:00:00.000+0900 | SYSTEM_EVENT | action=TIMEZONE_CHANGED", "2026-10-01T11:00:00.000+0900 | ALARM_FIRED | old", "2026-10-12T11:00:00.000+0900 | ALARM_FIRED | future", "malformed").joinToString("\n")
    val rows=OperationsSnapshot.observations(text,now)
    assertEquals(3,rows.size);assertEquals(setOf("token","event","atMs"),rows[0].keys)
    assertNotEquals(rows[0]["token"],rows[1]["token"])
    assertEquals("device_boot_seen",rows[2]["event"])
    assertFalse(rows.toString().contains("private"));assertFalse(rows.toString().contains("secret"))
  }
  @Test fun preservesOnlyLatestThousand() {
    val line="2026-10-11T11:00:00.000+0900 | SCHEDULE_FAIL | reason=unknown"
    assertEquals(1000,OperationsSnapshot.observations(List(1200){line}.joinToString("\n"),now).size)
  }
}
