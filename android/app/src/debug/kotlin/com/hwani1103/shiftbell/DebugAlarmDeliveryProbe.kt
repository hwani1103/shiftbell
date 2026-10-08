package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.io.File

/** Dev-debug only: native delivery A/B, no Flutter, database, audio or wake lock.
 * Run modes in separate locked-screen rounds: one alarm could wake the other.
 * Shell: am broadcast -n <dev-package>/.DebugAlarmDeliveryProbe
 *        --es op schedule --es mode alarm_clock --el delay_ms 90000
 * mode=allow_idle uses setExactAndAllowWhileIdle. op=cancel cancels only probes.
 * Evidence: run-as <dev-package> cat files/debug_alarm_probe.jsonl
 */
class DebugAlarmDeliveryProbe : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
            context.packageName != "com.hwani1103.shiftbell.dev") return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val mode = intent.getStringExtra("mode") ?: ""
        val op = intent.getStringExtra("op") ?: ""
        try {
            if (op == "cancel") {
                for (kind in MODES) {
                    val pending = operation(context, kind, 0)
                    manager.cancel(pending)
                    pending.cancel()
                }
                record(context, "cancel", "all", 0)
                return
            }
            if (mode !in MODES) return
            if (op == "fired" && intent.action == FIRE_ACTION) {
                val target = intent.getLongExtra("target_ms", 0)
                if (target > 0) record(context, "fired", mode, target)
                return
            }
            if (op != "schedule") return
            val delay = intent.getLongExtra("delay_ms", 90_000)
            require(delay in 30_000L..600_000L) { "delay_ms must be 30000..600000" }
            val target = System.currentTimeMillis() + delay
            val operation = operation(context, mode, target)
            if (mode == "alarm_clock") {
                val show = PendingIntent.getActivity(context, 9041,
                    Intent(context, MainActivity::class.java).setAction("shiftbell.DEBUG_PROBE_SHOW"),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                manager.setAlarmClock(AlarmManager.AlarmClockInfo(target, show), operation)
            } else {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target, operation)
            }
            record(context, "scheduled", mode, target)
        } catch (error: Exception) {
            record(context, "error", mode, 0, error.javaClass.simpleName)
        }
    }

    private fun operation(context: Context, mode: String, target: Long): PendingIntent =
        PendingIntent.getBroadcast(context, 9040,
            Intent(context, DebugAlarmDeliveryProbe::class.java).apply {
                action = FIRE_ACTION
                data = Uri.parse("shiftbell-debug://delivery-probe/$mode")
                putExtra("op", "fired")
                putExtra("mode", mode)
                putExtra("target_ms", target)
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun record(context: Context, event: String, mode: String, target: Long,
        error: String? = null) {
        val now = System.currentTimeMillis()
        val record = JSONObject().put("event", event).put("mode", mode)
            .put("targetMs", target).put("wallMs", now)
            .put("elapsedMs", SystemClock.elapsedRealtime())
            .put("interactive", (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive)
        if (target > 0) record.put("delayMs", now - target)
        if (error != null) record.put("error", error)
        Log.i("ShiftBellDeliveryProbe", record.toString())
        try { File(context.filesDir, "debug_alarm_probe.jsonl").appendText(record.toString() + "\n") }
        catch (error: Exception) { Log.w("ShiftBellDeliveryProbe", "Evidence write failed", error) }
    }

    companion object {
        private const val FIRE_ACTION = "com.hwani1103.shiftbell.DEBUG_DELIVERY_PROBE"
        private val MODES = setOf("alarm_clock", "allow_idle")
    }
}
