package com.hwani1103.shiftbell

import java.text.SimpleDateFormat
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.Date
import java.util.Locale

/** Sleep instants retain their offset through DST overlaps. Legacy local rows remain readable. */
internal object SleepTimestamp {
    private const val LOCAL = "yyyy-MM-dd'T'HH:mm:ss"
    fun format(millis: Long): String = SimpleDateFormat(LOCAL + "XXX", Locale.US).format(Date(millis))
    fun parse(value: String?): Long? {
        if (value == null) return null
        return runCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }.getOrNull()
            ?: runCatching {
                LocalDateTime.parse(value).atZone(ZoneId.systemDefault())
                    .withLaterOffsetAtOverlap().toInstant().toEpochMilli()
            }.getOrNull()
    }

}
