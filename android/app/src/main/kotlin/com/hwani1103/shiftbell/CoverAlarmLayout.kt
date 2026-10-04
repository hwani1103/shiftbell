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

/** Cover-only layout: real window size determines stacked versus side-by-side controls. */
internal object CoverAlarmLayout {
    fun create(context: Context, time: String, dismiss: () -> Unit, snooze: () -> Unit): View {
        val density = context.resources.displayMetrics.density
        fun dp(n: Float) = (n * density).roundToInt()
        val root = LinearLayout(context).apply {
            gravity = Gravity.CENTER
            setPadding(dp(16f), dp(16f), dp(16f), dp(16f))
        }
        val clock = TextView(context).apply {
            text = time
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(106, 79, 217))
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke(dp(3f), Color.rgb(173, 155, 238))
            }
        }
        val actions = LinearLayout(context).apply { gravity = Gravity.CENTER }
        fun button(label: String, primary: Boolean, action: () -> Unit) = Button(context).apply {
            text = label
            isAllCaps = false
            setTextColor(if (primary) Color.WHITE else Color.rgb(59, 46, 122))
            background = GradientDrawable().apply {
                cornerRadius = dp(28f).toFloat()
                setColor(if (primary) Color.rgb(106, 79, 217) else Color.rgb(230, 223, 249))
            }
            minWidth = 0
            minHeight = dp(48f)
            setPadding(dp(8f), 0, dp(8f), 0)
            setOnClickListener { action() }
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, 18f * context.resources.configuration.fontScale.coerceIn(1f, 1.3f))
            setAutoSizeTextTypeUniformWithConfiguration(12,
                (18f * context.resources.configuration.fontScale.coerceIn(1f, 1.3f)).roundToInt(), 1, TypedValue.COMPLEX_UNIT_DIP)
        }
        val later = button("+5m", false, snooze)
        val stop = button(context.getString(R.string.alarm_dismiss_label), true, dismiss)
        actions.addView(later)
        actions.addView(stop)
        root.addView(clock)
        root.addView(actions)
        root.setOnApplyWindowInsetsListener { _, insets ->
            // Keep controls in the rectangular safe area of the folder-shaped Flex Window.
            // Insets already excluded from the window arrive as zero: do not subtract a
            // model-specific camera strip a second time. Reserve hidden navigation bars too.
            val cutout = insets.displayCutout
            val bars = if (Build.VERSION.SDK_INT >= 30)
                insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            else null
            root.setPadding(
                dp(16f) + maxOf(bars?.left ?: insets.stableInsetLeft, insets.systemWindowInsetLeft, cutout?.safeInsetLeft ?: 0),
                dp(16f) + maxOf(bars?.top ?: insets.stableInsetTop, insets.systemWindowInsetTop, cutout?.safeInsetTop ?: 0),
                dp(16f) + maxOf(bars?.right ?: insets.stableInsetRight, insets.systemWindowInsetRight, cutout?.safeInsetRight ?: 0),
                dp(16f) + maxOf(bars?.bottom ?: insets.stableInsetBottom, insets.systemWindowInsetBottom,
                    cutout?.safeInsetBottom ?: 0, if (Build.VERSION.SDK_INT >= 29) insets.mandatorySystemGestureInsets.bottom else 0))
            insets
        }
        var last = ""
        val ringBackground = clock.background
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val width = root.width - root.paddingLeft - root.paddingRight
            val height = root.height - root.paddingTop - root.paddingBottom
            val key = "$width/$height"
            if (width <= 0 || height <= 0 || key == last) return@addOnLayoutChangeListener
            last = key
            // A square 5/6 window stays stacked even when display zoom reduces its dp height.
            // The narrow horizontal 3/4 window still uses a clock beside vertical actions.
            val compact = width > height * 1.4 || height / density < 140
            val tiny = height / density < 110
            root.orientation = if (compact) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            actions.orientation = if (compact && !tiny) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            val diameter = if (tiny) min(height, (width * .30f).roundToInt())
                else if (compact) min(height, (width * .48f).roundToInt())
                else min((width * .72f).roundToInt(), height - dp(84f)).coerceAtLeast(dp(64f))
            clock.background = if (tiny) null else ringBackground
            clock.layoutParams = LinearLayout.LayoutParams(diameter, diameter).apply {
                if (compact) rightMargin = dp(12f) else bottomMargin = dp(20f)
            }
            clock.setTextSize(TypedValue.COMPLEX_UNIT_PX, (diameter * .23f).coerceAtLeast(dp(14f).toFloat()))
            actions.layoutParams = LinearLayout.LayoutParams(
                if (compact) (width - diameter - dp(12f)).coerceAtLeast(dp(48f)) else width,
                if (compact) height else dp(56f))
            for (index in 0..1) {
                actions.getChildAt(index).layoutParams = if (compact && !tiny)
                    LinearLayout.LayoutParams(-1, 0, 1f).apply { if (index == 0) bottomMargin = dp(8f) }
                else LinearLayout.LayoutParams(0, -1, 1f).apply { if (index == 0) rightMargin = dp(if (tiny) 4f else 12f) }
            }
        }
        return FrameLayout(context).apply {
            addView(WaveGradientView(context).apply {
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, FrameLayout.LayoutParams(-1, -1))
            addView(root, FrameLayout.LayoutParams(-1, -1))
        }
    }
}
