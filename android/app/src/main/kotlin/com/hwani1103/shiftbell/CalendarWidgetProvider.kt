package com.hwani1103.shiftbell

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.util.SizeF
import android.util.TypedValue
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.floor
import kotlin.math.roundToInt

/** Both providers share the existing immediate-save, guard heartbeat and 30 minute updates.
 * Read the current DB on every update; never cache schedules or mutate alarm state.
 * The original component stays stable so already pinned three-week widgets upgrade in place.
 */
open class CalendarWidgetProvider : AppWidgetProvider() {
    protected open val singleWeek = false

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateAll(context, manager, ids, singleWeek)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        appWidgetId: Int, newOptions: Bundle) {
        // Weighted columns and measured text sizes use the actual host dimensions,
        // including fold/unfold. Height can never change the number of weeks.
        updateAll(context, manager, intArrayOf(appWidgetId), singleWeek)
    }

    companion object {
        private const val TAG = "CalendarWidgetProvider"
        internal fun windowStart(now: Calendar, firstWeekday: Int, singleWeek: Boolean): Calendar =
            (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                add(Calendar.DAY_OF_MONTH,
                    -((get(Calendar.DAY_OF_WEEK) - firstWeekday + 7) % 7) - if (singleWeek) 0 else 7)
            }

        // Time-of-day, not weather or astronomical sunrise. Device zone handles DST,
        // travel and countries with several time zones without location permission.
        internal fun isDaytime(now: Calendar) = now.get(Calendar.HOUR_OF_DAY) in 6..17
        internal fun dateKeyFor(day: Calendar): String = String.format(Locale.US,
            "%04d-%02d-%02d", day.get(Calendar.YEAR), day.get(Calendar.MONTH) + 1,
            day.get(Calendar.DAY_OF_MONTH))

        fun requestUpdate(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                for ((provider, single) in listOf(CalendarWidgetProvider::class.java to false,
                    WeekCalendarWidgetProvider::class.java to true)) {
                    updateAll(context, manager,
                        manager.getAppWidgetIds(ComponentName(context, provider)), single)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Widget refresh failed", e)
            }
        }

        private fun updateAll(context: Context, manager: AppWidgetManager, ids: IntArray, single: Boolean) {
            for (id in ids) try {
                val options = manager.getAppWidgetOptions(id)
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250).takeIf { it > 0 } ?: 250
                val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth).coerceAtLeast(minWidth)
                val sizes = if (Build.VERSION.SDK_INT >= 31)
                    options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES).orEmpty()
                        .filter { it.width > 0 && it.height > 0 }.distinct().take(16) else emptyList()
                val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, if (single) 102 else 228)
                val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight)
                val bitmaps = mutableMapOf<Int, Bitmap>()
                val views = if (Build.VERSION.SDK_INT >= 31 && sizes.isNotEmpty()) {
                    RemoteViews(sizes.associateWith { buildRemoteViews(context, single, widthDp = it.width, heightDp = it.height, bitmapCache = bitmaps) })
                } else RemoteViews(buildRemoteViews(context, single, widthDp = maxWidth.toFloat(), heightDp = minHeight.toFloat(), bitmapCache = bitmaps),
                    buildRemoteViews(context, single, widthDp = minWidth.toFloat(), heightDp = maxHeight.toFloat(), bitmapCache = bitmaps))
                manager.updateAppWidget(id, views)
            } catch (e: Exception) {
                // Rendering must never take down the alarm process.
                Log.e(TAG, "Widget render failed: " + id, e)
            }
        }

        internal fun buildRemoteViews(context: Context, single: Boolean,
            now: Calendar = Calendar.getInstance(),
            schedule: CalendarWidgetScheduleResolver.ResolvedSchedule? = CalendarWidgetScheduleResolver.readSchedule(context),
            suppliedMemos: Map<String, List<String>>? = null, widthDp: Float = 250f,
            bitmapCache: MutableMap<Int, Bitmap> = mutableMapOf(),
            heightDp: Float = if (single) 102f else 228f): RemoteViews {
            val views = RemoteViews(context.packageName,
                if (single) R.layout.calendar_widget_week else R.layout.calendar_widget)
            val day = isDaytime(now)
            views.setInt(R.id.widget_panel, "setBackgroundResource",
                if (day) R.drawable.calendar_widget_day else R.drawable.calendar_widget_night)
            views.setImageViewResource(R.id.widget_garden,
                if (day) R.drawable.widget_garden_day else R.drawable.widget_garden_night)
            val openApp = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("openTab", 2)
            }
            views.setOnClickPendingIntent(R.id.widget_panel, PendingIntent.getActivity(context, 0,
                openApp, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            if (!single) {
                val locale = ReleaseLocalePolicy.locale(context)
                val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "yMMMM")
                val formatter = SimpleDateFormat(pattern, locale).apply { timeZone = now.timeZone }
                views.setTextViewText(R.id.widget_date_header, formatter.format(now.time))
                views.setTextColor(R.id.widget_date_header, Color.parseColor(if (day) "#294E48" else "#30365D"))
                views.setImageViewResource(R.id.widget_day_period,
                    if (day) R.drawable.widget_landscape_day else R.drawable.widget_landscape_night)
                views.setContentDescription(R.id.widget_day_period,
                    context.getString(if (day) R.string.widget_daytime else R.string.widget_nighttime))
            }
            views.setViewVisibility(R.id.empty_message, if (schedule == null) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_content, if (schedule == null) View.GONE else View.VISIBLE)
            if (schedule == null) return views

            val first = ReleaseLocalePolicy.firstDayOfWeek(context)
            val weekdays = context.resources.getStringArray(R.array.widget_weekday_labels)
            for (c in 0..6) {
                views.setTextViewText(headerIds[c], weekdays[(c + first - Calendar.SUNDAY) % 7])
                views.setTextColor(headerIds[c], Color.parseColor(if (day) "#355B54" else "#444C77"))
            }
            val start = windowStart(now, first, single)
            val rowCount = if (single) 1 else 3
            val end = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, rowCount * 7 - 1) }
            val memos = suppliedMemos ?: CalendarWidgetScheduleResolver.readMemos(context, dateKeyFor(start), dateKeyFor(end))
            val overrides = CalendarWidgetHolidays.overrides(context)
            val density = context.resources.displayMetrics.density
            // Allocate the available row height to legible notes and their spacing.
            // A one-week widget keeps one home-screen row and only resizes horizontally.
            val rowHeight = ((heightDp - if (single) 24f else 61f) / rowCount - 2f).coerceAtLeast(36f)
            val dateHeight = minOf(if (single) 14f else 16f, rowHeight * .24f)
            val memoArea = (rowHeight - dateHeight - 18f).coerceAtLeast(12f)
            val memoGap = minOf(3f, memoArea * .07f)
            val memoHeight = minOf(16f, memoArea / 3f)
            val memoFont = minOf(9.5f, (memoHeight - memoGap) / 1.18f).coerceAtLeast(3f)
            for (r in 0 until rowCount) for (c in 0..6) {
                val index = r * 7 + c
                val cal = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, index) }
                val today = dateKeyFor(cal) == dateKeyFor(now)
                val red = ReleaseLocalePolicy.isCalendarRedDay(context, cal, overrides)
                val shift = CalendarWidgetScheduleResolver.shiftForDate(schedule, cal)
                val hasShift = shift.isNotEmpty() && shift != "미설정"
                val label = if (!hasShift) "" else if (shift == "없음") context.getString(R.string.widget_no_shift) else shift
                val color = if (shift == "없음") Color.rgb(234, 237, 239) else schedule.shiftColors[shift] ?: Color.TRANSPARENT
                val visibleLabel = label.replace(Regex("\\s+"), " ")
                views.setTextViewText(pillIds[index], visibleLabel)
                views.setTextViewTextSize(pillIds[index], TypedValue.COMPLEX_UNIT_PX,
                    fittedShiftSize(visibleLabel, widthDp, density, ReleaseLocalePolicy.locale(context)))
                views.setContentDescription(pillIds[index], label)
                if (hasShift) {
                    views.setImageViewBitmap(pillBgIds[index], bitmapCache.getOrPut(color) { roundedPillBitmap(color) })
                    views.setTextColor(pillIds[index], pillTextColorFor(color))
                } else views.setImageViewResource(pillBgIds[index], 0)
                views.setTextViewText(numIds[index], cal.get(Calendar.DAY_OF_MONTH).toString())
                views.setInt(numIds[index], "setHeight", (dateHeight * density).toInt())
                views.setTextViewTextSize(numIds[index], TypedValue.COMPLEX_UNIT_DIP, dateHeight - 2f)
                views.setContentDescription(numIds[index], SimpleDateFormat("EEEE, MMMM d, yyyy",
                    ReleaseLocalePolicy.locale(context)).apply { timeZone = cal.timeZone }.format(cal.time))
                views.setInt(numIds[index], "setBackgroundResource", if (today)
                    if (red) R.drawable.widget_today_holiday_light else R.drawable.widget_today_normal_light else 0)
                val outside = cal.get(Calendar.YEAR) != now.get(Calendar.YEAR) ||
                    cal.get(Calendar.MONTH) != now.get(Calendar.MONTH)
                val numberColor = if (red) Color.rgb(196, 48, 56)
                    else if (today) Color.WHITE else Color.parseColor(if (day) "#263F3E" else "#343D61")
                views.setTextColor(numIds[index], if (outside)
                    Color.argb(112, Color.red(numberColor), Color.green(numberColor), Color.blue(numberColor)) else numberColor)
                val notes = memos[dateKeyFor(cal)].orEmpty().take(3)
                for (slot in 0..2) {
                    val id = memoIds[slot][index]
                    views.setInt(id, "setHeight", (memoHeight * density).toInt())
                    views.setViewPadding(id, 0, (memoGap * density).roundToInt(), 0, 0)
                    views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_DIP, memoFont)
                    views.setViewVisibility(id, if (slot < notes.size) View.VISIBLE else View.GONE)
                    views.setTextViewText(id, completeMemoPrefix(notes.getOrElse(slot) { "" }, widthDp, density, ReleaseLocalePolicy.locale(context), memoFont))
                    views.setTextColor(id, Color.parseColor(if (day) "#48615A" else "#495375"))
                    views.setContentDescription(id, notes.getOrElse(slot) { "" })
                }
                // Dates and shifts share stable baselines; notes follow the shift.
                views.setViewPadding(numWrapIds[index], 0, 0, 0, 0)
            }
            return views
        }

        // Use the full cell width with equal gutters for EVERY shift. No ellipsis,
        // character-count heuristic, fixed minimum size or altered column widths.
        internal fun fittedShiftSize(label: String, widthDp: Float, density: Float, locale: Locale = Locale.getDefault()): Float {
            val maximum = 12f * density
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
                textLocale = locale
                textSize = maximum
                typeface = Typeface.DEFAULT_BOLD
            }
            val cellPixels = floor((floor(widthDp * density) - 2 * (7f * density).roundToInt()) / 7f)
            val available = (cellPixels - 4 * density.roundToInt()).coerceAtLeast(.1f)
            // Re-measure at the chosen size: fallback glyph hinting (notably Hindi)
            // is not perfectly linear when scaling from a larger size.
            repeat(8) {
                val measured = paint.measureText(label)
                if (measured <= available || measured == 0f) return paint.textSize
                paint.textSize *= available / measured * .97f
            }
            return paint.textSize
        }

        // Keep only complete grapheme clusters which fit. Never add an ellipsis or
        // leave half a final glyph; the accessibility description keeps the full note.
        internal fun completeMemoPrefix(value: String, widthDp: Float, density: Float, locale: Locale, fontDp: Float = 8f): String {
            val text = value.replace(Regex("\\s+"), " ")
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
                textSize = fontDp * density; textLocale = locale; typeface = Typeface.DEFAULT
            }
            val cell = floor((floor(widthDp * density) - 2 * (7f * density).roundToInt()) / 7f)
            val available = (cell - 2 * density.roundToInt() - density).coerceAtLeast(0f)
            val count = paint.breakText(text, true, available, null)
            if (count == text.length) return text
            val boundaries = android.icu.text.BreakIterator.getCharacterInstance(locale).apply { setText(text) }
            var end = if (boundaries.isBoundary(count)) count else boundaries.preceding(count)
            while (end > 0 && paint.measureText(text.substring(0, end)) > available) end = boundaries.preceding(end)
            return text.substring(0, end.coerceAtLeast(0))
        }

        private fun roundedPillBitmap(color: Int): Bitmap =
            Bitmap.createBitmap(120, 48, Bitmap.Config.ARGB_8888).also {
                Canvas(it).drawRoundRect(RectF(0f, 0f, 120f, 48f), 10f, 10f,
                    Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
            }

        private fun pillTextColorFor(color: Int): Int {
            if (Color.alpha(color) < 128) return Color.rgb(38, 44, 49)
            val luminance = Color.red(color) * .299 + Color.green(color) * .587 + Color.blue(color) * .114
            return if (luminance > 200) Color.rgb(33, 33, 33) else Color.WHITE
        }

        private val headerIds = intArrayOf(R.id.hdr_0, R.id.hdr_1, R.id.hdr_2, R.id.hdr_3, R.id.hdr_4, R.id.hdr_5, R.id.hdr_6)
        private val pillIds = intArrayOf(
            R.id.pill_0_0, R.id.pill_0_1, R.id.pill_0_2, R.id.pill_0_3, R.id.pill_0_4, R.id.pill_0_5, R.id.pill_0_6,
            R.id.pill_1_0, R.id.pill_1_1, R.id.pill_1_2, R.id.pill_1_3, R.id.pill_1_4, R.id.pill_1_5, R.id.pill_1_6,
            R.id.pill_2_0, R.id.pill_2_1, R.id.pill_2_2, R.id.pill_2_3, R.id.pill_2_4, R.id.pill_2_5, R.id.pill_2_6
        )
        private val pillBgIds = intArrayOf(
            R.id.pillbg_0_0, R.id.pillbg_0_1, R.id.pillbg_0_2, R.id.pillbg_0_3, R.id.pillbg_0_4, R.id.pillbg_0_5, R.id.pillbg_0_6,
            R.id.pillbg_1_0, R.id.pillbg_1_1, R.id.pillbg_1_2, R.id.pillbg_1_3, R.id.pillbg_1_4, R.id.pillbg_1_5, R.id.pillbg_1_6,
            R.id.pillbg_2_0, R.id.pillbg_2_1, R.id.pillbg_2_2, R.id.pillbg_2_3, R.id.pillbg_2_4, R.id.pillbg_2_5, R.id.pillbg_2_6
        )
        private val numIds = intArrayOf(
            R.id.num_0_0, R.id.num_0_1, R.id.num_0_2, R.id.num_0_3, R.id.num_0_4, R.id.num_0_5, R.id.num_0_6,
            R.id.num_1_0, R.id.num_1_1, R.id.num_1_2, R.id.num_1_3, R.id.num_1_4, R.id.num_1_5, R.id.num_1_6,
            R.id.num_2_0, R.id.num_2_1, R.id.num_2_2, R.id.num_2_3, R.id.num_2_4, R.id.num_2_5, R.id.num_2_6
        )
        private val numWrapIds = intArrayOf(
            R.id.numwrap_0_0, R.id.numwrap_0_1, R.id.numwrap_0_2, R.id.numwrap_0_3, R.id.numwrap_0_4, R.id.numwrap_0_5, R.id.numwrap_0_6,
            R.id.numwrap_1_0, R.id.numwrap_1_1, R.id.numwrap_1_2, R.id.numwrap_1_3, R.id.numwrap_1_4, R.id.numwrap_1_5, R.id.numwrap_1_6,
            R.id.numwrap_2_0, R.id.numwrap_2_1, R.id.numwrap_2_2, R.id.numwrap_2_3, R.id.numwrap_2_4, R.id.numwrap_2_5, R.id.numwrap_2_6
        )
        private val memoIds = arrayOf(
            intArrayOf(R.id.memo1_0_0, R.id.memo1_0_1, R.id.memo1_0_2, R.id.memo1_0_3, R.id.memo1_0_4, R.id.memo1_0_5, R.id.memo1_0_6, R.id.memo1_1_0, R.id.memo1_1_1, R.id.memo1_1_2, R.id.memo1_1_3, R.id.memo1_1_4, R.id.memo1_1_5, R.id.memo1_1_6, R.id.memo1_2_0, R.id.memo1_2_1, R.id.memo1_2_2, R.id.memo1_2_3, R.id.memo1_2_4, R.id.memo1_2_5, R.id.memo1_2_6),
            intArrayOf(R.id.memo2_0_0, R.id.memo2_0_1, R.id.memo2_0_2, R.id.memo2_0_3, R.id.memo2_0_4, R.id.memo2_0_5, R.id.memo2_0_6, R.id.memo2_1_0, R.id.memo2_1_1, R.id.memo2_1_2, R.id.memo2_1_3, R.id.memo2_1_4, R.id.memo2_1_5, R.id.memo2_1_6, R.id.memo2_2_0, R.id.memo2_2_1, R.id.memo2_2_2, R.id.memo2_2_3, R.id.memo2_2_4, R.id.memo2_2_5, R.id.memo2_2_6),
            intArrayOf(R.id.memo3_0_0, R.id.memo3_0_1, R.id.memo3_0_2, R.id.memo3_0_3, R.id.memo3_0_4, R.id.memo3_0_5, R.id.memo3_0_6, R.id.memo3_1_0, R.id.memo3_1_1, R.id.memo3_1_2, R.id.memo3_1_3, R.id.memo3_1_4, R.id.memo3_1_5, R.id.memo3_1_6, R.id.memo3_2_0, R.id.memo3_2_1, R.id.memo3_2_2, R.id.memo3_2_3, R.id.memo3_2_4, R.id.memo3_2_5, R.id.memo3_2_6)
        )
    }
}

class WeekCalendarWidgetProvider : CalendarWidgetProvider() {
    override val singleWeek = true
}
