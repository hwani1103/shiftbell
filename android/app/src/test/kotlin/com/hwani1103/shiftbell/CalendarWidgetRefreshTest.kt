package com.hwani1103.shiftbell

import android.appwidget.AppWidgetManager
import android.content.ContentValues
import android.content.Context
import android.os.Bundle
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.util.Calendar

@RunWith(RobolectricTestRunner::class)
class CalendarWidgetRefreshTest {
    @Test fun dbChangesRefreshBothPinnedProvidersIncludingAWeekOnlyInstallation() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        DatabaseHelper.resetInstanceForTest()
        val dbFile = ctx.createDeviceProtectedStorageContext().getDatabasePath("shiftbell.db")
        dbFile.parentFile?.mkdirs()
        File(G0TestSupport.g0Dir, "fixtures_db/v23.db").copyTo(dbFile, overwrite = true)
        try {
            val db = DatabaseHelper.getInstance(ctx).writableDatabase
            db.delete("shift_schedule", null, null)
            db.delete("date_memos", null, null)
            fun save(name: String) {
                db.delete("shift_schedule", null, null)
                db.insertOrThrow("shift_schedule", null, ContentValues().apply {
                    put("id", 1); put("is_regular", 1); put("pattern", name)
                    put("today_index", 0); put("shift_types", name)
                    put("start_date", "2026-01-01T00:00:00")
                    put("assigned_dates", "{}"); put("shift_colors", "{}")
                })
            }
            save("Before")
            val manager = AppWidgetManager.getInstance(ctx)
            val shadow = shadowOf(manager)
            val week = shadow.createWidget(WeekCalendarWidgetProvider::class.java, R.layout.calendar_widget_week)
            save("Week only")
            CalendarWidgetProvider.requestUpdate(ctx)
            assertEquals("Week only", shadow.getViewFor(week).findViewById<TextView>(R.id.pill_0_0).text.toString())
            val three = shadow.createWidget(CalendarWidgetProvider::class.java, R.layout.calendar_widget)
            save("Renamed shift")
            for (single in listOf(false, true)) {
                val start = CalendarWidgetProvider.windowStart(Calendar.getInstance(), ReleaseLocalePolicy.firstDayOfWeek(ctx), single)
                db.insertOrThrow("date_memos", null, ContentValues().apply {
                    put("date", CalendarWidgetProvider.dateKeyFor(start)); put("memo_text", "Saved memo")
                    put("order_index", 0); put("created_at", "2026-10-09T12:00:00")
                })
            }
            CalendarWidgetProvider.requestUpdate(ctx)
            for (id in listOf(week, three)) {
                val root = shadow.getViewFor(id)
                assertEquals("Renamed shift", root.findViewById<TextView>(R.id.pill_0_0).text.toString())
                assertEquals("Saved memo", root.findViewById<TextView>(R.id.memo1_0_0).text.toString())
                manager.updateAppWidgetOptions(id, Bundle().apply {
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 700)
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 700)
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 600)
                })
            }
            CalendarWidgetProvider.requestUpdate(ctx)
            assertNull(shadow.getViewFor(week).findViewById<android.view.View>(R.id.num_1_0))
            db.delete("date_memos", null, null)
            save("Changed again")
            CalendarWidgetProvider.requestUpdate(ctx)
            for (id in listOf(week, three)) {
                assertEquals("Changed again", shadow.getViewFor(id).findViewById<TextView>(R.id.pill_0_0).text.toString())
                assertEquals(android.view.View.GONE, shadow.getViewFor(id).findViewById<TextView>(R.id.memo1_0_0).visibility)
            }
        } finally { DatabaseHelper.resetInstanceForTest() }
    }
}
