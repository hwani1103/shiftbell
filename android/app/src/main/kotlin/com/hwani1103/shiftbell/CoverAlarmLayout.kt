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
        var arrangeBeforeMeasure: ((Int, Int) -> Unit)? = null
        val root = object : LinearLayout(context) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                // Size the compact controls before their initial text measurement.
                arrangeBeforeMeasure?.invoke(MeasureSpec.getSize(widthMeasureSpec), MeasureSpec.getSize(heightMeasureSpec))
                super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            }
        }.apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }
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
        fun roundButton(id: Int, symbol: String, action: () -> Unit) = button(id, symbol, true, action).apply {
            background = context.getDrawable(R.drawable.alarm_lock_control)
            backgroundTintList = null; stateListAnimator = null
            includeFontPadding = false; gravity = Gravity.CENTER
            setAutoSizeTextTypeWithDefaults(TextView.AUTO_SIZE_TEXT_TYPE_NONE)
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, if (id == R.id.dismissButton) 36f else 28f)
            setTextColor(Color.WHITE)
        }
        val minus = roundButton(R.id.snoozeDecreaseButton, "−") {}
        val later = button(R.id.snoozeButton, "", false, snooze).apply {
            background = context.getDrawable(R.drawable.alarm_lock_snooze_ripple)
            backgroundTintList = null; stateListAnimator = null
        }
        val plus = roundButton(R.id.snoozeIncreaseButton, "+") {}
        val stop = roundButton(R.id.dismissButton, "×", dismiss)
        val title = TextView(context).apply {
            id = R.id.lockSnoozeTitle; text = context.getString(R.string.alarm_snooze_title)
            gravity = Gravity.CENTER; setTextColor(Color.rgb(48,39,70)); typeface = Typeface.DEFAULT_BOLD
            maxLines = 1; setAutoSizeTextTypeUniformWithConfiguration(10,20,1,TypedValue.COMPLEX_UNIT_DIP)
        }
        val value = TextView(context).apply {
            id = R.id.snoozeValueText; text = context.getString(R.string.alarm_snooze_duration,5)
            gravity = Gravity.CENTER; setTextColor(Color.rgb(48,39,70)); typeface = Typeface.DEFAULT_BOLD
            maxLines = 1; setAutoSizeTextTypeUniformWithConfiguration(12,24,1,TypedValue.COMPLEX_UNIT_DIP)
        }
        val pillText = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(title,LinearLayout.LayoutParams(-1,0,1f)); addView(value,LinearLayout.LayoutParams(-1,0,1f))
        }
        val pill = FrameLayout(context).apply {
            background = context.getDrawable(R.drawable.alarm_lock_snooze)
            addView(pillText,FrameLayout.LayoutParams(-1,-1))
            addView(later,FrameLayout.LayoutParams(-1,-1))
        }
        val stopLabel = TextView(context).apply {
            text = context.getString(R.string.alarm_dismiss_label); gravity = Gravity.CENTER
            setTextColor(Color.rgb(59,46,122)); setTextSize(TypedValue.COMPLEX_UNIT_DIP,16f)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val stopGroup = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            // Give the first text layout the same bounded width as the control.
            addView(stop,LinearLayout.LayoutParams(dp(48),dp(48)))
            addView(stopLabel,LinearLayout.LayoutParams(-1,dp(24)))
        }
        stop.contentDescription = context.getString(R.string.alarm_dismiss_label)
        minus.contentDescription = context.getString(R.string.alarm_snooze_decrease)
        plus.contentDescription = context.getString(R.string.alarm_snooze_increase)
        later.contentDescription = SnoozeText.description(context, 5)
        minus.isEnabled = false
        choice.addView(minus, LinearLayout.LayoutParams(dp(48), dp(48)))
        choice.addView(pill, LinearLayout.LayoutParams(0, dp(48), 1f))
        choice.addView(plus, LinearLayout.LayoutParams(dp(48), dp(48)))
        actions.addView(choice); actions.addView(stopGroup)
        root.addView(clock); root.addView(actions)
        var insetLeft = 0; var insetTop = 0; var insetRight = 0; var insetBottom = 0
        var last = ""
        fun arrange(measuredWidth: Int, measuredHeight: Int) {
            val safeWidth = measuredWidth - insetLeft - insetRight
            val safeHeight = measuredHeight - insetTop - insetBottom
            if (safeWidth <= 0 || safeHeight <= 0) return
            val padding = if (safeWidth >= dp(192) && safeHeight >= dp(128)) dp(16) else 0
            val width = safeWidth - padding * 2
            val height = safeHeight - padding * 2
            val key = "$width/$height/$insetLeft/$insetTop/$insetRight/$insetBottom"
            if (key == last) return
            last = key
            root.setPadding(insetLeft + padding, insetTop + padding, insetRight + padding, insetBottom + padding)
            val single = height < dp(96) && width >= dp(208)
            val controlWidth = min(width, dp(352))
            val unit = controlWidth / 352f
            val roomy = height >= (192 * unit).roundToInt() + dp(24) && width >= dp(264)
            val side = if (roomy) (64 * unit).roundToInt() else dp(48)
            val stopSize = if (roomy) (80 * unit).roundToInt() else dp(48)
            val rowHeight = if (roomy) (88 * unit).roundToInt() else dp(48)
            val gap = if (roomy) (12 * unit).roundToInt() else 0
            val stopGap = if (roomy) (24 * unit).roundToInt() else 0
            for ((control, size) in listOf(minus to 36f, plus to 36f, stop to 46f)) {
                control.setAutoSizeTextTypeWithDefaults(TextView.AUTO_SIZE_TEXT_TYPE_NONE)
                control.setTextSize(TypedValue.COMPLEX_UNIT_PX, if (roomy) size * unit else dp(if (control === stop) 36 else 28).toFloat())
            }
            val labelHeight = if (height >= dp(150) && !single) dp(24) else 0
            val controlsHeight = if (single) dp(48) else rowHeight + stopGap + stopSize + labelHeight
            if (!(width >= dp(160) && height >= dp(96)) && !(width >= dp(208) && height >= dp(48)))
                android.util.Log.e("CoverAlarm", "UNSUPPORTED safe controls area ${width / density} x ${height / density} dp")
            actions.orientation = if (single) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            actions.layoutParams = LinearLayout.LayoutParams(controlWidth, controlsHeight)
            choice.layoutParams = if (single) LinearLayout.LayoutParams(0, rowHeight, 1f) else LinearLayout.LayoutParams(-1, rowHeight)
            minus.layoutParams = LinearLayout.LayoutParams(side,side)
            plus.layoutParams = LinearLayout.LayoutParams(side,side)
            pill.layoutParams = LinearLayout.LayoutParams(0,rowHeight,1f).apply { leftMargin = gap; rightMargin = gap }
            pillText.setPadding(dp(if (roomy) 14 else 3),dp(if (roomy) 10 else 0),dp(if (roomy) 14 else 3),dp(if (roomy) 10 else 0))
            stopGroup.layoutParams = LinearLayout.LayoutParams(if (single) stopSize else -1,stopSize+labelHeight).apply { topMargin = if (single) 0 else stopGap }
            stop.layoutParams = LinearLayout.LayoutParams(stopSize,stopSize)
            stopLabel.visibility = if (labelHeight > 0) View.VISIBLE else View.GONE
            val diameter = min(min(width, dp(260)), height - controlsHeight - dp(16))
            clock.visibility = if (diameter >= dp(64)) View.VISIBLE else View.GONE
            clock.layoutParams = LinearLayout.LayoutParams(diameter.coerceAtLeast(0), diameter.coerceAtLeast(0)).apply { bottomMargin = dp(16) }
            clock.setTextSize(TypedValue.COMPLEX_UNIT_PX, (diameter * .23f).coerceAtLeast(dp(14).toFloat()))
        }
        arrangeBeforeMeasure = ::arrange
        root.setOnApplyWindowInsetsListener { _, insets ->
            val cutout = insets.displayCutout
            val bars = if (Build.VERSION.SDK_INT >= 30) insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()) else null
            insetLeft = maxOf(bars?.left ?: insets.stableInsetLeft, insets.systemWindowInsetLeft, cutout?.safeInsetLeft ?: 0)
            insetTop = maxOf(bars?.top ?: insets.stableInsetTop, insets.systemWindowInsetTop, cutout?.safeInsetTop ?: 0)
            insetRight = maxOf(bars?.right ?: insets.stableInsetRight, insets.systemWindowInsetRight, cutout?.safeInsetRight ?: 0)
            insetBottom = maxOf(bars?.bottom ?: insets.stableInsetBottom, insets.systemWindowInsetBottom, cutout?.safeInsetBottom ?: 0,
                if (Build.VERSION.SDK_INT >= 29) insets.mandatorySystemGestureInsets.bottom else 0)
            root.requestLayout(); insets
        }
        return FrameLayout(context).apply {
            addView(WaveGradientView(context).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }, FrameLayout.LayoutParams(-1, -1))
            addView(root, FrameLayout.LayoutParams(-1, -1))
        }
    }
}
