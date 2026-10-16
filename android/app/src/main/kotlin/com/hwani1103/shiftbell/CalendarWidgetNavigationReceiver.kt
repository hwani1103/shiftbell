package com.hwani1103.shiftbell

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import java.util.Calendar
import java.util.concurrent.Executors

/** Explicit immutable widget actions only. Not exported; never opens alarms. */
class CalendarWidgetNavigationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val pending = goAsync()
        val app = context.applicationContext
        executor.execute {
            try { navigate(app, intent) }
            catch (error: Exception) { Log.e("CalendarWidget", "Month navigation failed", error) }
            finally { pending.finish() }
        }
    }

    companion object {
        internal const val ACTION = "com.hwani1103.shiftbell.CALENDAR_WIDGET_MONTH"
        private val executor = Executors.newSingleThreadExecutor()
        internal fun pendingIntent(context: Context, id: Int, delta: Int, month: Int): PendingIntent {
            val intent = Intent(context, CalendarWidgetNavigationReceiver::class.java).apply {
                action = ACTION
                data = Uri.parse("shiftbell://calendar-widget/$id/$month/$delta")
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                putExtra("delta", delta); putExtra("fromMonth", month)
            }
            return PendingIntent.getBroadcast(context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        internal fun navigate(context: Context, intent: Intent, now: Calendar = Calendar.getInstance()) =
            synchronized(CalendarWidgetProvider.renderLock) {
                val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                val delta = intent.getIntExtra("delta", 0)
                if (intent.action != ACTION || id == AppWidgetManager.INVALID_APPWIDGET_ID || delta !in listOf(-1, 1)) return@synchronized
                val manager = AppWidgetManager.getInstance(context)
                if (manager.getAppWidgetInfo(id)?.provider != ComponentName(context, CalendarWidgetProvider::class.java)) return@synchronized
                if (!CalendarWidgetMonths.canNavigate(manager.getAppWidgetOptions(id))) return@synchronized
                val current = CalendarWidgetMonths.selected(context, id, now)
                // Ignore a stale tap after resize, refresh, or a completed page turn.
                if (intent.getIntExtra("fromMonth", -1) != current) return@synchronized
                val next = current + delta
                if (next !in 12..119999) return@synchronized
                CalendarWidgetMonths.prefs(context).edit().putInt("month_$id", next).apply()
                CalendarWidgetProvider.updateOne(context, manager, id, false, now, current)
            }
    }
}
