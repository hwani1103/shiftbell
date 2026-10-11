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
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowSettings

@RunWith(RobolectricTestRunner::class)
class PermissionSettingsTest {
    private fun activity() = Robolectric.buildActivity(Activity::class.java).setup().get()

    @Test @Config(sdk = [33, 34]) fun `notification cancellation completes once and releases request guard`() {
        val a = activity()
        val request = NotificationPermissionRequest()
        val completed = mutableListOf<Boolean>()
        request.launch(a) { completed.add(it) }
        assertTrue(completed.isEmpty())
        request.launch(a) { completed.add(it) }
        assertEquals(listOf(false), completed) // No second permission prompt.
        assertFalse(request.onResult(9081)) // Do not consume other plugin results.
        // MainActivity forwards this code regardless of empty/denied/granted arrays.
        assertTrue(request.onResult(NotificationPermissionRequest.REQUEST_CODE))
        assertEquals(listOf(false, true), completed)
        request.onResult(NotificationPermissionRequest.REQUEST_CODE)
        assertEquals(2, completed.size)
        request.launch(a) { completed.add(it) }
        assertEquals(2, completed.size)
        request.dispose()
        request.dispose()
        assertEquals(listOf(false, true, false), completed)
    }

    @Test @Config(sdk = [32]) fun `older Android notification request has no runtime prompt`() {
        val completed = mutableListOf<Boolean>()
        val request = NotificationPermissionRequest()
        request.launch(activity()) { completed.add(it) }
        assertEquals(listOf(true), completed)
        request.dispose()
        assertEquals(1, completed.size)
    }

    // Exercise the production observer against each Android framework version.
    // These are host regressions, not evidence of a physical device permission flow.
    @Test @Config(sdk = [31, 32, 33]) fun `exact alarm denial and recovery are reread without granting on settings launch`() {
        val a = activity()
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        assertEquals("denied", PermissionSettings.snapshot(a)["exactAlarm"])
        assertEquals("notApplicable", PermissionSettings.snapshot(a)["fullScreen"])
        assertTrue(PermissionSettings.open(a, "exactAlarm"))
        val opened = shadowOf(a).nextStartedActivity
        assertEquals(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, opened.action)
        assertEquals("package:${a.packageName}", opened.data.toString())
        assertEquals("denied", PermissionSettings.snapshot(a)["exactAlarm"])
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        assertEquals("granted", PermissionSettings.snapshot(a)["exactAlarm"])
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        assertEquals("denied", PermissionSettings.snapshot(a)["exactAlarm"])
        assertNull(shadowOf(a).nextStartedActivity)
    }

    @Test @Config(sdk = [30, 31, 32, 33, 34]) fun `app notification and overlay revocation remain independent of an allowed alarm channel`() {
        val a = activity()
        val nm = a.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CustomAlarmReceiver.CHANNEL_ID, "alarm", NotificationManager.IMPORTANCE_HIGH))
        shadowOf(nm).setNotificationsEnabled(false)
        ShadowSettings.setCanDrawOverlays(false)
        val denied = PermissionSettings.snapshot(a)
        assertEquals("denied", denied["notification"])
        assertEquals("denied", denied["overlay"])
        assertEquals("granted", denied["alarmChannel"])
        shadowOf(nm).setNotificationsEnabled(true)
        ShadowSettings.setCanDrawOverlays(true)
        val restored = PermissionSettings.snapshot(a)
        assertEquals("granted", restored["notification"])
        assertEquals("granted", restored["overlay"])
        assertEquals("granted", restored["alarmChannel"])
    }

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
