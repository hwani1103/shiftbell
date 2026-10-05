package com.hwani1103.shiftbell

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import java.util.Calendar
import java.util.Locale

/** Release availability only; never changes stored schedules or alarm times. */
object ReleaseLocalePolicy {
    fun locale(context: Context): Locale = context.resources.configuration.locales[0]
    fun koreanFeatures(context: Context): Boolean = locale(context).language == "ko"

    // Same regional defaults as lib/l10n/release_locale.dart.
    private val mondayRegions = setOf(
        "GB", "IE", "AU", "NZ", "AT", "BE", "BG", "CH", "CY", "CZ", "DE",
        "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IS", "IT", "LI",
        "LT", "LU", "LV", "MC", "NL", "NO", "PL", "RO", "RS", "SE", "SI", "SK"
    )
    fun firstDayOfWeek(context: Context): Int = when (locale(context).language) {
        "de" -> Calendar.MONDAY
        "pt", "ko", "hi" -> Calendar.SUNDAY
        else -> if (locale(context).country in mondayRegions) Calendar.MONDAY else Calendar.SUNDAY
    }

    fun isCalendarRedDay(context: Context, day: Calendar,
        overrides: CalendarWidgetHolidays.Overrides = CalendarWidgetHolidays.Overrides.EMPTY): Boolean =
        day.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY ||
            (koreanFeatures(context) && CalendarWidgetHolidays.isHoliday(day, overrides))

    fun syncSleepWidget(context: Context) {
        // Manifest enabled cannot vary by locale. Keep the shipped enabled
        // default so updating Korean installs does not disable their widgets.
        // Hide it outside Korean on app resume, locale change/package replacement.
        val manager = context.packageManager
        val component = ComponentName(context, SleepWidgetProvider::class.java)
        val target = if (koreanFeatures(context)) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        if (manager.getComponentEnabledSetting(component) != target) {
            manager.setComponentEnabledSetting(component, target, PackageManager.DONT_KILL_APP)
        }
    }
}

class ReleaseLocaleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReleaseLocalePolicy.syncSleepWidget(context)
        ScheduleNotificationScheduler.syncLocale(context)
        CalendarWidgetProvider.requestUpdate(context)
        // Receivers still check the locale at delivery in case a transition races.
    }
}
