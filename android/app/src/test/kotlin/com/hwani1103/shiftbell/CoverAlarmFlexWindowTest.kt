package com.hwani1103.shiftbell

import android.content.Context
import android.app.Activity
import android.content.res.Configuration
import android.graphics.Insets
import android.graphics.Rect
import android.view.DisplayCutout
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Robolectric
import org.robolectric.shadows.ShadowLooper
import java.io.File
import kotlin.math.roundToInt

/** Spec-based virtual windows, not claims about Samsung firmware or measured default density. */
@RunWith(RobolectricTestRunner::class)
class CoverAlarmFlexWindowTest {
    @Test fun flexWindowControlsAvoidCutoutAndHiddenBarsAcrossZoomAndFontSizes() {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val report = StringBuilder("width,height,dpi,font,insets,clock,buttons,later,stop,clockTextPx,buttonTextPx\n")
        for (dpi in listOf(240, 280, 320, 360, 400, 440)) {
            for (font in listOf(.85f, 1f, 1.3f, 2f)) {
                for ((width, height) in listOf(720 to 748, 748 to 720, 720 to 648)) {
                    for (profile in 0..3) {
                        val context = base.createConfigurationContext(Configuration(base.resources.configuration).apply {
                            densityDpi = dpi; fontScale = font
                        })
                        val density = context.resources.displayMetrics.density
                        val safe = when (profile) {
                            1 -> Rect(0, 40, 0, 48) // status/navigation
                            2 -> Rect(0, 0, 0, 96) // conservative camera strip scenario
                            3 -> Rect(24, 40, 24, 96) // combined, with side reservations
                            else -> Rect()
                        }
                        var stops = 0; var snoozes = 0
                        val surface = CoverAlarmLayout.create(context, "23:59", { stops++ }, { snoozes++ }) as FrameLayout
                        val content = surface.getChildAt(1) as LinearLayout
                        // Geometry test: omit the decorative, infinitely animated layer so
                        // Robolectric can settle the Activity traversal deterministically.
                        surface.removeViewAt(0)
                        controller.get().setContentView(surface)
                        val builder = WindowInsets.Builder()
                        if (profile == 1 || profile == 3) {
                            builder.setInsetsIgnoringVisibility(WindowInsets.Type.systemBars(), Insets.of(safe.left, 40, safe.right, 48))
                            builder.setInsets(WindowInsets.Type.systemBars(), Insets.NONE)
                        }
                        if (profile >= 2) builder.setDisplayCutout(DisplayCutout(Rect(0, 0, 0, 96), listOf(Rect(width / 2, height - 96, width, height))))
                        content.dispatchApplyWindowInsets(builder.build())
                        repeat(4) {
                            ShadowLooper.idleMainLooper()
                            surface.forceLayout()
                            content.forceLayout()
                            surface.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                            surface.layout(0, 0, width, height)
                        }
                        val tag = "$width/$height dpi=$dpi font=$font profile=$profile"
                        val clock = content.getChildAt(0) as TextView
                        val actions = content.getChildAt(1) as LinearLayout
                        fun bounds(v: View): Rect = Rect().also { v.getDrawingRect(it); surface.offsetDescendantRectToMyCoords(v, it) }
                        val clockRect = bounds(clock)
                        val actionRect = bounds(actions)
                        assertTrue("clock must be laid out $tag $clockRect", clock.width >= 64 * density - 1)
                        assertFalse("overlap $tag", Rect.intersects(clockRect, actionRect))
                        val padding = (16 * density).roundToInt()
                        for (v in listOf(clock, actions)) {
                            val r = bounds(v)
                            assertTrue("safe edges $tag $r", r.left >= safe.left + padding && r.top >= safe.top + padding && r.right <= width - safe.right - padding && r.bottom <= height - safe.bottom - padding)
                        }
                        for (i in 0..1) {
                            val b = actions.getChildAt(i) as Button
                            assertTrue("touch area $tag", b.width >= 48 * density - 1 && b.height >= 48 * density - 1)
                            assertTrue("label width $tag", b.paint.measureText(b.text.toString()) <= b.width - b.paddingLeft - b.paddingRight + 1)
                            assertTrue("label height $tag", b.paint.fontMetrics.descent - b.paint.fontMetrics.ascent <= b.height - b.paddingTop - b.paddingBottom + 1)
                            b.performClick()
                        }
                        assertEquals(1, stops); assertEquals(1, snoozes)
                        assertTrue("clock fits $tag", clock.paint.measureText(clock.text.toString()) <= clock.width)
                        report.append("$width,$height,$dpi,$font,$profile,${clockRect.flattenToString()},${actionRect.flattenToString()},${bounds(actions.getChildAt(0)).flattenToString()},${bounds(actions.getChildAt(1)).flattenToString()},${clock.textSize},${(actions.getChildAt(1) as Button).textSize}\n")
                    }
                }
            }
        }
        File("../../build/cover_virtual").apply { mkdirs() }.resolve("flip56-layout-matrix.csv").writeText(report.toString())
        controller.pause().stop().destroy()
    }
}
