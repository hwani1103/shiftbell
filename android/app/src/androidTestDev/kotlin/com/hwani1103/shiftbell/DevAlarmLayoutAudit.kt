package com.hwani1103.shiftbell

import android.app.Instrumentation
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.util.Locale

/** Real Android font/layout rendering without opening windows or starting audio.
 * Offscreen captures are deliberately distinguished from live-window tests.
 */
object DevAlarmLayoutAudit {
    fun run(test: Instrumentation): JSONObject {
        val app = test.targetContext
        check(app.packageName == "com.hwani1103.shiftbell.dev")
        val output = File(app.cacheDir, "alarm_locale_layout").apply { mkdirs() }
        var count = 0
        val issues = mutableListOf<String>()
        test.runOnMainSync {
            for (locale in listOf("de-DE", "pt-BR")) for (scale in listOf(1f, 1.3f)) {
                val config = Configuration(app.resources.configuration).apply {
                    setLocale(Locale.forLanguageTag(locale)); fontScale = scale
                }
                val context = android.view.ContextThemeWrapper(
                    app.createConfigurationContext(config), androidx.appcompat.R.style.Theme_AppCompat_Light_NoActionBar)
                val density = context.resources.displayMetrics.density
                for (widthDp in listOf(320, 411)) for (overlay in listOf(true, false)) {
                    val root = LayoutInflater.from(context).inflate(
                        if (overlay) R.layout.overlay_alarm else R.layout.activity_alarm, null)
                    root.findViewById<TextView>(R.id.timeText).text = "23:59"
                    root.findViewById<TextView>(R.id.shiftTypeText).text = "WWWWWWWWWWWWWWWW"
                    val width = (widthDp * density).toInt()
                    root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec((780 * density).toInt(),
                            if (overlay) View.MeasureSpec.AT_MOST else View.MeasureSpec.EXACTLY))
                    root.layout(0, 0, width, root.measuredHeight)
                    fun checkText(view: View) {
                        if (view is TextView && view.text.isNotEmpty()) {
                            val bounds = android.graphics.Rect(0, 0, view.width, view.height)
                            (root as ViewGroup).offsetDescendantRectToMyCoords(view, bounds)
                            if (!(bounds.left >= 0 && bounds.top >= 0 && bounds.right <= root.width &&
                                bounds.bottom <= root.height)) issues += "$locale $scale $widthDp text outside root: ${view.text}"
                            val layout = view.layout
                            check(layout != null)
                            if ((0 until layout.lineCount).any { layout.getEllipsisCount(it) != 0 })
                                issues += "$locale $scale $widthDp ellipsized: ${view.text}"
                            if (layout.height > view.height - view.compoundPaddingTop - view.compoundPaddingBottom)
                                issues += "$locale $scale $widthDp overlay=$overlay cropped text: ${view.text}"
                        }
                        if (view is ViewGroup) for (i in 0 until view.childCount) checkText(view.getChildAt(i))
                    }
                    checkText(root)
                    val bitmap = Bitmap.createBitmap(width, root.height, Bitmap.Config.ARGB_8888)
                    root.draw(Canvas(bitmap))
                    File(output, "${locale}_${scale}_${widthDp}_${if (overlay) "overlay" else "lock"}.png")
                        .outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    bitmap.recycle()
                    count++
                }
            }
        }
        return JSONObject().put("case", "offscreen_native_localized_layout")
            .put("renders", count).put("directory", output.path)
            .put("issues", org.json.JSONArray(issues)).put("pass", issues.isEmpty())
    }
}
