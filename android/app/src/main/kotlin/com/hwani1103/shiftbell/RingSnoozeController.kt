package com.hwani1103.shiftbell

import android.content.Context
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.lang.ref.WeakReference

sealed interface SnoozeExecution {
    data object IgnoredStale : SnoozeExecution
    data object InvalidInput : SnoozeExecution
    data class Scheduled(val alarmId: Int, val targetAt: Long, val timeText: String, val shiftType: String) : SnoozeExecution
    data class Collision(val alarmId: Int, val targetAt: Long, val message: String) : SnoozeExecution
    data class DbFailed(val alarmId: Int) : SnoozeExecution
    data class OsFailed(val alarmId: Int, val targetAt: Long) : SnoozeExecution
    data class Unverified(val alarmId: Int, val targetAt: Long) : SnoozeExecution
    data class Superseded(val alarmId: Int) : SnoozeExecution
    data class ExecutionFailed(val alarmId: Int, val stage: String) : SnoozeExecution
}

/** All commands run on the app main thread, including notification broadcasts.
 * Only the tracker owns selection; views bind immutable snapshots to clicks. */
object RingSnoozeController {
    data class Click(val selection: RingingAlarmTracker.SnoozeSelection,
        val acceptedWallMillis: Long, val acceptedElapsedMillis: Long)
    private val observers = mutableListOf<WeakReference<Subscription>>()
    internal var stopForTest: ((Context) -> Unit)? = null
    internal var closeForTest: ((Context, Int) -> Boolean)? = null
    internal fun resetForTest() { stopForTest = null; closeForTest = null; observers.clear() }
    class Subscription internal constructor(internal val ring: RingingAlarmTracker.ActiveRing,
        internal val callback: (RingingAlarmTracker.SnoozeSelection) -> Unit) : AutoCloseable {
        internal var closed = false
        override fun close() { closed = true; observers.removeAll { it.get() == null || it.get() === this } }
    }
    private fun main() = check(Looper.myLooper() == Looper.getMainLooper()) { "Ring controls require main thread" }
    fun observe(ring: RingingAlarmTracker.ActiveRing, callback: (RingingAlarmTracker.SnoozeSelection) -> Unit): Subscription {
        main()
        return Subscription(ring, callback).also { observers.add(WeakReference(it)) }
    }
    fun adjust(context: Context, ring: RingingAlarmTracker.ActiveRing, steps: Int): RingingAlarmTracker.SnoozeSelection? {
        main()
        val before = RingingAlarmTracker.selectionForLiveRing(context, ring) ?: return null
        val selected = RingingAlarmTracker.adjustSnooze(context, ring, steps) ?: return null
        NotificationHelper.markRingPresented(context, ring) // Actual user interaction, not a delay heuristic.
        if (before != selected) {
            publishSelection(context, selected)
        }
        return selected
    }
    /** Serialized with UI/receiver clicks. Saving never stops or reschedules a ring. */
    fun setDefault(context: Context, minutes: Int): Boolean {
        main()
        require(SnoozeDefaults.valid(minutes))
        if (!SnoozeDefaults.write(context, minutes)) return false
        val ring = RingingAlarmTracker.current(context)
        val before = ring?.let { RingingAlarmTracker.selectionForLiveRing(context, it) }
        val selected = RingingAlarmTracker.setLiveSnooze(context, minutes)
        if (selected != null && selected != before) {
            NotificationHelper.markRingPresented(context, selected.ring)
            publishSelection(context, selected)
        }
        return true
    }
    private fun publishSelection(context: Context, selected: RingingAlarmTracker.SnoozeSelection) {
        val ring = selected.ring
        observers.mapNotNull { it.get() }.filter { !it.closed && it.ring == ring }.forEach {
            try { it.callback(selected) } catch (error: Exception) { Log.e("RingSnooze", "Selection observer failed", error) }
        }
        observers.removeAll { it.get() == null || it.get()?.closed == true }
        NotificationHelper.refreshExistingRing(context, ring, NotificationHelper.RingNoticeReason.SELECTION)
        Log.i("RingSnooze", "SELECT id=${ring.alarmId} round=${ring.round} minutes=${selected.minutes} revision=${selected.revision}")
    }
    fun click(selection: RingingAlarmTracker.SnoozeSelection) = Click(selection, System.currentTimeMillis(), SystemClock.elapsedRealtime())
    internal fun targetAt(acceptedWallMillis: Long, minutes: Int): Long {
        require(SnoozeText.valid(minutes))
        val raw = Math.addExact(acceptedWallMillis, minutes.toLong() * 60_000L)
        return Math.addExact(AlarmWakeScheduler.normalize(raw), if (Math.floorMod(raw, 1000L) == 0L) 0L else 1000L)
    }
    fun execute(context: Context, click: Click, legacy: Boolean = false): SnoozeExecution {
        main()
        val (ring, minutes, revision) = click.selection
        if (!SnoozeText.valid(minutes) || revision < 0) return SnoozeExecution.InvalidInput
        if (!legacy && RingingAlarmTracker.selectionForLiveRing(context, ring) == null) return SnoozeExecution.IgnoredStale
        val target = try { targetAt(click.acceptedWallMillis, minutes) } catch (_: ArithmeticException) { return SnoozeExecution.InvalidInput }
        if (!AlarmActionHelper.claimRingEnd(context, ring.alarmId, ring.round)) return SnoozeExecution.IgnoredStale
        var failedStage: String? = null
        val result = try {
            try { stopForTest?.invoke(context) ?: AlarmPlayer.getInstance(context.applicationContext).stopAlarm() }
            catch (error: Exception) { failedStage = "stop"; Log.e("RingSnooze", "Stop failed", error) }
            try { if (!(closeForTest?.invoke(context, ring.alarmId) ?: AlarmActionHelper.closeRingUi(context, ring.alarmId))) failedStage = "closeUi" }
            catch (error: Exception) { failedStage = "closeUi"; Log.e("RingSnooze", "UI cleanup failed", error) }
            if (failedStage != null) SnoozeExecution.ExecutionFailed(ring.alarmId, failedStage!!)
            else AlarmActionHelper.snoozeAt(context, ring.alarmId, target, selectedMinutes = minutes)
        } catch (error: Exception) {
            Log.e("RingSnooze", "Snooze execution failed", error)
            SnoozeExecution.ExecutionFailed(ring.alarmId, "execute")
        } finally {
            RingingAlarmTracker.finishTransition(ring.alarmId)
        }
        Log.i("RingSnooze", "EXECUTE id=${ring.alarmId} round=${ring.round} minutes=$minutes revision=$revision accepted=${click.acceptedWallMillis} target=$target elapsed=${SystemClock.elapsedRealtime() - click.acceptedElapsedMillis} result=${result.javaClass.simpleName}")
        try { SnoozeFeedback.publish(context, ring, result) }
        catch (error: Exception) { Log.e("RingSnooze", "Outcome presentation failed", error) }
        return result
    }
}
