package com.hwani1103.shiftbell

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.view.LayoutInflater
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Calendar
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class EnglishReleaseTest {
    private fun context(tag: String, scale: Float = 1f): Context {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val config = Configuration(base.resources.configuration).apply {
            setLocale(Locale.forLanguageTag(tag))
            fontScale = scale
        }
        return base.createConfigurationContext(config)
    }

    @Test fun weekdayOrderAndRemovedFeaturesFollowTheAppLocale() {
        for ((tag, first) in listOf("en-US" to Calendar.SUNDAY,
            "en-GB" to Calendar.MONDAY, "en-ZA" to Calendar.SUNDAY,
            "en-AE" to Calendar.MONDAY, "en-PH" to Calendar.SUNDAY,
            "af-ZA" to Calendar.SUNDAY, "ar-AE" to Calendar.MONDAY,
            "fil-PH" to Calendar.SUNDAY, "en-IE" to Calendar.MONDAY)) {
            val ctx = context(tag)
            assertEquals(first, ReleaseLocalePolicy.firstDayOfWeek(ctx))
            assertFalse(ReleaseLocalePolicy.koreanFeatures(ctx))
            assertFalse(ScheduleNotificationScheduler.isTabEnabled(ctx))
            assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(ctx))
            assertEquals("Alarm", ctx.getString(R.string.alarm_default_label))
        }
        assertTrue(ReleaseLocalePolicy.koreanFeatures(context("ko-KR")))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(context("ko-KR")))
        val koreanHoliday = Calendar.getInstance().apply { set(2026, Calendar.OCTOBER, 9) }
        assertFalse(ReleaseLocalePolicy.isCalendarRedDay(context("en-US"), koreanHoliday))
        assertTrue(ReleaseLocalePolicy.isCalendarRedDay(context("ko-KR"), koreanHoliday))
    }

    @Test fun sleepWidgetCanBeHiddenAndRestoredWithoutDisablingTheCalendar() {
        val en = context("en-US")
        val ko = context("ko-KR")
        val component = ComponentName(en, SleepWidgetProvider::class.java)
        ReleaseLocalePolicy.syncSleepWidget(en)
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            en.packageManager.getComponentEnabledSetting(component))
        ReleaseLocalePolicy.syncSleepWidget(ko)
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            ko.packageManager.getComponentEnabledSetting(component))
        assertNotEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            ko.packageManager.getComponentEnabledSetting(ComponentName(ko, CalendarWidgetProvider::class.java)))
    }

    @Test fun calendarWidgetsUseEnglishAndFullShiftText() {
        val ctx = context("en-GB")
        val now = Calendar.getInstance()
        val schedule = CalendarWidgetScheduleResolver.ResolvedSchedule(true,
            listOf("Afternoon"), 0, now.timeInMillis, emptyMap(), emptyMap())
        for (single in listOf(false, true)) {
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, single, now, schedule, emptyMap())
                .apply(ctx, android.widget.FrameLayout(ctx))
            val shift = root.findViewById<TextView>(R.id.pill_0_0)
            assertEquals("Afternoon", shift.text.toString())
            assertEquals(1, shift.maxLines)
            assertNull(shift.ellipsize)
            if (single) assertEquals("Mon", root.findViewById<TextView>(R.id.hdr_0).text.toString())
            else assertNull(root.findViewById<View>(R.id.hdr_0))
        }
    }
}
