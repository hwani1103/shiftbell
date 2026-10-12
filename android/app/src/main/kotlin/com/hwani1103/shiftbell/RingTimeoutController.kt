package com.hwani1103.shiftbell

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/** Process-owned watchdog. Neither opening nor destroying a window restarts it.
 * A killed process cannot keep its MediaPlayer/vibrator running; persisted old
 * rounds are never rearmed by opening the app. AlarmManager is a second path.
 */
object RingTimeoutController {
    private val handler = Handler(Looper.getMainLooper())
    private var ring: RingingAlarmTracker.ActiveRing? = null
    private var deadline = 0L
    private var task: Runnable? = null
    private var wakeLock: PowerManager.WakeLock? = null
    internal val isHoldingWakeLock: Boolean get() = wakeLock?.isHeld == true

    fun start(context: Context, current: RingingAlarmTracker.ActiveRing, minutes: Int): Long {
        if (ring == current) return deadline
        clear()
        ring = current
        val duration = minutes.coerceAtLeast(1).toLong() * 60_000L
        deadline = SystemClock.elapsedRealtime() + duration
        val app = context.applicationContext
        try {
            wakeLock = (app.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ShiftBell:RingDeadline")
                .apply { setReferenceCounted(false); acquire(duration + 30_000L) }
        } catch (e: Exception) {
            Log.w("RingDeadline", "Wake lock unavailable; OS deadline retained", e)
        }
        task = Runnable {
            if (ring == current) {
                if (RingingAlarmTracker.isCurrent(app, current.alarmId, current.round)) {
                    Log.i("RingDeadline", "Elapsed deadline id=${current.alarmId} round=${current.round}")
                    AlarmActionReceiver().onReceive(app, Intent().apply {
                        action = AlarmActionReceiver.ACTION_RING_TIMEOUT
                        putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, current.alarmId)
                        putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, current.round)
                    })
                } else clear()
            }
        }
        handler.postDelayed(task!!, duration)
        Log.i("RingDeadline", "Armed id=${current.alarmId} round=${current.round} deadline=$deadline duration=$duration")
        InAppAlarmController.changed()
        return deadline
    }

    fun remaining(current: RingingAlarmTracker.ActiveRing): Long? =
        if (ring == current) (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0) else null

    fun cancel(current: RingingAlarmTracker.ActiveRing) {
        if (ring == current) clear()
        InAppAlarmController.changed()
    }

    internal fun clear() {
        task?.let { handler.removeCallbacks(it) }
        task = null
        ring = null
        deadline = 0
        try { if (wakeLock?.isHeld == true) wakeLock?.release() }
        finally { wakeLock = null }
    }
}
