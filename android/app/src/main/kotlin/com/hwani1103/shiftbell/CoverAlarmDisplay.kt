package com.hwani1103.shiftbell

import android.app.ActivityManager
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.DisplayMetrics
import android.view.Display

/** Samsung built-in covers, including small covers without the full-screen feature flag. */
internal object CoverAlarmDisplay {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null
    private var discoveredCoverId: Int? = null

    private fun coverDisplay(context: Context): Display? {
        val manager = context.getSystemService(DisplayManager::class.java)
        val primary = manager.getDisplay(Display.DEFAULT_DISPLAY) ?: return null
        fun matches(it: Display) =
            it.displayId != Display.DEFAULT_DISPLAY && it.name == primary.name &&
                it.flags and Display.FLAG_PRESENTATION != 0 &&
                it.flags and Display.FLAG_PRIVATE == 0
        discoveredCoverId?.let { id ->
            manager.getDisplay(id)?.takeIf(::matches)?.let { return it }
            discoveredCoverId = null
        }
        val listed = manager.displays.filter(::matches)
        val candidates = if (listed.isNotEmpty()) listed else if (Build.MANUFACTURER.equals("samsung", true)) {
            // Older Samsung firmware omits the cover from both public display lists,
            // although getDisplay and app-owned Activity launch work. Discover once;
            // validate every candidate instead of assuming a specific target ID.
            (1..8).mapNotNull(manager::getDisplay).filter(::matches)
        } else emptyList()
        return candidates.singleOrNull()?.also { discoveredCoverId = it.displayId }
    }

    fun supported(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 29) return false
        if (context.packageManager.hasSystemFeature("com.samsung.feature.full_screen_sub_display")) return true
        if (!Build.MANUFACTURER.equals("samsung", ignoreCase = true)) return false
        val cover = coverDisplay(context) ?: return false
        val metrics = DisplayMetrics().also(cover::getRealMetrics)
        // Some Flip firmware (including tested Flip4/5) omits the newer feature flag.
        // Bound both dimensions so Fold covers and ordinary external screens are excluded.
        val width = metrics.widthPixels / metrics.density
        val height = metrics.heightPixels / metrics.density
        return minOf(width, height) in 80f..450f && maxOf(width, height) in 160f..600f
    }

    fun followRing(context: Context, id: Int, round: Long, duration: Int) {
        if (!supported(context)) return
        pending?.let(handler::removeCallbacks)
        val app = context.applicationContext
        val manager = app.getSystemService(DisplayManager::class.java)
        var previousTarget: Int? = null
        val check = object : Runnable {
            override fun run() {
                if (!RingingAlarmTracker.isCurrent(app, id, round)) {
                    pending = null
                    return
                }
                val primary = manager.getDisplay(Display.DEFAULT_DISPLAY)
                // Called after the existing alarm wake-up. The inner screen turns ON when unfolded.
                val cover = coverDisplay(app)
                val coverAwake = cover != null && cover.state != Display.STATE_OFF && cover.state != Display.STATE_UNKNOWN
                val target = when {
                    primary?.state == Display.STATE_ON -> Display.DEFAULT_DISPLAY
                    coverAwake && primary?.state == Display.STATE_OFF -> cover!!.displayId
                    else -> previousTarget ?: Display.DEFAULT_DISPLAY
                }
                if (target != previousTarget && (target != Display.DEFAULT_DISPLAY || previousTarget != null)) {
                    val intent = Intent(app, AlarmActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
                        putExtra("alarmId", id)
                        putExtra("alarmDuration", duration)
                        putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
                    }
                    try {
                        if (app.getSystemService(ActivityManager::class.java).isActivityStartAllowedOnDisplay(app, target, intent)) {
                            app.startActivity(intent, ActivityOptions.makeBasic().setLaunchDisplayId(target).toBundle())
                            Log.i("CoverAlarm", "Requested display=$target id=$id round=$round")
                        }
                    } catch (e: Exception) {
                        Log.w("CoverAlarm", "Cover launch unavailable; existing alarm remains active", e)
                    }
                }
                previousTarget = target
                handler.postDelayed(this, 750)
            }
        }
        pending = check
        handler.post(check)
    }
}
