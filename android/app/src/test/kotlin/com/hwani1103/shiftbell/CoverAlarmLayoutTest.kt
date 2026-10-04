package com.hwani1103.shiftbell

import android.content.Context
import android.app.Activity
import android.content.res.Configuration
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Robolectric
import org.robolectric.shadows.ShadowLooper
import kotlin.math.roundToInt

@RunWith(RobolectricTestRunner::class)
class CoverAlarmLayoutTest {
    @Test fun controlsStayInsideSmallAndLargeCoverWindows() {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        for (scale in listOf(.85f, 1f, 1.3f, 2f)) {
            val config = Configuration(base.resources.configuration).apply { fontScale = scale }
            val context = base.createConfigurationContext(config)
            val density = context.resources.displayMetrics.density
            for ((w, h) in listOf(192 to 98, 260 to 130, 512 to 260, 399 to 393, 399 to 441, 360 to 320)) {
                var dismissals = 0
                var snoozes = 0
                val surface = CoverAlarmLayout.create(context, "07:00", { dismissals++ }, { snoozes++ }) as FrameLayout
                val root = surface.getChildAt(1) as LinearLayout
                surface.removeViewAt(0)
                controller.get().setContentView(surface)
                val width = (w * density).roundToInt()
                val height = (h * density).roundToInt()
                repeat(3) {
                    ShadowLooper.idleMainLooper()
                    surface.forceLayout()
                    root.forceLayout()
                    surface.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                    surface.layout(0, 0, width, height)
                }
                val actions = root.getChildAt(1) as LinearLayout
                assertTrue("clock laid out $w/$h/$scale", root.getChildAt(0).width >= 30 * density)
                assertFalse("clock overlaps actions $w/$h/$scale", android.graphics.Rect.intersects(
                    android.graphics.Rect(root.getChildAt(0).left, root.getChildAt(0).top, root.getChildAt(0).right, root.getChildAt(0).bottom),
                    android.graphics.Rect(actions.left, actions.top, actions.right, actions.bottom)))
                assertTrue("actions bottom $w/$h/$scale", actions.bottom <= height)
                assertTrue("actions right $w/$h/$scale", actions.right <= width)
                for (i in 0..1) {
                    val button = actions.getChildAt(i) as Button
                    assertTrue("touch width $w/$h/$scale: ${button.width / density}", button.width / density >= 47.5f)
                    assertTrue("touch height $w/$h/$scale", button.height / density >= 47.5f)
                    assertTrue(button.bottom <= actions.height)
                    assertTrue(button.right <= actions.width)
                    button.performClick()
                }
                assertEquals(1, dismissals)
                assertEquals(1, snoozes)
            }
        }
        controller.pause().stop().destroy()
    }
}
