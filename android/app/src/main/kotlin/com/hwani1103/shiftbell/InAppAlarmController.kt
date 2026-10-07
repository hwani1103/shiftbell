package com.hwani1103.shiftbell

import android.app.Activity
import android.app.Dialog
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.Window
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import java.lang.ref.WeakReference

/** An app-owned window using the identical external overlay layout/resources.
 * It only presents an existing live round; it never starts playback or a timer.
 */
object InAppAlarmController {
    private val handler = Handler(Looper.getMainLooper())
    private var host = WeakReference<Activity>(null)
    private var dialog: Dialog? = null
    private var snoozeBinding: SnoozeControlsBinding? = null
    private var shown: RingingAlarmTracker.ActiveRing? = null
    private var shownLocale: String? = null
    val isHostVisible: Boolean get() = host.get()?.let { !it.isFinishing && !it.isDestroyed } == true

    fun resume(activity: Activity) {
        host = WeakReference(activity)
        changed()
    }

    fun pause(activity: Activity) {
        if (host.get() === activity) {
            host.clear()
            hide()
        }
    }

    fun changed() { handler.post { reconcile() } }

    private fun hide() {
        snoozeBinding?.close()
        snoozeBinding = null
        dialog?.dismiss()
        dialog = null
        shown = null
        shownLocale = null
    }

    private fun reconcile() {
        val activity = host.get() ?: return
        if (activity.isFinishing || activity.isDestroyed) { hide(); return }
        val current = RingingAlarmTracker.current(activity)
        if (current == null || !RingingAlarmTracker.isLiveRing(activity) ||
            AlarmOverlayService.visibleRing == current || AlarmActivity.visibleRing == current) {
            hide()
            return
        }
        val locale = activity.resources.configuration.locales.toLanguageTags()
        if (shown == current && shownLocale == locale && dialog?.isShowing == true) {
            snoozeBinding?.refresh()
            return
        }
        hide()
        val ui = AppTextScale.context(activity)
        val view = LayoutInflater.from(ui).inflate(R.layout.overlay_alarm, null)
        view.findViewById<TextView>(R.id.timeText).text = "--:--"
        view.findViewById<TextView>(R.id.shiftTypeText).setText(R.string.alarm_default_label)
        try {
            val db = DatabaseHelper.getInstance(activity).getReadableDatabaseWithRetry()
            db?.query("alarms", arrayOf("time", "shift_type", "type"),
                "id = ?", arrayOf(current.alarmId.toString()), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    view.findViewById<TextView>(R.id.timeText).text = cursor.getString(0) ?: ""
                    view.findViewById<TextView>(R.id.shiftTypeText).text = cursor.getString(1)
                        ?: ui.getString(R.string.alarm_default_label)
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("InAppAlarm", "Display metadata unavailable; controls remain usable", e)
        }
        if (!RingingAlarmTracker.isCurrent(activity, current.alarmId, current.round)) return
        fun act(action: String) {
            AlarmActionReceiver().onReceive(activity.applicationContext, Intent().apply {
                this.action = action
                putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, current.alarmId)
                putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, current.round)
            })
            reconcile()
        }
        view.findViewById<Button>(R.id.dismissButton).setOnClickListener {
            act(AlarmActionReceiver.ACTION_DISMISS_FROM_NOTIFICATION)
        }
        val card = Dialog(activity)
        card.requestWindowFeature(Window.FEATURE_NO_TITLE)
        card.setContentView(view)
        card.setCancelable(false)
        card.setCanceledOnTouchOutside(false)
        card.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            // Settings remain usable while ringing (including live snooze defaults).
            // Outside taps reach Flutter without dismissing or ending this card.
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
            setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
        }
        try { card.show() } catch (e: WindowManager.BadTokenException) {
            android.util.Log.w("InAppAlarm", "Host left before card could be shown", e)
            return
        }
        val width = activity.resources.configuration.screenWidthDp
        val density = activity.resources.displayMetrics.density
        card.window?.apply {
            setLayout(if (width <= 500) WindowManager.LayoutParams.MATCH_PARENT
                else (minOf(width - 32, 720) * density).toInt(), WindowManager.LayoutParams.WRAP_CONTENT)
            attributes = attributes.apply { y = (12 * density).toInt() }
        }
        dialog = card
        shown = current
        shownLocale = locale
        snoozeBinding = SnoozeControlsBinding(view, current) { reconcile() }
        NotificationHelper.markRingPresented(activity, current)
    }
}
