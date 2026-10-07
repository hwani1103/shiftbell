package com.hwani1103.shiftbell

import android.content.Context
import android.util.Log
import android.widget.Toast

object SnoozeFeedback {
    private fun prefs(context: Context) = context.createDeviceProtectedStorageContext().getSharedPreferences("snooze_feedback", Context.MODE_PRIVATE)
    internal fun message(context: Context, code: String) = context.getString(when (code) {
        "db" -> R.string.snooze_failed_db
        "superseded" -> R.string.snooze_superseded
        "execution" -> R.string.snooze_failed_execution
        else -> R.string.snooze_failed_schedule
    })
    fun publish(context: Context, ring: RingingAlarmTracker.ActiveRing, result: SnoozeExecution) {
        val code = when (result) {
            is SnoozeExecution.Scheduled -> {
                NotificationHelper.showUpdatedNotification(context, result.timeText, result.shiftType)
                return
            }
            is SnoozeExecution.Collision -> {
                Toast.makeText(context, result.message, Toast.LENGTH_LONG).show()
                return
            }
            is SnoozeExecution.DbFailed -> "db"
            is SnoozeExecution.ExecutionFailed -> "execution"
            is SnoozeExecution.Superseded -> "superseded"
            is SnoozeExecution.OsFailed, is SnoozeExecution.Unverified -> "schedule"
            else -> return
        }
        prefs(context).edit().putString("code", code).putLong("at", System.currentTimeMillis())
            .putInt("id", ring.alarmId).putLong("round", ring.round).commit()
        Log.e("SnoozeFeedback", "id=${ring.alarmId} round=${ring.round} failure=$code")
        Toast.makeText(context, message(context, code), Toast.LENGTH_LONG).show()
        try { NotificationHelper.showSnoozeFailure(context, code) }
        catch (error: Exception) { Log.w("SnoozeFeedback", "Failure notification unavailable; saved for next app resume", error) }
    }
    fun consume(context: Context) {
        val p = prefs(context)
        val code = p.getString("code", null) ?: return
        Toast.makeText(context, message(context, code), Toast.LENGTH_LONG).show()
        p.edit().clear().commit()
    }
}
