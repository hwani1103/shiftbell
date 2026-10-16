package com.hwani1103.shiftbell

import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.ViewFlipper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** Run with the next shared dev debug verification; no network or alarm state. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class CalendarWidgetMonthsTest {
    private fun context(tag: String = "ko-KR"): Context {
        val base = ApplicationProvider.getApplicationContext<Context>()
        return base.createConfigurationContext(Configuration(base.resources.configuration).apply {
            setLocale(Locale.forLanguageTag(tag))
        })
    }
    private fun date(year: Int = 2026, month: Int = Calendar.OCTOBER, day: Int = 9) =
        Calendar.getInstance(TimeZone.getTimeZone("Asia/Seoul")).apply {
            clear(); set(year, month, day, 12, 0)
        }
    private fun schedule() = CalendarWidgetScheduleResolver.ResolvedSchedule(
        true, listOf("D"), 0, date().timeInMillis, emptyMap(), emptyMap())
    private fun options(height: Int) = Bundle().apply {
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 320)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 320)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
    }

    @Test fun resizeThresholdsKeepOneWeekAndCapMultiAtSix() {
        for ((height, rows) in listOf(200 to 3, 329 to 3, 330 to 4, 399 to 4,
            400 to 5, 469 to 5, 470 to 6, 900 to 6)) {
            assertEquals(rows, CalendarWidgetMonths.rows(height.toFloat()))
            assertEquals(1, CalendarWidgetMonths.rows(height.toFloat(), true))
            assertEquals(rows == 6, CalendarWidgetMonths.canNavigate(options(height)))
        }
    }

    @Test fun completeMonthIncludesEveryDayAcrossLeapYearsAndWeekStarts() {
        for (year in 2025..2029) for (month in 0..11)
            for (first in listOf(Calendar.SUNDAY, Calendar.MONDAY)) {
                val target = CalendarWidgetMonths.month(date(), year * 12 + month)
                val start = CalendarWidgetMonths.start(target, first)
                assertEquals(first, start.get(Calendar.DAY_OF_WEEK))
                val dates = (0..41).map { offset ->
                    (start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, offset) }
                }
                val actual = dates.filter { CalendarWidgetMonths.index(it) == CalendarWidgetMonths.index(target) }
                assertEquals(target.getActualMaximum(Calendar.DAY_OF_MONTH), actual.size)
                assertEquals(1, actual.first().get(Calendar.DAY_OF_MONTH))
                assertEquals(42, dates.map { CalendarWidgetProvider.dateKeyFor(it) }.distinct().size)
            }
    }

    @Test fun compactModesIgnoreSelectedMonthAndSixWeekModeShowsFullGrid() {
        val ctx = context()
        val future = date(2027, Calendar.JANUARY, 1)
        for ((height, rows) in listOf(228 to 3, 350 to 4, 420 to 5, 500 to 6)) {
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, false, date(), schedule(), emptyMap(),
                heightDp = height.toFloat(), displayMonth = future).apply(ctx, FrameLayout(ctx))
            assertEquals(if (rows == 6) View.VISIBLE else View.GONE,
                root.findViewById<View>(R.id.widget_month_navigation).visibility)
            for (r in 0..5) assertEquals(if (r < rows) View.VISIBLE else View.GONE,
                root.findViewById<View>(ctx.resources.getIdentifier("widget_row_$r", "id", ctx.packageName)).visibility)
            assertEquals("27", root.findViewById<TextView>(R.id.num_0_0).text.toString())
            assertTrue(root.findViewById<TextView>(R.id.widget_date_header).text.contains(if (rows == 6) "2027" else "2026"))
            if (rows == 6) {
                assertEquals(.58f, root.findViewById<View>(R.id.cell_0_0).alpha, .001f)
                assertEquals(1f, root.findViewById<View>(R.id.cell_1_0).alpha, .001f)
                assertEquals("6", root.findViewById<TextView>(R.id.num_5_6).text.toString())
            }
        }
    }

    @Test fun holidayAndThreeNotesShareTypeSizeButWeekHasNoHoliday() {
        val ctx = context()
        val notes = mapOf("2026-10-09" to listOf("메모1", "메모2", "메모3"))
        for (height in listOf(200f, 228f, 350f, 420f, 500f, 700f)) {
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, false, date(), schedule(), notes,
                heightDp = height).apply(ctx, FrameLayout(ctx))
            val holiday = root.findViewById<TextView>(R.id.holiday_1_5)
            assertEquals("한글날", holiday.contentDescription.toString())
            assertEquals(View.VISIBLE, holiday.visibility)
            for (id in listOf(R.id.memo1_1_5, R.id.memo2_1_5, R.id.memo3_1_5)) {
                val memo = root.findViewById<TextView>(id)
                assertEquals(View.VISIBLE, memo.visibility)
                assertEquals(holiday.textSize, memo.textSize, .001f)
                assertEquals(0, memo.paddingTop)
            }
        }
        val week = CalendarWidgetProvider.buildRemoteViews(ctx, true, date(), schedule(), notes)
            .apply(ctx, FrameLayout(ctx))
        assertNull(week.findViewById<View>(R.id.holiday_0_5))
        assertNull(week.findViewById<View>(R.id.widget_month_navigation))
    }

    @Test fun holidayNamesFollowCountryAndRemoteOverrides() {
        val day = date()
        assertEquals("한글날", CalendarWidgetHolidays.name(context(), day))
        assertNull(CalendarWidgetHolidays.name(context("en-US"), day))
        for (tag in listOf("en-US", "de-DE", "pt-BR", "hi-IN")) {
            val holiday = date(2026, Calendar.JANUARY, if (tag == "hi-IN") 26 else 1)
            assertNull(CalendarWidgetHolidays.name(context(tag), holiday))
            assertTrue(ReleaseLocalePolicy.isCalendarRedDay(context(tag), holiday))
        }
        val custom = CalendarWidgetHolidays.Overrides(setOf("2026-10-09"), setOf("2026-10-09"),
            mapOf("2026-10-09" to "변경된 이름"))
        assertEquals("변경된 이름", CalendarWidgetHolidays.name(context(), day, custom))
        assertNull(CalendarWidgetHolidays.name(context(), day,
            CalendarWidgetHolidays.Overrides(remove = setOf("2026-10-09"))))
        assertNull(CalendarWidgetHolidays.name(context(), date(day = 11))) // ordinary Sunday
    }

    @Test fun pageTransitionRespectsDisabledSystemAnimations() {
        val ctx = context()
        for (scale in listOf(0f, 1f)) {
            Settings.Global.putFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, scale)
            Settings.Global.putFloat(ctx.contentResolver, Settings.Global.TRANSITION_ANIMATION_SCALE, scale)
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, false, date(), schedule(), emptyMap(),
                heightDp = 500f, previousMonth = CalendarWidgetMonths.index(date()) - 1)
                .apply(ctx, FrameLayout(ctx))
            val pages = root.findViewById<ViewFlipper>(R.id.widget_month_pages)
            assertEquals(if (scale == 0f) 1 else 2, pages.childCount)
            assertEquals(if (scale == 0f) 0 else 1, pages.displayedChild)
            // ShadowViewAnimator changes visibility without invoking the SDK's
            // showOnly/startAnimation. Verify the configured transition here;
            // actual playback is a launcher/device check.
            if (scale == 0f) assertNull(pages.currentView.animation)
            else {
                assertNotNull(pages.inAnimation)
                assertNotNull(pages.outAnimation)
                assertEquals(180L, pages.inAnimation.duration)
                assertEquals(180L, pages.outAnimation.duration)
            }
            val first = CalendarWidgetProvider.buildRemoteViews(ctx, false, date(), schedule(), emptyMap(), heightDp = 500f)
                .apply(ctx, FrameLayout(ctx)).findViewById<ViewFlipper>(R.id.widget_month_pages)
            assertEquals(0, first.displayedChild)
            assertNull(first.currentView.animation)
        }
    }

    @Test fun monthActionsAreSeparateFromAppLaunchAndCompactActionsAreRejected() {
        val ctx = context()
        val manager = AppWidgetManager.getInstance(ctx)
        val host = shadowOf(manager)
        val id = 301
        val other = 302
        // createWidget builds a View but leaves getAppWidgetInfo() null in
        // Robolectric. Register the provider exactly as a bound launcher does.
        for (widgetId in listOf(id, other)) host.addBoundWidget(widgetId,
            AppWidgetProviderInfo().apply {
                provider = ComponentName(ctx, CalendarWidgetProvider::class.java)
                initialLayout = R.layout.calendar_widget
            })
        assertEquals(ComponentName(ctx, CalendarWidgetProvider::class.java), manager.getAppWidgetInfo(id).provider)
        val current = CalendarWidgetMonths.index(date())
        val pending = CalendarWidgetNavigationReceiver.pendingIntent(ctx, id, 1, current)
        val intent = shadowOf(pending).savedIntent
        assertEquals(CalendarWidgetNavigationReceiver::class.java.name, intent.component?.className)
        for (height in listOf(228, 350, 420)) {
            manager.updateAppWidgetOptions(id, options(height))
            CalendarWidgetNavigationReceiver.navigate(ctx, intent, date())
            assertEquals(current, CalendarWidgetMonths.selected(ctx, id, date()))
        }
        manager.updateAppWidgetOptions(id, options(500))
        CalendarWidgetNavigationReceiver.navigate(ctx, intent, date())
        assertEquals(current + 1, CalendarWidgetMonths.selected(ctx, id, date()))
        assertEquals(current, CalendarWidgetMonths.selected(ctx, other, date()))
        CalendarWidgetNavigationReceiver.navigate(ctx, intent, date()) // duplicate stale tap
        assertEquals(current + 1, CalendarWidgetMonths.selected(ctx, id, date()))
        CalendarWidgetProvider().onAppWidgetOptionsChanged(ctx, manager, id, options(350))
        assertEquals(current, CalendarWidgetMonths.selected(ctx, id, date()))

        val root = CalendarWidgetProvider.buildRemoteViews(ctx, false, date(), schedule(), emptyMap(), heightDp = 500f)
            .apply(ctx, FrameLayout(ctx))
        root.findViewById<View>(R.id.widget_panel).performClick()
        val launch = shadowOf(ApplicationProvider.getApplicationContext<android.app.Application>()).nextStartedActivity
        assertEquals(MainActivity::class.java.name, launch.component?.className)
        assertEquals(2, launch.getIntExtra("openTab", -1))
    }
}
