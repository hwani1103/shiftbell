package com.hwani1103.shiftbell

import org.junit.Assert.*
import org.junit.Test
import java.util.TimeZone

class SleepTimestampTest {
    @Test fun offsetsDistinguishRepeatedClockTimes() {
        val first = SleepTimestamp.parse("2026-11-01T01:30:00-04:00")!!
        val second = SleepTimestamp.parse("2026-11-01T01:30:00-05:00")!!
        assertEquals(3_600_000L, second - first)
        assertEquals(first, SleepTimestamp.parse(SleepTimestamp.format(first)))
        assertEquals(second, SleepTimestamp.parse(SleepTimestamp.format(second)))
    }
    @Test fun legacyLocalAndFractionalRowsRemainReadable() {
        val old = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"))
            val expected = SleepTimestamp.parse("2026-09-27T22:00:00+09:00")
            assertEquals(expected, SleepTimestamp.parse("2026-09-27T22:00:00"))
            assertEquals(expected, SleepTimestamp.parse("2026-09-27T22:00:00.000"))
            assertEquals(expected, SleepTimestamp.parse("2026-09-27T13:00:00Z"))
        } finally { TimeZone.setDefault(old) }
    }
    @Test fun invalidOrTrailingTextIsRejected() {
        assertNull(SleepTimestamp.parse("garbage"))
        assertNull(SleepTimestamp.parse("2026-02-30T22:00:00"))
        assertNull(SleepTimestamp.parse("2026-09-27T22:00:00oops"))
    }
}
