package com.hwani1103.shiftbell

import android.content.Context

object SnoozeText {
    const val DEFAULT_MINUTES = 5
    fun valid(minutes: Int) = minutes in 5..30 && minutes % 5 == 0
    fun compact(minutes: Int): String { require(valid(minutes)); return "+${minutes}m" }
    fun description(context: Context, minutes: Int) = context.getString(R.string.alarm_snooze_minutes, minutes)
    fun selection(context: Context, minutes: Int) = context.getString(R.string.alarm_snooze_selection, minutes)
}
