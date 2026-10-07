package com.hwani1103.shiftbell

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class PermissionSettingsTest {
    private fun activity() = Robolectric.buildActivity(Activity::class.java).setup().get()

    @Test @Config(sdk = [34]) fun `standard and OEM intents target the running flavor without task flags`() {
        val a = activity()
        val full = PermissionSettings.intent(a, "fullScreen")!!
        assertEquals(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, full.action)
        assertEquals("package:${a.packageName}", full.data.toString())
        assertEquals(0, full.flags)
        val exact = PermissionSettings.intent(a, "exactAlarm")!!
        assertEquals(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, exact.action)
        val oem = PermissionSettings.intent(a, "xiaomi")!!
        assertEquals("miui.intent.action.APP_PERM_EDITOR", oem.action)
        assertEquals(a.packageName, oem.getStringExtra("extra_pkgname"))
        assertTrue(oem.hasCategory(Intent.CATEGORY_DEFAULT))
        assertFalse(oem.hasExtra("extra_permission"))
        assertEquals(0, oem.flags)
    }

    @Test @Config(sdk = [30]) fun `older Android does not request exact or fullscreen permissions`() {
        val a = activity()
        val states = PermissionSettings.snapshot(a)
        assertEquals("notApplicable", states["exactAlarm"])
        assertEquals("notApplicable", states["fullScreen"])
        assertNull(PermissionSettings.intent(a, "fullScreen"))
        assertNull(PermissionSettings.intent(a, "exactAlarm"))
    }

    @Test @Config(sdk = [33]) fun `Android 13 checks exact alarms but does not offer fullscreen settings`() {
        val a = activity()
        assertEquals("notApplicable", PermissionSettings.snapshot(a)["fullScreen"])
        assertNotNull(PermissionSettings.intent(a, "exactAlarm"))
        assertNull(PermissionSettings.intent(a, "fullScreen"))
    }

    @Test fun `activity not found and security exceptions fall back and double failure stays false`() {
        val target = Intent("primary"); val fallback = Intent("fallback")
        val calls = mutableListOf<String?>()
        assertTrue(PermissionSettings.launchWithFallback(target, fallback) {
            calls.add(it.action)
            if (it.action == "primary") throw ActivityNotFoundException()
        })
        assertEquals(listOf("primary", "fallback"), calls)
        assertFalse(PermissionSettings.launchWithFallback(target, fallback) { throw SecurityException() })
    }

    @Test fun `manufacturer normalization is confined to Xiaomi family`() {
        assertTrue(PermissionSettings.isXiaomiFamily(" XIAOMI ", ""))
        assertTrue(PermissionSettings.isXiaomiFamily("", "POCO"))
        assertTrue(PermissionSettings.isXiaomiFamily("redmi", ""))
        assertFalse(PermissionSettings.isXiaomiFamily("samsung", "galaxy"))
        assertFalse(PermissionSettings.isXiaomiFamily("vivo", "vivo"))
    }

    @Test @Config(sdk = [34]) fun `channel denial does not become app notification or fullscreen denial`() {
        val a = activity()
        val nm = a.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CustomAlarmReceiver.CHANNEL_ID, "alarm", NotificationManager.IMPORTANCE_NONE))
        val blocked = PermissionSettings.snapshot(a)
        assertEquals("denied", blocked["alarmChannel"])
        assertEquals("granted", blocked["notification"])
        nm.createNotificationChannel(NotificationChannel("alarm_control", "legacy", NotificationManager.IMPORTANCE_HIGH))
        assertEquals("granted", PermissionSettings.snapshot(a)["alarmChannel"])
    }
}
