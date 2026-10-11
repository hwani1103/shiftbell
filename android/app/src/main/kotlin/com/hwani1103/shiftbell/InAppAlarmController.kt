package com.hwani1103.shiftbell

import android.app.Activity
import android.app.Dialog
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.Window
import android.view.WindowManager
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import java.lang.ref.WeakReference

/** An app-owned floating entry, independent of overlay/notification permissions.
 * Only a user tap opens the shared alarm controls. Never starts playback or a timer.
 */
object InAppAlarmController {
    private val handler = Handler(Looper.getMainLooper())
    private var host = WeakReference<Activity>(null)
    private var dialog: Dialog? = null
    private var snoozeBinding: SnoozeControlsBinding? = null
    private var shown: RingingAlarmTracker.ActiveRing? = null
    private var shownLocale: String? = null
    private var expandedRing: RingingAlarmTracker.ActiveRing? = null
    private var pulse: ObjectAnimator? = null
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

    private fun hide(clearExpansion: Boolean = true) {
        pulse?.cancel()
        pulse = null
        snoozeBinding?.close()
        snoozeBinding = null
        dialog?.dismiss()
        dialog = null
        shown = null
        shownLocale = null
        if (clearExpansion) expandedRing = null
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
        val expanded = expandedRing == current
        if (shown == current && shownLocale == locale && dialog?.isShowing == true) {
            resizeWindow(activity, dialog!!, expanded)
            snoozeBinding?.refresh()
            return
        }
        hide(clearExpansion = false)
        if (!expanded) {
            expandedRing = null
            showButton(activity, current, locale)
            return
        }
        showControls(activity, current, locale)
    }

    private fun valid(activity: Activity, ring: RingingAlarmTracker.ActiveRing): Boolean =
        host.get() === activity && !activity.isFinishing && !activity.isDestroyed &&
            RingingAlarmTracker.isLiveRing(activity) &&
            RingingAlarmTracker.isCurrent(activity, ring.alarmId, ring.round)

    private fun collapse(activity: Activity, ring: RingingAlarmTracker.ActiveRing) {
        if (!valid(activity, ring)) { changed(); return }
        expandedRing = null
        hide(clearExpansion = false)
        reconcile()
    }

    private fun dp(activity: Activity, value: Int) =
        (value * activity.resources.displayMetrics.density).toInt()

    private fun showButton(activity: Activity, current: RingingAlarmTracker.ActiveRing, locale: String) {
        val ui = AppTextScale.context(activity)
        val circle = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.WHITE)
            setStroke(dp(activity, 1), 0x33808080)
        }
        val button = FrameLayout(ui).apply {
            id = R.id.in_app_alarm_button
            contentDescription = ui.getString(R.string.in_app_alarm_open)
            isClickable = true
            isFocusable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            background = RippleDrawable(ColorStateList.valueOf(0x224B63D9), circle, null)
        }
        val icon = ImageView(ui).apply {
            setImageDrawable(activity.applicationInfo.loadIcon(activity.packageManager))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        button.addView(icon, FrameLayout.LayoutParams(dp(activity, 42), dp(activity, 42), Gravity.CENTER))
        button.addView(View(ui).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFFDC3545.toInt())
                setStroke(dp(activity, 2), Color.WHITE)
            }
        }, FrameLayout.LayoutParams(dp(activity, 12), dp(activity, 12), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(activity, 3)
            marginEnd = dp(activity, 3)
        })
        button.setOnClickListener {
            if (shown != current || !valid(activity, current)) { changed(); return@setOnClickListener }
            expandedRing = current
            hide(clearExpansion = false)
            reconcile()
        }
        val entry = Dialog(activity)
        entry.requestWindowFeature(Window.FEATURE_NO_TITLE)
        entry.setContentView(button)
        entry.setCancelable(false)
        entry.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            // Small app-owned window above Flutter routes/sheets; outside touches
            // and the keyboard remain with the underlying app. No overlay permission.
            addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        if (!valid(activity, current)) return
        try { entry.show() } catch (_: WindowManager.BadTokenException) { return }
        resizeWindow(activity, entry, false)
        dialog = entry
        shown = current
        shownLocale = locale
        // Preserve the previous foreground presentation acknowledgement only
        // after a real control entry is visible, not merely after observing 7777.
        NotificationHelper.markRingPresented(activity, current)
        val accessibility = activity.getSystemService(Activity.ACCESSIBILITY_SERVICE) as AccessibilityManager
        if ((Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled()) &&
            !accessibility.isTouchExplorationEnabled) {
            pulse = ObjectAnimator.ofPropertyValuesHolder(icon,
                PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 1.12f),
                PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 1.12f)).apply {
                duration = 900
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.REVERSE
                start()
            }
        }
        android.util.Log.d("InAppAlarm", "Floating entry shown: id=${current.alarmId} round=${current.round}")
    }

    private fun showControls(activity: Activity, current: RingingAlarmTracker.ActiveRing, locale: String) {
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
        // Reserve the unused trailing end of the time row. Do not change the
        // shared external-overlay layout or repurpose X (which still ends the alarm).
        view.findViewById<TextView>(R.id.timeText).setPaddingRelative(0, 0, dp(activity, 48), 0)
        (view as FrameLayout).addView(ImageButton(ui).apply {
            id = R.id.in_app_alarm_collapse
            contentDescription = ui.getString(R.string.in_app_alarm_collapse)
            setImageResource(R.drawable.ic_alarm_collapse)
            background = RippleDrawable(ColorStateList.valueOf(0x33FFFFFF),
                GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0x22302D4A)
                }, null)
            setPadding(dp(activity, 12), dp(activity, 12), dp(activity, 12), dp(activity, 12))
            setOnClickListener { collapse(activity, current) }
        }, FrameLayout.LayoutParams(dp(activity, 48), dp(activity, 48), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(activity, 12)
            marginEnd = dp(activity, 12)
        })
        val card = Dialog(activity)
        card.requestWindowFeature(Window.FEATURE_NO_TITLE)
        card.setContentView(view)
        card.setCancelable(true)
        card.setCanceledOnTouchOutside(false)
        card.setOnCancelListener { if (dialog === card) collapse(activity, current) }
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
        resizeWindow(activity, card, true)
        dialog = card
        shown = current
        shownLocale = locale
        snoozeBinding = SnoozeControlsBinding(view, current) { reconcile() }
        NotificationHelper.markRingPresented(activity, current)
    }

    private fun resizeWindow(activity: Activity, card: Dialog, expanded: Boolean) {
        val width = activity.resources.configuration.screenWidthDp
        val density = activity.resources.displayMetrics.density
        card.window?.apply {
            setGravity(if (expanded) Gravity.TOP or Gravity.CENTER_HORIZONTAL else Gravity.TOP or Gravity.END)
            setLayout(if (!expanded) dp(activity, 56)
                else if (width <= 500) WindowManager.LayoutParams.MATCH_PARENT
                else (minOf(width - 32, 720) * density).toInt(),
                if (expanded) WindowManager.LayoutParams.WRAP_CONTENT else dp(activity, 56))
            attributes = attributes.apply {
                x = if (expanded) 0 else dp(activity, 12)
                y = dp(activity, 12)
            }
        }
    }
}
