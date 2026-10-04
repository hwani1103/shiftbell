package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import kotlin.math.roundToInt

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AlarmOverlayLayoutTest {
    @Test fun clockRemainsReadableBesideAlarmControls() {
        val base = ApplicationProvider.getApplicationContext<Context>()
        for (scale in listOf(1f, 1.6f, 2f)) {
            val config = Configuration(base.resources.configuration).apply { fontScale = scale }
            val context = base.createConfigurationContext(config)
            val root = LayoutInflater.from(context).inflate(R.layout.overlay_alarm, null) as FrameLayout
            root.removeViewAt(0) // Animated background does not affect content geometry.
            root.findViewById<TextView>(R.id.timeText).text = "23:59"
            root.findViewById<TextView>(R.id.shiftTypeText).text = "Late Night Shift"
            // Reuse the visible overlay across folding and unfolding.
            for (widthDp in listOf(720, 320, 360, 720)) {
                val width = (widthDp * context.resources.displayMetrics.density).roundToInt()
                root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                root.layout(0, 0, width, root.measuredHeight)
                val clock = root.findViewById<TextView>(R.id.timeText)
                println("overlay $widthDp/$scale: textSize=${clock.textSize}, textWidth=${clock.paint.measureText(clock.text.toString())}, available=${clock.width}, lines=${clock.lineCount}")
                assertEquals("clock stays on one line $widthDp/$scale", 1, clock.lineCount)
                assertTrue("clock fits without clipping $widthDp/$scale",
                    clock.paint.measureText(clock.text.toString()) <= clock.width - clock.totalPaddingLeft - clock.totalPaddingRight + 1)
                for (id in listOf(R.id.dismissButton, R.id.snoozeButton)) {
                    val button = root.findViewById<View>(id)
                    assertTrue("action target $widthDp/$scale", button.width >= 48 * context.resources.displayMetrics.density)
                }
            }
        }
    }
}
