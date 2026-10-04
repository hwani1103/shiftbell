package com.hwani1103.shiftbell

import android.view.View
import android.widget.TextView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import kotlin.math.min
import kotlin.math.roundToInt

/** Changes only geometry. Ring state, timeout, dismissal and snooze stay owned
 * by AlarmActivity. Ordinary phone geometry is restored from the original XML. */
internal object AlarmResponsiveLayout {
    fun install(root: ConstraintLayout) {
        val original = ConstraintSet().apply { setForceId(false); clone(root) }
        val clock = root.findViewById<TextView>(R.id.timeText)
        val originalClockWidth = clock.layoutParams.width
        val originalClockHeight = clock.layoutParams.height
        val originalClockText = clock.textSize
        val guideline = View.generateViewId()
        var lastSize = Pair(0, 0)
        root.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            val width = right - left
            val height = bottom - top
            if (width <= 0 || height <= 0 || lastSize == Pair(width, height)) return@addOnLayoutChangeListener
            lastSize = Pair(width, height)
            val density = root.resources.displayMetrics.density
            val w = width / density
            val h = height / density
            val wide = w > 500
            val shortCover = w in 380f..500f && h <= 700 && h > w && w / h >= 0.61f
            fun dp(value: Float) = (value * density).roundToInt()
            val set = ConstraintSet().apply { setForceId(false); clone(original) }
            var circle = originalClockWidth
            var text = originalClockText
            if (wide) {
                val square = w / h >= 0.85f
                set.create(guideline, ConstraintSet.VERTICAL_GUIDELINE)
                set.setGuidelinePercent(guideline, if (square) 0.50f else 0.48f)
                set.connect(R.id.alarmCard, ConstraintSet.END, guideline, ConstraintSet.START)
                set.connect(R.id.alarmCard, ConstraintSet.BOTTOM, ConstraintSet.PARENT_ID, ConstraintSet.BOTTOM, dp(24f))
                set.setMargin(R.id.alarmCard, ConstraintSet.TOP, dp(24f))
                set.setVerticalBias(R.id.alarmCard, 0.5f)
                set.connect(R.id.buttonContainer, ConstraintSet.START, guideline, ConstraintSet.END)
                set.setMargin(R.id.buttonContainer, ConstraintSet.BOTTOM, dp(h * 0.25f))
                set.connect(R.id.swipeHintContainer, ConstraintSet.TOP, ConstraintSet.PARENT_ID, ConstraintSet.TOP, dp(24f))
                set.connect(R.id.swipeHintContainer, ConstraintSet.START, guideline, ConstraintSet.END)
                set.setVerticalBias(R.id.swipeHintContainer, 0.75f)
                circle = dp(min(w * 0.39f, h * 0.48f).coerceIn(200f, 360f))
                text = originalClockText * (circle.toFloat() / originalClockWidth).coerceAtMost(1.3f)
            } else if (shortCover) {
                circle = dp(min(w * 0.6f, h * 0.36f).coerceIn(180f, 240f))
                set.setMargin(R.id.alarmCard, ConstraintSet.TOP, dp(16f))
                set.setMargin(R.id.buttonContainer, ConstraintSet.BOTTOM, dp(28f))
            }
            set.applyTo(root)
            clock.layoutParams = clock.layoutParams.apply {
                this.width = circle
                this.height = if (wide || shortCover) circle else originalClockHeight
            }
            clock.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, text)
        }
    }
}
