package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.Instrumentation
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.os.Bundle
import android.os.SystemClock
import org.json.JSONObject

/** Runs only in the separately installed dev test APK. Never produces sound or vibration. */
object DevRingWatchdogAudit {
    /** Sends the REAL notification PendingIntent and waits five real minutes.
     * This verifies dispatch and scheduling; it does not claim a human UI tap.
     */
    fun snooze(test: Instrumentation): JSONObject {
        val context = test.targetContext
        check(context.packageName == "com.hwani1103.shiftbell.dev")
        val db = DatabaseHelper.getInstance(context).getWritableDatabaseWithRetry()!!
        check(!RingingAlarmTracker.isLiveRing(context))
        val durationMinutes = db.rawQuery("SELECT sound_file, volume, vibration_strength, duration FROM alarm_types WHERE id = 3", null).use {
            check(it.moveToFirst() && it.getString(0) == "silent" && it.getFloat(1) == 0f &&
                it.getInt(2) == 0 && it.getInt(3) in 1..3) { "Requires explicitly prepared SILENT fixture" }
            it.getInt(3)
        }
        val id = -970002
        db.rawQuery("SELECT COUNT(*) FROM alarms WHERE id = ?", arrayOf(id.toString())).use {
            check(it.moveToFirst() && it.getInt(0) == 0)
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        check(manager.areNotificationsEnabled())
        fun action(title: Int): PendingIntent = manager.activeNotifications.single { it.id == 7777 }
            .notification.actions.single { it.title.toString() == context.getString(title) }.actionIntent
        fun waitUntil(timeout: Long, predicate: () -> Boolean) {
            val limit = SystemClock.elapsedRealtime() + timeout
            while (!predicate()) {
                check(SystemClock.elapsedRealtime() < limit) { "Timed out waiting for ring state" }
                Thread.sleep(100)
            }
            test.waitForIdleSync()
        }
        val now = AlarmWakeScheduler.normalize(System.currentTimeMillis())
        db.insertOrThrow("alarms", null, ContentValues().apply {
            put("id", id); put("time", "00:00"); put("date", AlarmInstant.format(now))
            put("type", "custom"); put("alarm_type_id", 3)
        })
        try {
            test.runOnMainSync {
                CustomAlarmReceiver().onReceive(context, android.content.Intent().apply {
                    putExtra(CustomAlarmReceiver.EXTRA_ID, id)
                    putExtra(AlarmWakeScheduler.EXTRA_EXPECTED_AT, now)
                })
            }
            waitUntil(10_000) { RingingAlarmTracker.current(context)?.alarmId == id }
            val first = RingingAlarmTracker.current(context)!!
            val staleDismiss = action(R.string.notif_action_dismiss)
            val snoozedAt = SystemClock.elapsedRealtime()
            action(R.string.notif_action_snooze).send()
            waitUntil(10_000) { RingingAlarmTracker.current(context) == null }
            check(!RingTimeoutController.isHoldingWakeLock)
            check(manager.activeNotifications.none { it.id == 7777 })
            test.sendStatus(10, Bundle().apply { putString("stream", "SILENT notification snooze dispatched; waiting five REAL minutes.\n") })
            Thread.sleep(durationMinutes * 60_000L + 5_000)
            check(RingingAlarmTracker.current(context) == null)
            db.rawQuery("SELECT type FROM alarms WHERE id = ?", arrayOf(id.toString())).use {
                check(it.moveToFirst() && it.getString(0) == "snoozed") { "Old deadline consumed snooze" }
            }
            waitUntil(310_000 - (SystemClock.elapsedRealtime() - snoozedAt)) {
                RingingAlarmTracker.current(context)?.alarmId == id
            }
            val elapsed = SystemClock.elapsedRealtime() - snoozedAt
            val second = RingingAlarmTracker.current(context)!!
            check(second.round != first.round && elapsed in 298_500..310_000)
            try { staleDismiss.send() } catch (_: PendingIntent.CanceledException) { }
            Thread.sleep(500)
            check(RingingAlarmTracker.current(context) == second) { "Old control stopped new round" }
            check((RingTimeoutController.remaining(second) ?: 0) > 40_000)
            action(R.string.notif_action_dismiss).send()
            waitUntil(10_000) { RingingAlarmTracker.current(context) == null }
            check(!RingTimeoutController.isHoldingWakeLock)
            check(manager.activeNotifications.none { it.id == 7777 })
            return JSONObject().put("case", "silent_real_notification_snooze")
                .put("elapsedMs", elapsed).put("oldDeadlineAndActionIgnored", true)
                .put("notificationAndWakeLockCleared", true).put("pass", true)
        } finally {
            test.runOnMainSync { AlarmActionHelper.stopRingingAlarm(context, id) }
            AlarmWakeScheduler.cancelRaw(context, id)
            db.delete("alarms", "id = ?", arrayOf(id.toString()))
            db.delete("alarm_history", "alarm_id = ?", arrayOf(id.toString()))
            db.delete("alarm_creation_log", "alarm_id = ?", arrayOf(id.toString()))
        }
    }

    fun run(test: Instrumentation): JSONObject {
        val context = test.targetContext
        check(context.packageName == "com.hwani1103.shiftbell.dev")
        val db = DatabaseHelper.getInstance(context).getWritableDatabaseWithRetry()!!
        check(!RingingAlarmTracker.isLiveRing(context))
        val id = -970001
        db.rawQuery("SELECT COUNT(*) FROM alarms WHERE id = ?", arrayOf(id.toString())).use {
            check(it.moveToFirst() && it.getInt(0) == 0) { "Audit ID already occupied" }
        }
        db.insertOrThrow("alarms", null, ContentValues().apply {
            put("id", id); put("time", "00:00"); put("date", AlarmInstant.format(System.currentTimeMillis()))
            put("type", "custom"); put("alarm_type_id", 3)
        })
        var started = 0L
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        val originalVolume = audio.getStreamVolume(android.media.AudioManager.STREAM_ALARM)
        val playerField = AlarmPlayer::class.java.getDeclaredField("mediaPlayer").apply { isAccessible = true }
        try {
            test.runOnMainSync {
                val ring = RingingAlarmTracker.startRing(context, id)
                started = SystemClock.elapsedRealtime()
                AlarmActionHelper.scheduleRingTimeout(context, ring, 1)
                val backup = AlarmActionHelper.ringTimeoutPendingIntent(context, id, ring.round,
                    PendingIntent.FLAG_NO_CREATE)!!
                (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(backup)
                // Gain is set to zero BEFORE MediaPlayer.start; vibration is disabled.
                // This exercises a real looping player without any audible output.
                check(VolumeCalibration.linearGain(0f) == 0f)
                AlarmPlayer.getInstance(context).playAlarmWithSettings("alarmbell1", 0f, 0)
                check((playerField.get(AlarmPlayer.getInstance(context)) as? android.media.MediaPlayer)?.isPlaying == true)
            }
            test.sendStatus(10, Bundle().apply { putString("stream", "SILENT watchdog armed; OS backup removed; no alarm UI.\n") })
            Thread.sleep(55_000)
            check(RingingAlarmTracker.current(context)?.alarmId == id) { "Ended before 55 seconds" }
            val limit = started + 65_000
            while (RingingAlarmTracker.current(context)?.alarmId == id && SystemClock.elapsedRealtime() < limit) {
                Thread.sleep(50)
            }
            val elapsed = SystemClock.elapsedRealtime() - started
            test.waitForIdleSync()
            check(RingingAlarmTracker.current(context) == null) { "Independent watchdog did not end ring" }
            check(!RingTimeoutController.isHoldingWakeLock) { "Wake lock leaked" }
            check(playerField.get(AlarmPlayer.getInstance(context)) == null) { "MediaPlayer leaked" }
            check(audio.getStreamVolume(android.media.AudioManager.STREAM_ALARM) == originalVolume)
            check(elapsed in 59_500..62_000) { "Unexpected deadline: $elapsed ms" }
            db.rawQuery("SELECT dismiss_type FROM alarm_history WHERE alarm_id = ?", arrayOf(id.toString())).use {
                check(it.moveToFirst() && it.getString(0) == "timeout" && !it.moveToNext())
            }
            return JSONObject().put("case", "silent_watchdog_without_OS_or_UI")
                .put("elapsedMs", elapsed).put("wakeLockReleased", true)
                .put("mutedPlayerReleased", true).put("originalVolumeRestored", true).put("pass", true)
        } finally {
            test.runOnMainSync { AlarmActionHelper.stopRingingAlarm(context, id) }
            db.delete("alarms", "id = ?", arrayOf(id.toString()))
            db.delete("alarm_history", "alarm_id = ?", arrayOf(id.toString()))
        }
    }
}
