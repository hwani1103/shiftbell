package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration
import android.graphics.Rect
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import java.util.Locale
import kotlin.math.roundToInt

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SnoozeControlsLayoutTest {
    @Test fun allControlsFitPhoneCardAndRemoteViewsInFiveLanguages() {
        val app = ApplicationProvider.getApplicationContext<Context>()
        for (tag in listOf("ko", "en", "de", "pt-BR", "hi")) for (scale in listOf(1f, 1.3f, 2f))
            for (dark in listOf(false, true)) for (minutes in listOf(5,15,30)) {
            val c = app.createConfigurationContext(Configuration(app.resources.configuration).apply {
                setLocale(Locale.forLanguageTag(tag)); fontScale = scale
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
            })
            val d = c.resources.displayMetrics.density
            for (width in listOf(320, 360, 720)) {
                for (layout in listOf(R.layout.overlay_alarm, R.layout.activity_alarm)) {
                    val root = LayoutInflater.from(c).inflate(layout, null) as ViewGroup
                    root.removeViewAt(0) // Animated decoration only.
                    val ring = RingingAlarmTracker.startRing(c, 7)
                    repeat(minutes / 5 - 1) { RingingAlarmTracker.adjustSnooze(c, ring, 1) }
                    val binding = SnoozeControlsBinding(root, ring)
                    if (root is ConstraintLayout) {
                        AlarmResponsiveLayout.install(root)
                        androidx.core.view.ViewCompat.dispatchApplyWindowInsets(root,
                            androidx.core.view.WindowInsetsCompat.Builder().setInsets(
                                androidx.core.view.WindowInsetsCompat.Type.systemBars(),
                                androidx.core.graphics.Insets.of(0, (24*d).roundToInt(), 0, (48*d).roundToInt())).build())
                    }
                    val w = (width * d).roundToInt()
                    val h = (if (width == 720) 540 else 760) * d
                    repeat(3) {
                        root.forceLayout()
                        root.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(if (layout == R.layout.activity_alarm) h.roundToInt() else 0,
                                if (layout == R.layout.activity_alarm) View.MeasureSpec.EXACTLY else View.MeasureSpec.UNSPECIFIED))
                        root.layout(0, 0, w, root.measuredHeight)
                    }
                    val bounds = mutableListOf<Rect>()
                    for (id in listOf(R.id.snoozeDecreaseButton, R.id.snoozeButton, R.id.snoozeIncreaseButton, R.id.dismissButton)) {
                        val view = root.findViewById<View>(id)
                        val r = Rect().also { view.getDrawingRect(it); root.offsetDescendantRectToMyCoords(view,it) }
                        val message = "$tag/$scale/$dark/$minutes/$width/$layout/$id: $r root=${root.width}x${root.height}"
                        assertTrue(message, r.left >= root.paddingLeft && r.top >= root.paddingTop &&
                            r.right <= root.width-root.paddingRight && r.bottom <= root.height-root.paddingBottom)
                        assertTrue(message, view.width >= 48*d-1 && view.height >= 48*d-1)
                        assertFalse(message, view.contentDescription.isNullOrEmpty())
                        bounds.forEach { assertFalse(message, Rect.intersects(it,r)) }
                        bounds.add(r)
                    }
                    val text = root.findViewById<TextView>(R.id.snoozeValueText)
                    assertEquals(SnoozeText.compact(minutes), text.text.toString())
                    assertTrue("value fits $tag/$scale/$width", text.paint.measureText(text.text.toString()) <= text.width + 1)
                    assertEquals(SnoozeText.description(c, minutes), root.findViewById<View>(R.id.snoozeButton).contentDescription)
                    binding.close()
                    RingingAlarmTracker.endIfCurrent(c, ring.alarmId, ring.round)
                }
            }
            val ring = RingingAlarmTracker.startRing(c, 7)
            repeat(minutes/5-1) { RingingAlarmTracker.adjustSnooze(c, ring, 1) }
            NotificationHelper.postInitialRing(c, 7, ring.round, "Shift", 3)
            val notification = org.robolectric.Shadows.shadowOf(c.getSystemService(android.app.NotificationManager::class.java)).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
            val remote = notification.bigContentView.apply(c, FrameLayout(c))
            assertEquals(SnoozeText.selection(c, minutes), remote.findViewById<TextView>(R.id.snoozeValueText).text.toString())
            assertEquals(minutes > 5, remote.findViewById<View>(R.id.snoozeDecreaseButton).isEnabled)
            assertEquals(minutes < 30, remote.findViewById<View>(R.id.snoozeIncreaseButton).isEnabled)
            RingingAlarmTracker.endIfCurrent(c, ring.alarmId, ring.round)
        }
    }
}
