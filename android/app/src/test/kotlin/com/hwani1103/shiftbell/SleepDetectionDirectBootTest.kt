package com.hwani1103.shiftbell

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.UserManager
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "ko-rKR")
class SleepDetectionDirectBootTest {
    private lateinit var base: Context
    private lateinit var context: Context

    @Before
    fun setUp() {
        base = ApplicationProvider.getApplicationContext()
        base.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear().commit()
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(true)
        context = object : ContextWrapper(base) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                check(base.getSystemService(UserManager::class.java).isUserUnlocked) {
                    "Credential encrypted preferences unavailable before unlock"
                }
                return super.getSharedPreferences(name, mode)
            }
        }
    }

    @Test fun lockedBootDefersDetectionWithoutReadingCredentialPreferences() {
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(false)
        assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(context))
    }

    @Test fun unlockRestoresEnabledDetection() {
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(false)
        assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(context))
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(true)
        assertTrue(SleepDetectionScheduler.isSleepDetectionEnabled(context))
    }

    @Test fun unlockRespectsDisabledTab() {
        base.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.condition_tab_enabled", false).commit()
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(false)
        assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(context))
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(true)
        assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(context))
    }

    @Test @Config(qualifiers = "en-rUS")
    fun englishRemainsDisabledAcrossUnlock() {
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(false)
        assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(context))
        shadowOf(base.getSystemService(UserManager::class.java)).setUserUnlocked(true)
        assertFalse(SleepDetectionScheduler.isSleepDetectionEnabled(context))
    }
}
