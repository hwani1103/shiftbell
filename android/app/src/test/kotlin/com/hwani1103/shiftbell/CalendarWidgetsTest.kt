package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CalendarWidgetsTest {
    private val regions = listOf("ko-KR", "en-US", "en-GB", "en-ZA", "en-AE", "en-PH", "pt-BR", "de-DE", "hi-IN")
    private fun context(tag: String, scale: Float = 1f): Context {
        val app = ApplicationProvider.getApplicationContext<Context>()
        return app.createConfigurationContext(Configuration(app.resources.configuration).apply {
            setLocale(Locale.forLanguageTag(tag)); fontScale = scale
        })
    }
    private fun now(zone: String = "Asia/Seoul", hour: Int = 12): Calendar = Calendar.getInstance(TimeZone.getTimeZone(zone)).apply {
        clear(); set(2026, Calendar.OCTOBER, 9, hour, 0)
    }
    private fun schedule(label: String) = CalendarWidgetScheduleResolver.ResolvedSchedule(true,
        listOf(label), 0, now().timeInMillis, emptyMap(), mapOf(label to 0xFF4771D1.toInt()))
    private fun bounds(root: ViewGroup, view: View) = Rect().also {
        view.getDrawingRect(it); root.offsetDescendantRectToMyCoords(view, it)
    }
    private fun layout(root: View, width: Int, height: Int, density: Float) {
        repeat(2) {
            root.measure(View.MeasureSpec.makeMeasureSpec((width*density).toInt(), View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec((height*density).toInt(), View.MeasureSpec.EXACTLY))
            root.layout(0, 0, root.measuredWidth, root.measuredHeight)
        }
    }

    @Test fun allRegionsHaveCorrectWindowAndNoExtraWeeksAtLargeSizes() {
        for (tag in regions) for (single in listOf(false, true)) {
            val ctx = context(tag)
            val start = CalendarWidgetProvider.windowStart(now(), ReleaseLocalePolicy.firstDayOfWeek(ctx), single)
            assertEquals(if (tag in listOf("en-GB", "en-AE", "de-DE")) Calendar.MONDAY else Calendar.SUNDAY,
                start.get(Calendar.DAY_OF_WEEK))
            assertEquals(if (single) if (start.get(Calendar.DAY_OF_WEEK) == Calendar.MONDAY) 5 else 4
                else if (start.get(Calendar.DAY_OF_WEEK) == Calendar.MONDAY) 28 else 27, start.get(Calendar.DAY_OF_MONTH))
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, single, now(), schedule("D"), emptyMap()).apply(ctx, FrameLayout(ctx))
            assertNull(root.findViewById<View>(if (single) R.id.num_1_0 else ctx.resources.getIdentifier("num_3_0", "id", ctx.packageName)))
            if (single) {
                assertNull(root.findViewById<View>(R.id.widget_date_header))
                assertEquals(ctx.resources.getStringArray(R.array.widget_weekday_labels)[start.get(Calendar.DAY_OF_WEEK)-1],
                    root.findViewById<TextView>(R.id.hdr_0).text.toString())
            } else assertFalse(root.findViewById<TextView>(R.id.widget_date_header).text.isNullOrEmpty())
        }
    }

    @Test fun dayNightUsesLocalHourAcrossZonesAndDstBoundaries() {
        for (zone in listOf("Asia/Seoul", "America/New_York", "America/Los_Angeles", "Europe/London",
            "Africa/Johannesburg", "Asia/Dubai", "Asia/Manila", "America/Sao_Paulo", "Europe/Berlin", "Asia/Kolkata")) {
            assertFalse(CalendarWidgetProvider.isDaytime(now(zone,5)))
            assertTrue(CalendarWidgetProvider.isDaytime(now(zone,6)))
            assertTrue(CalendarWidgetProvider.isDaytime(now(zone,17)))
            assertFalse(CalendarWidgetProvider.isDaytime(now(zone,18)))
            val boundary = now(zone).apply { set(2026, Calendar.NOVEMBER, 1, 23, 59) }
            val start = CalendarWidgetProvider.windowStart(boundary, Calendar.SUNDAY, true)
            assertEquals("2026-11-01", CalendarWidgetProvider.dateKeyFor(start))
        }
    }

    @Test fun fullShiftNamesAndThreeNotesFitWithEqualGuttersInEveryLanguage() {
        for (tag in regions) for (scale in listOf(1f, 2f)) for (single in listOf(false,true))
            for (width in listOf(250, 320, 400, 700)) {
            val ctx = context(tag, scale)
            val density = ctx.resources.displayMetrics.density
            val label = when (tag) {
                "ko-KR" -> "아주아주긴특수근무이름심야지원"
                "de-DE" -> "BereitschaftsdienstNachtschicht"
                "hi-IN" -> "बहुत लंबी रात की विशेष सहायता शिफ्ट"
                else -> "Extraordinarily long overnight support shift"
            }
            val start = CalendarWidgetProvider.windowStart(now(), ReleaseLocalePolicy.firstDayOfWeek(ctx), single)
            val notes = (0..20).associate { i -> CalendarWidgetProvider.dateKeyFor((start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, i) }) to
                listOf("Memo one", "Memo two", "Memo three").take(i % 4) }
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, single, now(), schedule(label), notes, width.toFloat()).apply(ctx, FrameLayout(ctx)) as ViewGroup
            layout(root, width, if(single) 102 else 262, density)
            var previous: Rect? = null
            for (c in 0..6) {
                fun id(prefix: String) = ctx.resources.getIdentifier(prefix + "_0_" + c, "id", ctx.packageName)
                val shift = root.findViewById<TextView>(id("pill"))
                assertEquals(label, shift.text.toString())
                assertNull(shift.ellipsize)
                assertTrue("full label fits $tag/$width: measured=${shift.paint.measureText(label)} width=${shift.width} size=${shift.textSize}", shift.paint.measureText(label) <= shift.width - shift.paddingLeft - shift.paddingRight + 1)
                val rect = bounds(root, shift)
                previous?.let { assertEquals("fixed gutter", 2*density, (rect.left-it.right).toFloat(), 1.1f) }
                previous = rect
                val date = bounds(root, root.findViewById(id("num")))
                assertTrue("date above shift $tag/$width/$c", date.bottom <= rect.top)
                val count = c % 4
                if (count > 0) {
                    val memoText = root.findViewById<TextView>(id("memo1"))
                    assertEquals("Memo one", memoText.text.toString())
                    assertTrue("memo line visible $tag/$width/$scale: height=" + memoText.height + " layout=" + memoText.layout.height + " baseline=" + memoText.baseline + " pads=" + memoText.compoundPaddingTop + "," + memoText.compoundPaddingBottom,
                        memoText.layout.height <= memoText.height - memoText.compoundPaddingTop - memoText.compoundPaddingBottom)
                    val memo = bounds(root, memoText)
                    assertTrue("date and memo do not overlap $tag/$width/$c: $date $memo", date.bottom <= memo.top)
                    val last = bounds(root, root.findViewById(id("memo"+count)))
                    assertTrue(last.bottom <= root.height - root.paddingBottom)
                }
            }
            if (scale == 1f && width == 320 && tag in listOf("ko-KR", "en-US", "de-DE", "hi-IN")) {
                val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
                root.draw(Canvas(bitmap))
                val noteBounds = bounds(root, root.findViewById(R.id.memo1_0_1))
                var ink = 0
                for (y in noteBounds.top until noteBounds.bottom) for (x in noteBounds.left until noteBounds.right) {
                    if (android.graphics.Color.red(bitmap.getPixel(x,y)) < 150) ink++
                }
                assertTrue("memo glyphs actually painted $tag/$single", ink > 0)
                val file = File("../../artifacts/calendar_widgets_2026_10_09/" + tag + (if(single) "-week" else "-three") + ".png")
                file.parentFile?.mkdirs(); file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
        val ctx = context("en-US")
        for (label in listOf("D", "X".repeat(1000))) {
            val size = CalendarWidgetProvider.fittedShiftSize(label, 250f, 1f)
            assertTrue(size > 0f && size <= 10f)
        }
    }

    @Test fun nullScheduleShowsSetupAndRefreshingUsesLatestScheduleAndMemos() {
        val ctx = context("ko-KR")
        val empty = CalendarWidgetProvider.buildRemoteViews(ctx, true, now(), null).apply(ctx, FrameLayout(ctx))
        assertEquals(View.VISIBLE, empty.findViewById<View>(R.id.empty_message).visibility)
        val first = CalendarWidgetProvider.buildRemoteViews(ctx, true, now(), schedule("Before"), emptyMap()).apply(ctx, FrameLayout(ctx))
        val revised = CalendarWidgetProvider.buildRemoteViews(ctx, true, now(), schedule("After"), emptyMap()).apply(ctx, FrameLayout(ctx))
        assertEquals("Before", first.findViewById<TextView>(R.id.pill_0_0).text.toString())
        assertEquals("After", revised.findViewById<TextView>(R.id.pill_0_0).text.toString())
    }
    @Test fun representativePreviewsFillAllocatedHosts() {
        for (tag in listOf("ko-KR", "en-US", "de-DE", "pt-BR", "hi-IN"))
            for (single in listOf(false,true)) for (hour in listOf(12,22)) {
            val base = context(tag)
            val ctx = base.createConfigurationContext(Configuration(base.resources.configuration).apply { densityDpi = 320 })
            val density = ctx.resources.displayMetrics.density
            val instant = now(hour = hour)
            val names = listOf(ctx.getString(R.string.widget_preview_day), ctx.getString(R.string.widget_preview_night), ctx.getString(R.string.widget_preview_off))
            val data = CalendarWidgetScheduleResolver.ResolvedSchedule(true, names, 0, now().timeInMillis,
                emptyMap(), names.zip(listOf(0xFF4771D1.toInt(), 0xFF6B6524.toInt(), 0xFFEF5350.toInt())).toMap())
            val start = CalendarWidgetProvider.windowStart(instant, ReleaseLocalePolicy.firstDayOfWeek(ctx), single)
            val notes = (0..20).associate { i -> CalendarWidgetProvider.dateKeyFor((start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH,i) }) to
                (if (tag == "ko-KR") listOf("약속", "운동", "장보기") else listOf("Meet", "Gym", "Shop")).take(i%4) }
            val root = CalendarWidgetProvider.buildRemoteViews(ctx, single, instant, data, notes, 320f).apply(ctx, FrameLayout(ctx)) as ViewGroup
            layout(root,320,600,density)
            assertEquals(600*density, root.findViewById<View>(R.id.widget_panel).height.toFloat(), 1f)
            layout(root,320,if(single) 102 else 262,density)
            val bitmap = Bitmap.createBitmap(root.width,root.height,Bitmap.Config.ARGB_8888)
            root.draw(Canvas(bitmap))
            val file = File("../../artifacts/calendar_widgets_2026_10_09/preview-" + tag + (if(single) "-week" else "-three") + "-" + hour + ".png")
            file.parentFile?.mkdirs(); file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
        }
    }

}
