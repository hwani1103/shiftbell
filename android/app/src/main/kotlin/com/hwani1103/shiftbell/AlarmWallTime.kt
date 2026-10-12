package com.hwani1103.shiftbell

import java.time.LocalDateTime
import java.time.ZoneId

/** Device-local alarms: shift gaps forward, ring once at the later overlap. */
internal object AlarmWallTime {
    fun resolve(year: Int, month: Int, day: Int, hour: Int, minute: Int,
                zone: ZoneId = ZoneId.systemDefault()): Long =
        LocalDateTime.of(year, month, day, hour, minute).atZone(zone)
            .withLaterOffsetAtOverlap().toInstant().toEpochMilli()
}
