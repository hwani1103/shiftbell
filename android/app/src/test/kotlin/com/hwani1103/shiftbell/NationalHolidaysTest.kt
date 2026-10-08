package com.hwani1103.shiftbell

import android.content.Context
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
class NationalHolidaysTest {
    private fun red(tag: String, year: Int, month: Int, day: Int): Boolean {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val configuration = Configuration(base.resources.configuration).apply {
            setLocales(LocaleList(Locale.forLanguageTag(tag)))
        }
        val context = base.createConfigurationContext(configuration)
        val date = Calendar.getInstance().apply { clear(); set(year, month - 1, day) }
        return ReleaseLocalePolicy.isCalendarRedDay(context, date)
    }

    @Test fun `existing calendar widget uses national dates and limits red Sundays to Korean`() {
        assertTrue(red("en-US", 2026, 11, 26))
        assertFalse(red("en-US", 2026, 10, 9))
        assertTrue(red("ko-KR", 2026, 10, 9))
        assertTrue(red("en-GB", 2028, 1, 3))
        assertFalse(red("en-GB", 2026, 4, 6))
        assertTrue(red("ar-AE", 2026, 6, 15))
        assertFalse(red("ar-AE", 2026, 6, 16))
        assertTrue(red("fil-PH", 2027, 2, 6))
        assertTrue(red("hi-IN", 2026, 1, 26))
        assertTrue(red("pt-BR", 2026, 11, 20))
        assertTrue(red("de-DE", 2026, 10, 3))
        assertFalse(red("de-AT", 2026, 10, 3))
        assertFalse(red("fr-FR", 2026, 11, 26))
        assertFalse(red("en-US", 2029, 1, 1))
        // Ordinary Sunday: overseas neutral, Korean unchanged.
        for (tag in listOf("en-US", "en-GB", "en-ZA", "en-AE", "de-DE", "pt-BR", "hi-IN", "en-PH")) {
            assertFalse(tag, red(tag, 2026, 10, 11))
        }
        assertTrue(red("ko-KR", 2026, 10, 11))
    }
}
