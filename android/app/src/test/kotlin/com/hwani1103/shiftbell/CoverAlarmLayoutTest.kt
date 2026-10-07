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
    @Test fun selectedValuesAndLocalizedLabelsFitTinyCovers() {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        for (tag in listOf("ko", "en", "de", "pt-BR", "hi")) for (minutes in listOf(5,15,30))
            for (scale in listOf(1f, 2f)) for ((w, h) in listOf(192 to 98, 399 to 441)) {
            val context = base.createConfigurationContext(Configuration(base.resources.configuration).apply {
                fontScale = scale; setLocale(java.util.Locale.forLanguageTag(tag))
            })
            val d = context.resources.displayMetrics.density
            val surface = CoverAlarmLayout.create(context, "23:59", {}, {}) as FrameLayout
            surface.removeViewAt(0)
            controller.get().setContentView(surface)
            val ring = RingingAlarmTracker.startRing(context, 7)
            repeat(minutes / 5 - 1) { RingingAlarmTracker.adjustSnooze(context, ring, 1) }
            val binding = SnoozeControlsBinding(surface, ring)
            repeat(4) {
                ShadowLooper.idleMainLooper(); surface.forceLayout()
                surface.measure(View.MeasureSpec.makeMeasureSpec((w*d).roundToInt(), View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec((h*d).roundToInt(), View.MeasureSpec.EXACTLY))
                surface.layout(0,0,surface.measuredWidth,surface.measuredHeight)
            }
            for (id in listOf(R.id.snoozeDecreaseButton,R.id.snoozeButton,R.id.snoozeIncreaseButton,R.id.dismissButton)) {
                val b = surface.findViewById<Button>(id)
                assertTrue("target $tag/$minutes/$scale/$w", b.width >= 48*d-1 && b.height >= 48*d-1)
                assertTrue("text $tag/$minutes/$scale/$w", b.paint.measureText(b.text.toString()) <= b.width-b.paddingLeft-b.paddingRight+1)
                assertFalse(b.contentDescription.isNullOrEmpty())
            }
            assertEquals("+${minutes}m", surface.findViewById<Button>(R.id.snoozeButton).text.toString())
            binding.close(); RingingAlarmTracker.endIfCurrent(context, ring.alarmId, ring.round)
        }
        controller.pause().stop().destroy()
    }

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
                if (root.getChildAt(0).visibility == View.VISIBLE) assertTrue("clock laid out $w/$h/$scale", root.getChildAt(0).width >= 64 * density - 1)
                if (root.getChildAt(0).visibility == View.VISIBLE) assertFalse("clock overlaps actions $w/$h/$scale", android.graphics.Rect.intersects(
                    android.graphics.Rect(root.getChildAt(0).left, root.getChildAt(0).top, root.getChildAt(0).right, root.getChildAt(0).bottom),
                    android.graphics.Rect(actions.left, actions.top, actions.right, actions.bottom)))
                assertTrue("actions bottom $w/$h/$scale", actions.bottom <= height)
                assertTrue("actions right $w/$h/$scale", actions.right <= width)
                for (id in listOf(R.id.snoozeDecreaseButton, R.id.snoozeButton, R.id.snoozeIncreaseButton, R.id.dismissButton)) {
                    val button = surface.findViewById<Button>(id)
                    assertTrue("touch width $w/$h/$scale: ${button.width / density}", button.width / density >= 47.5f)
                    assertTrue("touch height $w/$h/$scale", button.height / density >= 47.5f)
                    val bounds = android.graphics.Rect().also { button.getDrawingRect(it); surface.offsetDescendantRectToMyCoords(button, it) }
                    assertTrue(bounds.top >= 0 && bounds.left >= 0 && bounds.bottom <= height && bounds.right <= width)
                    button.performClick()
                }
                assertEquals(1, dismissals)
                assertEquals(1, snoozes)
            }
        }
        controller.pause().stop().destroy()
    }
}
