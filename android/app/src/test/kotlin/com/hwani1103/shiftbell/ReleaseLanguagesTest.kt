package com.hwani1103.shiftbell

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.LocaleList
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Calendar
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class ReleaseLanguagesTest {
    @Test fun `release country weekday starts match Flutter and never add Korean holidays`() {
        for ((tag, first) in listOf("en-US" to Calendar.SUNDAY, "en-GB" to Calendar.MONDAY,
            "en-ZA" to Calendar.SUNDAY, "af-ZA" to Calendar.SUNDAY,
            "en-PH" to Calendar.SUNDAY, "fil-PH" to Calendar.SUNDAY,
            "en-AE" to Calendar.MONDAY, "ar-AE" to Calendar.MONDAY,
            "de-DE" to Calendar.MONDAY, "pt-BR" to Calendar.SUNDAY,
            "hi-IN" to Calendar.SUNDAY, "en-IN" to Calendar.SUNDAY)) {
            val locale = Locale.forLanguageTag(tag)
            val c = context(locale.language, locale.country)
            assertEquals(tag, first, ReleaseLocalePolicy.firstDayOfWeek(c))
            assertFalse(tag, ReleaseLocalePolicy.koreanFeatures(c))
            val holiday = Calendar.getInstance().apply { set(2026, Calendar.OCTOBER, 9) }
            assertFalse(tag, ReleaseLocalePolicy.isCalendarRedDay(c, holiday))
            val labels = c.resources.getStringArray(R.array.widget_weekday_labels)
            val firstColumn = first - Calendar.SUNDAY
            val ordered = (0..6).map { labels[(it + firstColumn) % 7] }
            assertEquals(tag, 7, ordered.toSet().size)
            assertEquals(tag, if (first == Calendar.MONDAY) labels[1] else labels[0], ordered[0])
        }
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(context("ko", "KR")))
    }
    @Test fun `unsupported primary locale uses English without enabling Korean features`() {
        val app = ApplicationProvider.getApplicationContext<Context>()
        val c = app.createConfigurationContext(Configuration(app.resources.configuration).apply {
            setLocales(LocaleList(Locale.JAPANESE, Locale.KOREAN))
        })
        assertEquals("Dismiss", c.getString(R.string.alarm_dismiss_label))
        assertEquals("ShiftBell (Test)", c.getString(R.string.app_name))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
    }
    @Test fun `supported primary locales do not inherit a secondary Korean translation`() {
        val app = ApplicationProvider.getApplicationContext<Context>()
        for (tag in listOf("pt-BR", "de-DE", "en-US", "hi-IN")) {
            val primary = Locale.forLanguageTag(tag)
            val c = app.createConfigurationContext(Configuration(app.resources.configuration).apply {
                setLocales(LocaleList(primary, Locale.KOREAN))
            })
            assertEquals(tag, context(primary.language, primary.country).getString(R.string.alarm_dismiss_label),
                c.getString(R.string.alarm_dismiss_label))
            assertFalse(tag, ReleaseLocalePolicy.koreanFeatures(c))
            assertEquals(tag, "ShiftBell (Test)", c.getString(R.string.app_name))
            assertArrayEquals(tag, context(primary.language, primary.country).resources.getStringArray(R.array.widget_weekday_labels),
                c.resources.getStringArray(R.array.widget_weekday_labels))
        }
    }
    @Test fun `sleep widget is absent on fresh install and only enabled for Korean`() {
        val app = ApplicationProvider.getApplicationContext<Context>()
        val component = ComponentName(app, SleepWidgetProvider::class.java)
        val manager = app.packageManager
        assertFalse(manager.getReceiverInfo(component,
            PackageManager.MATCH_DISABLED_COMPONENTS).enabled)
        ReleaseLocalePolicy.syncSleepWidget(context("ko", "KR"))
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            manager.getComponentEnabledSetting(component))
        for ((language, country) in listOf("pt" to "BR", "de" to "DE", "en" to "US", "hi" to "IN")) {
            ReleaseLocalePolicy.syncSleepWidget(context(language, country))
            assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                manager.getComponentEnabledSetting(component))
        }
    }

    private fun context(language: String, country: String): Context {
        val app = ApplicationProvider.getApplicationContext<Context>()
        return app.createConfigurationContext(Configuration(app.resources.configuration).apply {
            setLocale(Locale(language, country))
        })
    }

    @Test fun `German alarm controls and widget weekdays use German resources`() {
        val c = context("de", "DE")
        assertEquals("Wecker stoppen", c.getString(R.string.notif_action_dismiss))
        assertEquals("5 Min. später", c.getString(R.string.alarm_snooze_label))
        assertEquals("Mo", c.getString(R.string.widget_weekday_1))
        assertEquals(Calendar.MONDAY, ReleaseLocalePolicy.firstDayOfWeek(c))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
        assertEquals(Calendar.MONDAY, ReleaseLocalePolicy.firstDayOfWeek(context("de", "")))
    }

    @Test fun `Brazilian alarm controls and widget weekdays use Portuguese resources`() {
        val c = context("pt", "BR")
        assertEquals("Desligar alarme", c.getString(R.string.notif_action_dismiss))
        assertEquals("Adiar 5 min", c.getString(R.string.alarm_snooze_label))
        assertEquals("Sáb", c.getString(R.string.widget_weekday_6))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(c))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
    }

    @Test fun `Hindi alarm controls and widget weekdays use Hindi resources`() {
        val c = context("hi", "IN")
        assertEquals("अलार्म बंद करें", c.getString(R.string.notif_action_dismiss))
        assertEquals("5 मिनट बाद", c.getString(R.string.alarm_snooze_label))
        assertEquals("सोम", c.getString(R.string.widget_weekday_1))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(c))
        assertEquals(Calendar.SUNDAY, ReleaseLocalePolicy.firstDayOfWeek(context("hi", "GB")))
        assertFalse(ReleaseLocalePolicy.koreanFeatures(c))
        assertEquals("स्नूज़ किया गया · फिर 07:00 पर बजेगा",
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

    @Test fun genericAlarmLabelExistsInEveryReleaseLanguage() {
        for ((lang, country) in listOf("ko" to "KR", "en" to "US", "de" to "DE", "pt" to "BR", "hi" to "IN")) {
            assertTrue(context(lang, country).getString(R.string.alarm_default_label).isNotBlank())
        }
    }
}
