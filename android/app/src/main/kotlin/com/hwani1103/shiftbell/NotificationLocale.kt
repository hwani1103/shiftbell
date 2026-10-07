package com.hwani1103.shiftbell

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat

/** Refresh only existing presentation; never schedule alarms or restart a ring. */
object NotificationLocale {
    private const val KIND = "shiftbell.copy.kind"
    private const val TIME = "shiftbell.copy.time"
    private const val LANGUAGE = "shiftbell.copy.locale"
    private const val ALARM_ID = "shiftbell.copy.alarm"
    private const val ROUND = "shiftbell.copy.round"

    fun metadata(context: Context, kind: String, time: String = "", alarmId: Int = -1, round: Long = -1) = Bundle().apply {
        putString(KIND, kind)
        putString(TIME, time)
        putString(LANGUAGE, context.resources.configuration.locales.toLanguageTags())
        putInt(ALARM_ID, alarmId)
        putLong(ROUND, round)
    }

    internal fun translated(context: Context, old: Notification): Notification? {
        val extras = old.extras ?: return null
        val kind = extras.getString(KIND) ?: return null
        val language = context.resources.configuration.locales.toLanguageTags()
        if (extras.getString(LANGUAGE) == language) return null
        val builder = NotificationCompat.Builder(context, old)
            .setOnlyAlertOnce(true).setSilent(true).setFullScreenIntent(null, false)
        when (kind) {
            "guard" -> builder.setContentTitle(context.getString(R.string.notif_guard_title, extras.getString(TIME)))
            "snooze" -> builder.setContentTitle(context.getString(R.string.notif_snoozed_title, extras.getString(TIME)))
            "snoozeFailure" -> {
                val body = SnoozeFeedback.message(context, extras.getString(TIME) ?: "schedule")
                builder.setContentTitle(context.getString(R.string.snooze_failure_title))
                    .setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            }
            "restore" -> {
                val body = context.getString(R.string.notif_restore_text)
                builder.setContentTitle(context.getString(R.string.notif_restore_title))
                    .setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            }
            "ring" -> {
                if (extras.getInt(RingControlNotification.VERSION, 1) == 2) return null
                if (NotificationCompat.getActionCount(old) != 2) return null
                val body = context.getString(R.string.notif_ringing_content)
                builder.setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body)).clearActions()
                for ((index, key) in listOf(R.string.notif_action_snooze, R.string.notif_action_dismiss).withIndex()) {
                    val action = NotificationCompat.getAction(old, index) ?: return null
                    builder.addAction(NotificationCompat.Action.Builder(action.iconCompat, context.getString(key), action.actionIntent)
                        .addExtras(action.extras).build())
                }
            }
            else -> return null
        }
        builder.addExtras(Bundle().apply { putString(LANGUAGE, language) })
        return builder.build()
    }

    fun refresh(context: Context) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Only rename channels that already exist; preserve user blocking/importance.
                for ((id, keys) in mapOf(
                    "shiftbell_result_v3" to (R.string.channel_alarm_result to R.string.channel_result_description),
                    "shiftbell_pre_v3" to (R.string.channel_alarm_guard to R.string.channel_guard_description),
                    "shiftbell_restore" to (R.string.channel_restore_notify to 0),
                    CustomAlarmReceiver.CHANNEL_ID to (0 to R.string.channel_ring_description))) {
                    val channel = manager.getNotificationChannel(id) ?: continue
                    if (keys.first != 0) channel.name = context.getString(keys.first)
                    if (keys.second != 0) channel.description = context.getString(keys.second)
                    manager.createNotificationChannel(channel)
                }
            }
            for (posted in manager.activeNotifications) {
                val old = posted.notification
                if (old.extras.getInt(RingControlNotification.VERSION, 1) == 2) {
                    if (old.extras.getString(LANGUAGE) != context.resources.configuration.locales.toLanguageTags()) {
                        NotificationHelper.refreshExistingRing(context,
                            RingingAlarmTracker.ActiveRing(old.extras.getInt(ALARM_ID), old.extras.getLong(ROUND)),
                            NotificationHelper.RingNoticeReason.LOCALE)
                    }
                    continue
                }
                if (old.extras.getString(KIND) == "ring" &&
                    !NotificationHelper.mayRefreshRingLocale(context, old.extras.getInt(ALARM_ID), old.extras.getLong(ROUND))) continue
                val updated = translated(context, old) ?: continue
                val publish = {
                    // Do not restore an already dismissed/replaced notification snapshot.
                    if (manager.activeNotifications.any { it.key == posted.key && it.postTime == posted.postTime }) {
                        manager.notify(posted.tag, posted.id, updated)
                    }
                }
                if (old.extras.getString(KIND) == "ring") {
                    RingingAlarmTracker.runIfCurrent(context, old.extras.getInt(ALARM_ID), old.extras.getLong(ROUND), publish)
                } else publish()
            }
        } catch (error: Exception) {
            Log.w("NotificationLocale", "Could not refresh notification copy", error)
        }
    }
}
