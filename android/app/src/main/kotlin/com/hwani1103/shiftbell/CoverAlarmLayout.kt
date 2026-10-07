package com.hwani1103.shiftbell

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.min
import kotlin.math.roundToInt

/** Controls retain 48dp targets. Tiny covers sacrifice the decorative clock first. */
internal object CoverAlarmLayout {
    fun create(context: Context, time: String, dismiss: () -> Unit, snooze: () -> Unit): View {
        val density = context.resources.displayMetrics.density
        fun dp(n: Int) = (n * density).roundToInt()
        val root = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }
        val clock = TextView(context).apply {
            id = R.id.timeText; text = time; gravity = Gravity.CENTER
            setTextColor(Color.rgb(106, 79, 217)); typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) }
        }
        val actions = LinearLayout(context).apply { gravity = Gravity.CENTER; orientation = LinearLayout.VERTICAL }
        val choice = LinearLayout(context).apply { gravity = Gravity.CENTER }
        fun button(viewId: Int, label: String, primary: Boolean, action: () -> Unit) = Button(context).apply {
            id = viewId; text = label; isAllCaps = false
            setTextColor(if (primary) Color.WHITE else Color.rgb(59, 46, 122))
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(if (primary) Color.rgb(106, 79, 217) else Color.rgb(230, 223, 249))
            }
            minWidth = 0; minHeight = dp(48); minimumWidth = 0; minimumHeight = dp(48)
            setPadding(dp(4), 0, dp(4), 0)
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, 18f)
            setAutoSizeTextTypeUniformWithConfiguration(12, 24, 1, TypedValue.COMPLEX_UNIT_DIP)
            setOnClickListener { action() }
        }
        val minus = button(R.id.snoozeDecreaseButton, "−", false) {}
        val later = button(R.id.snoozeButton, SnoozeText.compact(5), false, snooze)
        val plus = button(R.id.snoozeIncreaseButton, "+", false) {}
        val stop = button(R.id.dismissButton, context.getString(R.string.alarm_dismiss_label), true, dismiss)
        stop.contentDescription = context.getString(R.string.alarm_dismiss_label)
        minus.contentDescription = context.getString(R.string.alarm_snooze_decrease)
        plus.contentDescription = context.getString(R.string.alarm_snooze_increase)
        later.contentDescription = SnoozeText.description(context, 5)
        minus.isEnabled = false
        choice.addView(minus, LinearLayout.LayoutParams(dp(48), dp(48)))
        choice.addView(later, LinearLayout.LayoutParams(0, dp(48), 1f))
        choice.addView(plus, LinearLayout.LayoutParams(dp(48), dp(48)))
        actions.addView(choice); actions.addView(stop)
        root.addView(clock); root.addView(actions)
        var insetLeft = 0; var insetTop = 0; var insetRight = 0; var insetBottom = 0
        var last = ""
        fun arrange() {
            val safeWidth = root.width - insetLeft - insetRight
            val safeHeight = root.height - insetTop - insetBottom
            if (safeWidth <= 0 || safeHeight <= 0) return
            val padding = if (safeWidth >= dp(192) && safeHeight >= dp(128)) dp(16) else 0
            val width = safeWidth - padding * 2
            val height = safeHeight - padding * 2
            val key = "$width/$height/$insetLeft/$insetTop/$insetRight/$insetBottom"
            if (key == last) return
            last = key
            root.setPadding(insetLeft + padding, insetTop + padding, insetRight + padding, insetBottom + padding)
            val single = height < dp(96) && width >= dp(208)
            val controlsHeight = dp(if (single) 48 else 96)
            stop.text = if (single) "×" else context.getString(R.string.alarm_dismiss_label)
            if (!(width >= dp(160) && height >= dp(96)) && !(width >= dp(208) && height >= dp(48)))
                android.util.Log.e("CoverAlarm", "UNSUPPORTED safe controls area ${width / density} x ${height / density} dp")
            actions.orientation = if (single) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            actions.layoutParams = LinearLayout.LayoutParams(min(width, dp(360)), controlsHeight)
            choice.layoutParams = if (single) LinearLayout.LayoutParams(0, dp(48), 1f) else LinearLayout.LayoutParams(-1, dp(48))
            stop.layoutParams = LinearLayout.LayoutParams(if (single) dp(48) else -1, dp(48))
            val diameter = min(min(width, dp(260)), height - controlsHeight - dp(16))
            clock.visibility = if (diameter >= dp(64)) View.VISIBLE else View.GONE
            clock.layoutParams = LinearLayout.LayoutParams(diameter.coerceAtLeast(0), diameter.coerceAtLeast(0)).apply { bottomMargin = dp(16) }
            clock.setTextSize(TypedValue.COMPLEX_UNIT_PX, (diameter * .23f).coerceAtLeast(dp(14).toFloat()))
        }
        root.setOnApplyWindowInsetsListener { _, insets ->
            val cutout = insets.displayCutout
            val bars = if (Build.VERSION.SDK_INT >= 30) insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()) else null
            insetLeft = maxOf(bars?.left ?: insets.stableInsetLeft, insets.systemWindowInsetLeft, cutout?.safeInsetLeft ?: 0)
            insetTop = maxOf(bars?.top ?: insets.stableInsetTop, insets.systemWindowInsetTop, cutout?.safeInsetTop ?: 0)
            insetRight = maxOf(bars?.right ?: insets.stableInsetRight, insets.systemWindowInsetRight, cutout?.safeInsetRight ?: 0)
            insetBottom = maxOf(bars?.bottom ?: insets.stableInsetBottom, insets.systemWindowInsetBottom, cutout?.safeInsetBottom ?: 0,
                if (Build.VERSION.SDK_INT >= 29) insets.mandatorySystemGestureInsets.bottom else 0)
            arrange(); insets
        }
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> arrange() }
        return FrameLayout(context).apply {
            addView(WaveGradientView(context).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }, FrameLayout.LayoutParams(-1, -1))
            addView(root, FrameLayout.LayoutParams(-1, -1))
        }
    }
}
