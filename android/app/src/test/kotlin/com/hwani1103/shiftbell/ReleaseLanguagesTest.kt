package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Calendar
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class ReleaseLanguagesTest {
    private fun context(language: String, country: String): Context {
        val app = ApplicationProvider.getApplicationContext<Context>()
        return app.createConfigurationContext(Configuration(app.resources.configuration).apply {
            setLocale(Locale(language, country))
        })
    }

    @Test fun `German alarm controls and widget weekdays use German resources`() {
        val c = context("de", "DE")
        assertEquals("Wecker stoppen", c.getString(R.string.notif_action_dismiss))
        assertEquals("Später", c.getString(R.string.alarm_snooze_label))
        assertEquals("Mo", c.getString(R.string.widget_weekday_1))
        assertEquals(Calendar.MONDAY, ReleaseLocalePolicy.firstDayOfWeek(c))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
        assertEquals(Calendar.MONDAY, ReleaseLocalePolicy.firstDayOfWeek(context("de", "")))
    }

    @Test fun `Brazilian alarm controls and widget weekdays use Portuguese resources`() {
        val c = context("pt", "BR")
        assertEquals("Desligar alarme", c.getString(R.string.notif_action_dismiss))
        assertEquals("Adiar", c.getString(R.string.alarm_snooze_label))
        assertEquals("Sáb", c.getString(R.string.widget_weekday_6))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(c))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
    }

    @Test fun `Hindi alarm controls and widget weekdays use Hindi resources`() {
        val c = context("hi", "IN")
        assertEquals("अलार्म बंद करें", c.getString(R.string.notif_action_dismiss))
        assertEquals("स्नूज़ करें", c.getString(R.string.alarm_snooze_label))
        assertEquals("सोम", c.getString(R.string.widget_weekday_1))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(c))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(context("hi", "GB")))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
        assertEquals("स्नूज़ किया गया · अगला अलार्म 07:00 पर",
            c.getString(R.string.notif_snoozed_title, "07:00"))
        assertTrue(SleepScheduleResolver.isRestShiftName("छुट्टी"))
        assertTrue(SleepScheduleResolver.isRestShiftName("अवकाश"))
        assertFalse(SleepScheduleResolver.isRestShiftName("अवकाशप्राप्त"))
    }

    @Test fun `rest-name matching agrees with Dart and avoids substring false positives`() {
        for (name in listOf("Frei", "Urlaub", "Folga", "Férias", "FERIAS", "Paid Leave", "PTO", "휴무"))
            assertTrue(name, SleepScheduleResolver.isRestShiftName(name))
        for (name in listOf("Office", "Officer", "Forestry", "Freitag", "Urlauber", "Früh", "Tarde", "Night duty"))
            assertFalse(name, SleepScheduleResolver.isRestShiftName(name))
    }
}
