package com.hwani1103.shiftbell

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Bundle
import android.util.SizeF
import android.os.Build
import java.util.Calendar

/** Local calendar geometry/state; no alarm writes or network requests. */
internal object CalendarWidgetMonths {
    const val PREFS = "calendar_widget_months"
    // Preserve three weeks at the compact size, then add one row per 70 dp.
    fun rows(height: Float, single: Boolean = false): Int =
        if (single) 1 else (3 + ((height - 260f) / 70f).toInt().coerceAtLeast(0)).coerceAtMost(6)

    fun index(day: Calendar) = day.get(Calendar.YEAR) * 12 + day.get(Calendar.MONTH)
    fun month(now: Calendar, index: Int) = (now.clone() as Calendar).apply {
        set(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.YEAR, index / 12); set(Calendar.MONTH, index % 12)
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }
    fun start(month: Calendar, first: Int) = (month.clone() as Calendar).apply {
        set(Calendar.DAY_OF_MONTH, 1)
        add(Calendar.DAY_OF_MONTH, -((get(Calendar.DAY_OF_WEEK) - first + 7) % 7))
    }
    fun prefs(context: Context) = context.createDeviceProtectedStorageContext()
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun selected(context: Context, id: Int, now: Calendar): Int =
        prefs(context).getInt("month_$id", index(now)).takeIf { it in 12..119999 } ?: index(now)
    fun reset(context: Context, id: Int) { prefs(context).edit().remove("month_$id").apply() }
    fun canNavigate(options: Bundle): Boolean {
        val sizes = if (Build.VERSION.SDK_INT >= 31)
            options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES).orEmpty() else emptyList()
        return if (sizes.isNotEmpty()) sizes.any { rows(it.height) == 6 }
            else rows(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 228).toFloat()) == 6 ||
                rows(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 228).toFloat()) == 6
    }
}

/** Bounded process cache. Refresh signals invalidate it after every app save.
 * One range query preloads the selected month and both adjacent 42-day grids. */
internal object CalendarWidgetMonthCache {
    data class Snapshot(val start: String, val end: String,
        val schedule: CalendarWidgetScheduleResolver.ResolvedSchedule?,
        val memos: Map<String, List<String>>, val created: Long, val identity: String)
    private val entries = ArrayDeque<Snapshot>()
    internal var loads = 0
        private set
    @Synchronized fun invalidate() { entries.clear() }
    @Synchronized fun get(context: Context, month: Calendar, preload: Boolean = false): Snapshot {
        val first = ReleaseLocalePolicy.firstDayOfWeek(context)
        val from = (month.clone() as Calendar).apply { if (preload) add(Calendar.MONTH, -1) }
        val to = (month.clone() as Calendar).apply { if (preload) add(Calendar.MONTH, 1) }
        val start = CalendarWidgetProvider.dateKeyFor(CalendarWidgetMonths.start(from, first))
        val end = CalendarWidgetProvider.dateKeyFor(CalendarWidgetMonths.start(to, first).apply { add(Calendar.DAY_OF_MONTH, 41) })
        val identity = context.packageName + "/" + ReleaseLocalePolicy.locale(context).toLanguageTag() + "/" + month.timeZone.id
        val clock = android.os.SystemClock.elapsedRealtime()
        entries.firstOrNull { it.identity == identity && it.start <= start && it.end >= end && clock - it.created < 30 * 60_000L }?.let { return it }
        // A miss always loads neighbours too, so the first previous/next tap is warm.
        val lower = CalendarWidgetMonths.start((month.clone() as Calendar).apply { add(Calendar.MONTH, -1) }, first)
        val upper = CalendarWidgetMonths.start((month.clone() as Calendar).apply { add(Calendar.MONTH, 1) }, first).apply { add(Calendar.DAY_OF_MONTH, 41) }
        val lo = CalendarWidgetProvider.dateKeyFor(lower); val hi = CalendarWidgetProvider.dateKeyFor(upper)
        val snapshot = Snapshot(lo, hi, CalendarWidgetScheduleResolver.readSchedule(context),
            CalendarWidgetScheduleResolver.readMemos(context, lo, hi).mapValues { it.value.take(3) }, clock, identity)
        loads++
        if (snapshot.schedule != null) {
            entries.addFirst(snapshot)
            while (entries.size > 4) entries.removeLast()
        }
        return snapshot
    }
}
