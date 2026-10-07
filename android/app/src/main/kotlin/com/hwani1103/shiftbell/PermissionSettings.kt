package com.hwani1103.shiftbell

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import java.util.Locale

/** OS observations only: opening settings never grants a permission. */
object PermissionSettings {
    private fun observed(check: () -> Boolean): String = try {
        if (check()) "granted" else "denied"
    } catch (_: Exception) { "unknown" }

    fun isXiaomiFamily(manufacturer: String, brand: String): Boolean =
        listOf(manufacturer, brand).any {
            it.trim().lowercase(Locale.ROOT) in setOf("xiaomi", "redmi", "poco")
        }

    fun snapshot(activity: Activity): Map<String, Any> {
        val nm = activity.getSystemService(NotificationManager::class.java)
        val xiaomi = isXiaomiFamily(Build.MANUFACTURER, Build.BRAND) && try {
            activity.packageManager.getPackageInfo("com.miui.securitycenter", 0)
            true
        } catch (_: Exception) { false }
        return mapOf(
            "notification" to observed { NotificationManagerCompat.from(activity).areNotificationsEnabled() },
            "overlay" to if (Build.VERSION.SDK_INT < 23) "notApplicable" else observed { Settings.canDrawOverlays(activity) },
            "exactAlarm" to if (Build.VERSION.SDK_INT < 31) "notApplicable" else observed {
                activity.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
            },
            "fullScreen" to if (Build.VERSION.SDK_INT < 34) "notApplicable" else observed { nm.canUseFullScreenIntent() },
            // A blocked channel is distinct from app-wide notification denial.
            "alarmChannel" to if (Build.VERSION.SDK_INT < 26) "notApplicable" else observed {
                val current = nm.getNotificationChannel(CustomAlarmReceiver.CHANNEL_ID)
                val legacy = nm.getNotificationChannel("alarm_control")
                current == null || current.importance != NotificationManager.IMPORTANCE_NONE ||
                    (legacy != null && legacy.importance != NotificationManager.IMPORTANCE_NONE)
            },
            "xiaomi" to xiaomi,
            "sdk" to Build.VERSION.SDK_INT
        )
    }

    fun intent(activity: Activity, kind: String): Intent? {
        val uri = Uri.parse("package:${activity.packageName}")
        return when (kind) {
            "notification" -> if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName) else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
            "alarmChannel" -> if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, CustomAlarmReceiver.CHANNEL_ID) else null
            "overlay" -> if (Build.VERSION.SDK_INT >= 23) Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri) else null
            "exactAlarm" -> if (Build.VERSION.SDK_INT >= 31) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, uri) else null
            "fullScreen" -> if (Build.VERSION.SDK_INT >= 34) Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, uri) else null
            "xiaomi" -> Intent("miui.intent.action.APP_PERM_EDITOR")
                .addCategory(Intent.CATEGORY_DEFAULT).setPackage("com.miui.securitycenter")
                .putExtra("extra_pkgname", activity.packageName).putExtra("extra_package_uid", Process.myUid())
            "app" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
            else -> null
        }
    }

    fun open(activity: Activity, kind: String): Boolean {
        val target = intent(activity, kind) ?: return false
        return launchWithFallback(target, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${activity.packageName}"))) { activity.startActivity(it) }
    }

    internal fun launchWithFallback(target: Intent, fallback: Intent, launch: (Intent) -> Unit): Boolean {
        try { launch(target); return true } catch (_: Exception) { }
        return try { launch(fallback); true } catch (_: Exception) { false }
    }
}
