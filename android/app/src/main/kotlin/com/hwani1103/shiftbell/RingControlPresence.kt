package com.hwani1103.shiftbell

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/** A point-in-time OS observation, not a guarantee of heads-up or shade visibility. */
internal object RingControlPresence {
    enum class Result { PRESENT, ABSENT, BLOCKED, UNKNOWN }

    fun observe(context: Context, ring: RingingAlarmTracker.ActiveRing): Result = try {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            Result.BLOCKED
        } else {
            val posted = manager.activeNotifications.firstOrNull {
                it.id == NotificationHelper.RING_CONTROL_ID &&
                    it.tag == NotificationHelper.ringTag(ring) &&
                    it.notification.extras.getInt("shiftbell.copy.alarm", -1) == ring.alarmId &&
                    it.notification.extras.getLong("shiftbell.copy.round", -1) == ring.round
            }
            if (Build.VERSION.SDK_INT < 26) {
                if (posted == null) Result.ABSENT else Result.PRESENT
            } else {
                // When absent, inspect the channel used by the existing initial-post policy.
                // Never wait on a known block, and never create or change a channel here.
                val channelId = posted?.notification?.channelId ?: run {
                    val primary = manager.getNotificationChannel(CustomAlarmReceiver.CHANNEL_ID)
                    val legacy = manager.getNotificationChannel("alarm_control")
                    if (primary?.importance == NotificationManager.IMPORTANCE_NONE &&
                        legacy != null && legacy.importance != NotificationManager.IMPORTANCE_NONE) {
                        "alarm_control"
                    } else CustomAlarmReceiver.CHANNEL_ID
                }
                val availability = channelAvailability(manager, channelId)
                if (posted == null && availability == Result.PRESENT) Result.ABSENT else availability
            }
        }
    } catch (e: Exception) {
        Log.w("RingControlPresence", "Cannot confirm current ring notification; retain overlay fallback", e)
        Result.UNKNOWN
    }

    @android.annotation.TargetApi(26)
    private fun channelAvailability(manager: NotificationManager, id: String): Result {
        val channel = manager.getNotificationChannel(id) ?: return Result.UNKNOWN
        return when {
            channel.importance == NotificationManager.IMPORTANCE_NONE -> Result.BLOCKED
            channel.importance < NotificationManager.IMPORTANCE_MIN -> Result.UNKNOWN
            Build.VERSION.SDK_INT >= 28 && channel.group != null -> {
                val group = manager.getNotificationChannelGroup(channel.group)
                when {
                    group == null -> Result.UNKNOWN
                    group.isBlocked -> Result.BLOCKED
                    else -> Result.PRESENT
                }
            }
            else -> Result.PRESENT
        }
    }

}
