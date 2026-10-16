package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration
import android.os.UserManager
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "ko-rKR")
class SleepWidgetReapplyTest {
    @Test fun appLocaleAndDisabledActionsSurviveLauncherReapply() {
        val host = ApplicationProvider.getApplicationContext<Context>()
        shadowOf(host.getSystemService(UserManager::class.java)).setUserUnlocked(true)
        val prefs = host.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val method = SleepWidgetProvider.Companion.javaClass.getDeclaredMethod(
            "buildRemoteViews", Context::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
        method.isAccessible = true
        fun render(context: Context): RemoteViews = method.invoke(SleepWidgetProvider.Companion, context, 200, 100) as RemoteViews
        for (tag in listOf("en-US", "de-DE", "pt-BR", "hi-IN", "ko-KR")) {
            val app = host.createConfigurationContext(Configuration(host.resources.configuration).apply {
                setLocale(Locale.forLanguageTag(tag))
            })
            prefs.edit().putBoolean("flutter.condition_tab_enabled", true)
                .putBoolean("flutter.sleep_global_enabled_v1", true).commit()
            val view = render(app).apply(host, FrameLayout(host))
            val sleep = view.findViewById<TextView>(R.id.sleep_button_sleep)
            val wake = view.findViewById<TextView>(R.id.sleep_button_wake)
            assertEquals(tag, app.getString(R.string.sleep_widget_sleep), sleep.text.toString())
            assertEquals(tag, app.getString(R.string.sleep_widget_wake), wake.text.toString())
            assertTrue(tag, sleep.isEnabled && wake.isEnabled && sleep.hasOnClickListeners())
            prefs.edit().putBoolean("flutter.condition_tab_enabled", false)
                .putBoolean("flutter.sleep_global_enabled_v1", false).commit()
            render(app).reapply(host, view)
            assertFalse(tag, sleep.isEnabled || wake.isEnabled)
            assertFalse(tag, sleep.hasOnClickListeners() || wake.hasOnClickListeners())
            assertFalse(tag, view.findViewById<View>(R.id.sleep_widget_root).hasOnClickListeners())
            assertEquals(tag, View.VISIBLE, view.findViewById<View>(R.id.sleep_shift_label).visibility)
            prefs.edit().putBoolean("flutter.condition_tab_enabled", true)
                .putBoolean("flutter.sleep_global_enabled_v1", true).commit()
            render(app).reapply(host, view)
            assertTrue(tag, sleep.isEnabled && wake.isEnabled && sleep.hasOnClickListeners())
            assertEquals(tag, View.GONE, view.findViewById<View>(R.id.sleep_shift_label).visibility)
        }
    }
}
