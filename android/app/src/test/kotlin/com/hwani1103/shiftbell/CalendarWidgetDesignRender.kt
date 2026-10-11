package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.util.Calendar
import java.util.Locale

/** Rendering harness only. No functional assertions or regression suites. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CalendarWidgetDesignRender {
    @Test fun renderOnly() {
        val app = ApplicationProvider.getApplicationContext<Context>()
        for (tag in listOf("ko-KR", "de-DE", "hi-IN")) for (single in listOf(false,true))
            for (hour in listOf(12,22)) for (height in if(single) listOf(102) else listOf(200,228,300)) {
            val ctx = app.createConfigurationContext(Configuration(app.resources.configuration).apply {
                setLocale(Locale.forLanguageTag(tag)); densityDpi = 320
            })
            val now = Calendar.getInstance().apply { clear(); set(2026,9,9,hour,0) }
            val names = listOf(ctx.getString(R.string.widget_preview_day),ctx.getString(R.string.widget_preview_night),ctx.getString(R.string.widget_preview_off))
            val data = CalendarWidgetScheduleResolver.ResolvedSchedule(true,names,0,now.timeInMillis,emptyMap(),names.zip(listOf(0xFF4771D1.toInt(),0xFF6B6524.toInt(),0xFFEF5350.toInt())).toMap())
            val start = CalendarWidgetProvider.windowStart(now,ReleaseLocalePolicy.firstDayOfWeek(ctx),single)
            val sample = when(tag) { "ko-KR" -> listOf("약속시간변경", "운동", "장보기")
                "hi-IN" -> listOf("मुलाकात", "व्यायाम", "खरीदारी")
                else -> listOf("Besprechung", "Training", "Einkaufen") }
            val notes = (0..20).associate { i -> CalendarWidgetProvider.dateKeyFor((start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH,i) }) to sample.take(i%4) }
            val root = CalendarWidgetProvider.buildRemoteViews(ctx,single,now,data,notes,320f,heightDp=height.toFloat()).apply(ctx,FrameLayout(ctx))
            repeat(2) {
                root.measure(View.MeasureSpec.makeMeasureSpec(640,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height*2,View.MeasureSpec.EXACTLY))
                root.layout(0,0,640,height*2)
            }
            val bitmap = Bitmap.createBitmap(640,height*2,Bitmap.Config.ARGB_8888)
            root.draw(Canvas(bitmap))
            val file = File("../../artifacts/calendar_widget_design_v2/"+tag+(if(single) "-week" else "-three")+"-"+hour+"-"+height+".png")
            file.parentFile?.mkdirs(); file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
        }
    }
}
