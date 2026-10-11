package com.hwani1103.shiftbell

import android.content.Context
import android.os.Build
import android.os.PowerManager
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Locale

/** Read-only telemetry adapter. Never called from alarm delivery or scheduling. */
object OperationsSnapshot {
    private const val WINDOW_MS = 72L * 60 * 60 * 1000
    private val events = mapOf(
        "SCHEDULE_OK" to "alarm_schedule_ok", "SCHEDULE_FAIL" to "alarm_schedule_failed",
        "ALARM_FIRED" to "alarm_fired", "REFRESH_DONE" to "alarm_refresh_completed",
        "REFRESH_FAIL" to "alarm_refresh_failed"
    )

    internal fun observations(text: String, now: Long): List<Map<String, Any>> {
        val date = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).apply { isLenient = false }
        val duplicates = mutableMapOf<String, Int>()
        return text.lineSequence().mapNotNull { line ->
            try {
                val parts = line.split(" | ", limit = 3)
                if (parts.size < 2) return@mapNotNull null
                val at = date.parse(parts[0])?.time ?: return@mapNotNull null
                if (at < now - WINDOW_MS || at > now) return@mapNotNull null
                val event = events[parts[1]] ?: if (parts[1] == "SYSTEM_EVENT" &&
                    Regex("(?:^| )action=(?:LOCKED_BOOT_COMPLETED|BOOT_COMPLETED)(?: |$)").containsMatchIn(parts.getOrElse(2) { "" }))
                    "device_boot_seen" else return@mapNotNull null
                // An ordinal preserves distinct, identical records in one millisecond.
                val hash = MessageDigest.getInstance("SHA-256").digest(line.toByteArray(Charsets.UTF_8))
                    .joinToString("") { "%02x".format(it) }
                val ordinal = duplicates[hash] ?: 0
                duplicates[hash] = ordinal + 1
                mapOf("token" to (hash + ":" + ordinal), "event" to event, "atMs" to at)
            } catch (_: Exception) { null }
        }.toList().takeLast(1000)
    }

    fun read(context: Context, permissions: Map<String, Any>): Map<String, Any> {
        val now = System.currentTimeMillis()
        val battery = try {
            if (Build.VERSION.SDK_INT < 23) "notApplicable"
            else if (context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)) "unrestricted"
            else "restricted"
        } catch (_: Exception) { "unknown" }
        return mapOf("manufacturer" to Build.MANUFACTURER.lowercase(Locale.ROOT),
            "battery" to battery, "permissions" to permissions,
            "observations" to observations(DiagLog.readAll(context), now))
    }
}
