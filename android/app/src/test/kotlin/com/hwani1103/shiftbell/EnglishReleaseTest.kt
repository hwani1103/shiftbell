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
            "en-GB" to Calendar.MONDAY, "en-IE" to Calendar.MONDAY)) {
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

    @Test fun calendarWidgetPreviewsUseEnglishAndBoundedShiftText() {
        for (scale in listOf(1f, 1.3f)) {
            val ctx = context("en-GB", scale)
            for (layout in listOf(R.layout.calendar_widget, R.layout.calendar_widget_full)) {
                val root = LayoutInflater.from(ctx).inflate(layout, null)
                val density = ctx.resources.displayMetrics.density
                for (width in listOf(280, 380, 700)) {
                    root.findViewById<TextView>(R.id.pill_0_0).text = "Afternoon"
                    root.measure(View.MeasureSpec.makeMeasureSpec((width * density).toInt(), View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec((400 * density).toInt(), View.MeasureSpec.EXACTLY))
                    root.layout(0, 0, root.measuredWidth, root.measuredHeight)
                    val shift = root.findViewById<TextView>(R.id.pill_0_0)
                    assertTrue(shift.width > 0)
                    assertEquals(1, shift.maxLines)
                    assertEquals(TextView.AUTO_SIZE_TEXT_TYPE_UNIFORM, shift.autoSizeTextType)
                    assertEquals("Mon", root.findViewById<TextView>(R.id.hdr_0).text.toString())
                    assertTrue(shift.textSize <= 9 * ctx.resources.displayMetrics.scaledDensity + .1f)
                }
            }
        }
    }
}
