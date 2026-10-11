package com.hwani1103.shiftbell

import android.content.Context
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/** Measure the entire control group together, before drawing or resizing a window. */
class AlarmControlLayout(context: Context, attrs: AttributeSet? = null) : LinearLayout(context, attrs) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        if (available > 0) {
            // 64 + 12 + 200 + 12 + 64 = 352. Dismissal is 80, pill height 88.
            val unit = available / 352f
            fun size(id: Int, width: Int, height: Int) {
                findViewById<View>(id).layoutParams.apply {
                    this.width = (width * unit).roundToInt()
                    this.height = (height * unit).roundToInt()
                }
            }
            size(R.id.snoozeDecreaseButton, 64, 64)
            size(R.id.snoozeIncreaseButton, 64, 64)
            size(R.id.dismissButton, 80, 80)
            for ((id, textSize) in listOf(R.id.snoozeDecreaseButton to 36f, R.id.snoozeIncreaseButton to 36f, R.id.dismissButton to 46f)) {
                findViewById<TextView>(id).setTextSize(TypedValue.COMPLEX_UNIT_PX, textSize * unit)
            }
            val pill = findViewById<View>(R.id.snoozeButton).parent as View
            (pill.layoutParams as LayoutParams).apply {
                height = (88 * unit).roundToInt()
                leftMargin = (12 * unit).roundToInt(); rightMargin = leftMargin
            }
            (findViewById<View>(R.id.dismissButton).layoutParams as ViewGroup.MarginLayoutParams).topMargin = (24 * unit).roundToInt()
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}
