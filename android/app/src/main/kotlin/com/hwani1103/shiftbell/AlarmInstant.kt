package com.hwani1103.shiftbell

import android.content.Context
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Absolute instants for snoozes/events; recurring templates remain wall clocks. */
internal object AlarmInstant {
    private val stored = DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ssXXX", Locale.US)
    private val offsetSuffix = Regex("(?:Z|[+-]\\d{2}:\\d{2})$")
    fun hasOffset(value: String) = offsetSuffix.containsMatchIn(value)
    fun parse(value: String): Long = OffsetDateTime.parse(value).toInstant().toEpochMilli()
    fun format(millis: Long): String = stored.format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
    fun display(context: Context, millis: Long): String {
        val at = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault())
        val time = DateTimeFormatter.ofPattern("HH:mm", Locale.US).format(at)
        val offsets = at.zone.rules.getValidOffsets(at.toLocalDateTime())
        if (offsets.size != 2) return time
        return context.getString(if (at.offset == offsets.first())
            R.string.alarm_clock_first else R.string.alarm_clock_second, time)
    }
}
