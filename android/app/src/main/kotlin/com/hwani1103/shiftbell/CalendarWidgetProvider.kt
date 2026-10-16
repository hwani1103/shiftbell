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
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
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
 * Refresh invalidates local month snapshots; navigation never mutates alarm state.
 * The original component stays stable so already pinned three-week widgets upgrade in place.
 */
open class CalendarWidgetProvider : AppWidgetProvider() {
    protected open val singleWeek = false

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // Provider update broadcasts can arrive at different times (or only for
        // the visible home page). Refresh every pinned calendar from one clock.
        requestUpdate(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        appWidgetId: Int, newOptions: Bundle) {
        // Weighted columns and measured text sizes use the actual host dimensions,
        // including fold/unfold. Compact modes always return to the current date.
        val height = newOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 228)
        if (!singleWeek && CalendarWidgetMonths.rows(height.toFloat()) < 6) {
            CalendarWidgetMonths.reset(context, appWidgetId)
        }
        requestUpdate(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) CalendarWidgetMonths.reset(context, id)
        super.onDeleted(context, appWidgetIds)
    }

    companion object {
        internal val renderLock = Any()
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

        fun requestUpdate(context: Context) = synchronized(renderLock) {
            CalendarWidgetMonthCache.invalidate()
            try {
                val manager = AppWidgetManager.getInstance(context)
                val now = Calendar.getInstance()
                for ((provider, single) in listOf(CalendarWidgetProvider::class.java to false,
                    WeekCalendarWidgetProvider::class.java to true)) {
                    updateAll(context, manager,
                        manager.getAppWidgetIds(ComponentName(context, provider)), single, now)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Widget refresh failed", e)
            }
        }

        private fun updateAll(context: Context, manager: AppWidgetManager, ids: IntArray, single: Boolean, now: Calendar) {
            for (id in ids) updateOne(context, manager, id, single, now)
        }

        internal fun updateOne(context: Context, manager: AppWidgetManager, id: Int, single: Boolean,
            now: Calendar = Calendar.getInstance(), previousMonth: Int? = null) {
            try {
                val options = manager.getAppWidgetOptions(id)
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250).takeIf { it > 0 } ?: 250
                val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth).coerceAtLeast(minWidth)
                val sizes = if (Build.VERSION.SDK_INT >= 31)
                    options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES).orEmpty()
                        .filter { it.width > 0 && it.height > 0 }.distinct().take(16) else emptyList()
                val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, if (single) 102 else 228).takeIf { it > 0 } ?: if (single) 102 else 228
                val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight).coerceAtLeast(minHeight)
                val selected = CalendarWidgetMonths.selected(context, id, now)
                val bitmaps = mutableMapOf<Int, Bitmap>()
                fun render(width: Float, height: Float): RemoteViews {
                    val month = CalendarWidgetMonths.month(now,
                        if (CalendarWidgetMonths.rows(height, single) == 6) selected else CalendarWidgetMonths.index(now))
                    val data = CalendarWidgetMonthCache.get(context, month)
                    return buildRemoteViews(context, single, now, data.schedule, data.memos,
                        width, bitmaps, height, month, previousMonth, id)
                }
                val views = if (Build.VERSION.SDK_INT >= 31 && sizes.isNotEmpty()) {
                    RemoteViews(sizes.associateWith { render(it.width, it.height) })
                } else RemoteViews(render(maxWidth.toFloat(), minHeight.toFloat()),
                    render(minWidth.toFloat(), maxHeight.toFloat()))
                manager.updateAppWidget(id, views)
                // Publish the already-cached page first, then prepare its new neighbours.
                if (!single && CalendarWidgetMonths.canNavigate(options)) {
                    CalendarWidgetMonthCache.get(context, CalendarWidgetMonths.month(now, selected), preload = true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Widget render failed: " + id, e)
            }
        }

        internal fun buildRemoteViews(context: Context, single: Boolean,
            now: Calendar = Calendar.getInstance(),
            schedule: CalendarWidgetScheduleResolver.ResolvedSchedule? = CalendarWidgetScheduleResolver.readSchedule(context),
            suppliedMemos: Map<String, List<String>>? = null, widthDp: Float = 250f,
            bitmapCache: MutableMap<Int, Bitmap> = mutableMapOf(),
            heightDp: Float = if (single) 102f else 228f,
            displayMonth: Calendar? = null, previousMonth: Int? = null,
            widgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID): RemoteViews {
            val rowCount = CalendarWidgetMonths.rows(heightDp, single)
            val shownMonth = CalendarWidgetMonths.month(now,
                if (rowCount == 6 && displayMonth != null) CalendarWidgetMonths.index(displayMonth) else CalendarWidgetMonths.index(now))
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
                views.setTextViewText(R.id.widget_date_header, formatter.format(shownMonth.time))
                views.setTextColor(R.id.widget_date_header, Color.parseColor(if (day) "#294E48" else "#30365D"))
                views.setViewVisibility(R.id.widget_month_navigation, if (rowCount == 6) View.VISIBLE else View.GONE)
                for ((button, delta) in listOf(R.id.widget_previous_month to -1, R.id.widget_next_month to 1)) {
                    views.setTextColor(button, Color.parseColor(if (day) "#294E48" else "#30365D"))
                    if (rowCount == 6) views.setOnClickPendingIntent(button,
                        CalendarWidgetNavigationReceiver.pendingIntent(context, widgetId, delta, CalendarWidgetMonths.index(shownMonth)))
                }
                views.setImageViewResource(R.id.widget_day_period,
                    if (day) R.drawable.widget_landscape_day else R.drawable.widget_landscape_night)
                views.setContentDescription(R.id.widget_day_period,
                    context.getString(if (day) R.string.widget_daytime else R.string.widget_nighttime))
            }
            views.setViewVisibility(R.id.empty_message, if (schedule == null) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_content, if (schedule == null) View.GONE else View.VISIBLE)
            if (schedule == null) return views

            fun grid(month: Calendar): RemoteViews {
                val page = if (single) views else RemoteViews(context.packageName, R.layout.calendar_widget_grid)
                fillGrid(context, page, single, now, month, rowCount, schedule, suppliedMemos, widthDp, heightDp, bitmapCache)
                return page
            }
            if (single) return grid(shownMonth)
            views.removeAllViews(R.id.widget_month_pages)
            val animate = previousMonth != null && rowCount == 6 &&
                android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f &&
                android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.TRANSITION_ANIMATION_SCALE, 1f) > 0f
            if (animate) views.addView(R.id.widget_month_pages, grid(CalendarWidgetMonths.month(now, previousMonth!!)))
            views.addView(R.id.widget_month_pages, grid(shownMonth))
            // Establish the old page without an entrance animation first.
            // Otherwise animateFirstView=false also suppresses the month turn.
            // A normal refresh keeps its sole first page without extra selection.
            if (animate) {
                views.setDisplayedChild(R.id.widget_month_pages, 0)
                views.setDisplayedChild(R.id.widget_month_pages, 1)
            }
            return views
        }

        private fun fillGrid(context: Context, views: RemoteViews, single: Boolean,
            now: Calendar, shownMonth: Calendar, rowCount: Int,
            schedule: CalendarWidgetScheduleResolver.ResolvedSchedule,
            suppliedMemos: Map<String, List<String>>?, widthDp: Float, heightDp: Float,
            bitmapCache: MutableMap<Int, Bitmap>) {
            val day = isDaytime(now)
            val first = ReleaseLocalePolicy.firstDayOfWeek(context)
            val weekdays = context.resources.getStringArray(R.array.widget_weekday_labels)
            for (c in 0..6) {
                views.setTextViewText(headerIds[c], weekdays[(c + first - Calendar.SUNDAY) % 7])
                views.setTextColor(headerIds[c], Color.parseColor(if (day) "#355B54" else "#444C77"))
            }
            val start = if (rowCount == 6) CalendarWidgetMonths.start(shownMonth, first) else windowStart(now, first, single)
            if (!single) for (r in 0..5) views.setViewVisibility(rowIds[r], if (r < rowCount) View.VISIBLE else View.GONE)
            val end = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, rowCount * 7 - 1) }
            val memos = suppliedMemos ?: CalendarWidgetScheduleResolver.readMemos(context, dateKeyFor(start), dateKeyFor(end))
            val overrides = CalendarWidgetHolidays.overrides(context)
            val density = context.resources.displayMetrics.density
            // Allocate the available row height to legible notes and their spacing.
            // A one-week widget keeps one home-screen row and only resizes horizontally.
            val rowHeight = ((heightDp - if (single) 24f else 61f) / rowCount - 2f).coerceAtLeast(36f)
            val dateHeight = minOf(if (single) 14f else 16f, rowHeight * .24f)
            val memoArea = (rowHeight - dateHeight - 18f).coerceAtLeast(12f)
            val holidayNames = !single && ReleaseLocalePolicy.koreanFeatures(context)
            val memoGap = if (holidayNames) 0f else minOf(3f, memoArea * .07f)
            val memoHeight = if (holidayNames) minOf(16f, floor(memoArea / 4f))
                else minOf(16f, memoArea / 3f)
            val memoFont = fittedMemoFont(memoHeight, memoGap, density, ReleaseLocalePolicy.locale(context))
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
                val outside = cal.get(Calendar.YEAR) != shownMonth.get(Calendar.YEAR) ||
                    cal.get(Calendar.MONTH) != shownMonth.get(Calendar.MONTH)
                val numberColor = if (red) Color.rgb(196, 48, 56)
                    else if (today) Color.WHITE else Color.parseColor(if (day) "#263F3E" else "#343D61")
                if (!single) views.setFloat(cellIds[index], "setAlpha", if (rowCount == 6 && outside && !today) .58f else 1f)
                views.setTextColor(numIds[index], if (outside && rowCount != 6 && !today)
                    Color.argb(112, Color.red(numberColor), Color.green(numberColor), Color.blue(numberColor)) else numberColor)
                if (!single) {
                    val holiday = CalendarWidgetHolidays.name(context, cal, overrides).orEmpty()
                    val id = holidayIds[index]
                    views.setInt(id, "setHeight", (memoHeight * density).toInt())
                    views.setViewPadding(id, 0, 0, 0, 0)
                    views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_DIP, memoFont)
                    views.setViewVisibility(id, if (holiday.isEmpty()) View.GONE else View.VISIBLE)
                    views.setTextViewText(id, completeMemoPrefix(holiday, widthDp, density, ReleaseLocalePolicy.locale(context), memoFont))
                    views.setTextColor(id, Color.rgb(196, 48, 56))
                    views.setContentDescription(id, holiday)
                }
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
        private fun fittedMemoFont(heightDp: Float, gapDp: Float, density: Float, locale: Locale): Float {
            // RemoteViews rounds padding but truncates setHeight. Fit the actual
            // remaining pixels, including font fallback, rather than a dp ratio.
            val available = ((heightDp * density).toInt() - (gapDp * density).roundToInt()).coerceAtLeast(1)
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = Typeface.create("sans-serif", Typeface.NORMAL)
                textLocale = locale
            }
            val probe = "Ag근म"
            var low = 0f
            var high = 9.5f
            repeat(14) {
                val size = (low + high) / 2f
                paint.textSize = size * density
                val builder = StaticLayout.Builder.obtain(probe, 0, probe.length, paint, 1000)
                    .setIncludePad(false).setAlignment(Layout.Alignment.ALIGN_NORMAL)
                if (Build.VERSION.SDK_INT >= 28) builder.setUseLineSpacingFromFallbacks(true)
                if (builder.build().height <= available) low = size else high = size
            }
            return low
        }

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
            R.id.pill_2_0, R.id.pill_2_1, R.id.pill_2_2, R.id.pill_2_3, R.id.pill_2_4, R.id.pill_2_5, R.id.pill_2_6,
            R.id.pill_3_0, R.id.pill_3_1, R.id.pill_3_2, R.id.pill_3_3, R.id.pill_3_4, R.id.pill_3_5, R.id.pill_3_6,
            R.id.pill_4_0, R.id.pill_4_1, R.id.pill_4_2, R.id.pill_4_3, R.id.pill_4_4, R.id.pill_4_5, R.id.pill_4_6,
            R.id.pill_5_0, R.id.pill_5_1, R.id.pill_5_2, R.id.pill_5_3, R.id.pill_5_4, R.id.pill_5_5, R.id.pill_5_6
        )
        private val pillBgIds = intArrayOf(
            R.id.pillbg_0_0, R.id.pillbg_0_1, R.id.pillbg_0_2, R.id.pillbg_0_3, R.id.pillbg_0_4, R.id.pillbg_0_5, R.id.pillbg_0_6,
            R.id.pillbg_1_0, R.id.pillbg_1_1, R.id.pillbg_1_2, R.id.pillbg_1_3, R.id.pillbg_1_4, R.id.pillbg_1_5, R.id.pillbg_1_6,
            R.id.pillbg_2_0, R.id.pillbg_2_1, R.id.pillbg_2_2, R.id.pillbg_2_3, R.id.pillbg_2_4, R.id.pillbg_2_5, R.id.pillbg_2_6,
            R.id.pillbg_3_0, R.id.pillbg_3_1, R.id.pillbg_3_2, R.id.pillbg_3_3, R.id.pillbg_3_4, R.id.pillbg_3_5, R.id.pillbg_3_6,
            R.id.pillbg_4_0, R.id.pillbg_4_1, R.id.pillbg_4_2, R.id.pillbg_4_3, R.id.pillbg_4_4, R.id.pillbg_4_5, R.id.pillbg_4_6,
            R.id.pillbg_5_0, R.id.pillbg_5_1, R.id.pillbg_5_2, R.id.pillbg_5_3, R.id.pillbg_5_4, R.id.pillbg_5_5, R.id.pillbg_5_6
        )
        private val numIds = intArrayOf(
            R.id.num_0_0, R.id.num_0_1, R.id.num_0_2, R.id.num_0_3, R.id.num_0_4, R.id.num_0_5, R.id.num_0_6,
            R.id.num_1_0, R.id.num_1_1, R.id.num_1_2, R.id.num_1_3, R.id.num_1_4, R.id.num_1_5, R.id.num_1_6,
            R.id.num_2_0, R.id.num_2_1, R.id.num_2_2, R.id.num_2_3, R.id.num_2_4, R.id.num_2_5, R.id.num_2_6,
            R.id.num_3_0, R.id.num_3_1, R.id.num_3_2, R.id.num_3_3, R.id.num_3_4, R.id.num_3_5, R.id.num_3_6,
            R.id.num_4_0, R.id.num_4_1, R.id.num_4_2, R.id.num_4_3, R.id.num_4_4, R.id.num_4_5, R.id.num_4_6,
            R.id.num_5_0, R.id.num_5_1, R.id.num_5_2, R.id.num_5_3, R.id.num_5_4, R.id.num_5_5, R.id.num_5_6
        )
        private val numWrapIds = intArrayOf(
            R.id.numwrap_0_0, R.id.numwrap_0_1, R.id.numwrap_0_2, R.id.numwrap_0_3, R.id.numwrap_0_4, R.id.numwrap_0_5, R.id.numwrap_0_6,
            R.id.numwrap_1_0, R.id.numwrap_1_1, R.id.numwrap_1_2, R.id.numwrap_1_3, R.id.numwrap_1_4, R.id.numwrap_1_5, R.id.numwrap_1_6,
            R.id.numwrap_2_0, R.id.numwrap_2_1, R.id.numwrap_2_2, R.id.numwrap_2_3, R.id.numwrap_2_4, R.id.numwrap_2_5, R.id.numwrap_2_6,
            R.id.numwrap_3_0, R.id.numwrap_3_1, R.id.numwrap_3_2, R.id.numwrap_3_3, R.id.numwrap_3_4, R.id.numwrap_3_5, R.id.numwrap_3_6,
            R.id.numwrap_4_0, R.id.numwrap_4_1, R.id.numwrap_4_2, R.id.numwrap_4_3, R.id.numwrap_4_4, R.id.numwrap_4_5, R.id.numwrap_4_6,
            R.id.numwrap_5_0, R.id.numwrap_5_1, R.id.numwrap_5_2, R.id.numwrap_5_3, R.id.numwrap_5_4, R.id.numwrap_5_5, R.id.numwrap_5_6
        )
        private val cellIds = intArrayOf(
            R.id.cell_0_0, R.id.cell_0_1, R.id.cell_0_2, R.id.cell_0_3, R.id.cell_0_4, R.id.cell_0_5, R.id.cell_0_6,
            R.id.cell_1_0, R.id.cell_1_1, R.id.cell_1_2, R.id.cell_1_3, R.id.cell_1_4, R.id.cell_1_5, R.id.cell_1_6,
            R.id.cell_2_0, R.id.cell_2_1, R.id.cell_2_2, R.id.cell_2_3, R.id.cell_2_4, R.id.cell_2_5, R.id.cell_2_6,
            R.id.cell_3_0, R.id.cell_3_1, R.id.cell_3_2, R.id.cell_3_3, R.id.cell_3_4, R.id.cell_3_5, R.id.cell_3_6,
            R.id.cell_4_0, R.id.cell_4_1, R.id.cell_4_2, R.id.cell_4_3, R.id.cell_4_4, R.id.cell_4_5, R.id.cell_4_6,
            R.id.cell_5_0, R.id.cell_5_1, R.id.cell_5_2, R.id.cell_5_3, R.id.cell_5_4, R.id.cell_5_5, R.id.cell_5_6
        )
        private val holidayIds = intArrayOf(
            R.id.holiday_0_0, R.id.holiday_0_1, R.id.holiday_0_2, R.id.holiday_0_3, R.id.holiday_0_4, R.id.holiday_0_5, R.id.holiday_0_6,
            R.id.holiday_1_0, R.id.holiday_1_1, R.id.holiday_1_2, R.id.holiday_1_3, R.id.holiday_1_4, R.id.holiday_1_5, R.id.holiday_1_6,
            R.id.holiday_2_0, R.id.holiday_2_1, R.id.holiday_2_2, R.id.holiday_2_3, R.id.holiday_2_4, R.id.holiday_2_5, R.id.holiday_2_6,
            R.id.holiday_3_0, R.id.holiday_3_1, R.id.holiday_3_2, R.id.holiday_3_3, R.id.holiday_3_4, R.id.holiday_3_5, R.id.holiday_3_6,
            R.id.holiday_4_0, R.id.holiday_4_1, R.id.holiday_4_2, R.id.holiday_4_3, R.id.holiday_4_4, R.id.holiday_4_5, R.id.holiday_4_6,
            R.id.holiday_5_0, R.id.holiday_5_1, R.id.holiday_5_2, R.id.holiday_5_3, R.id.holiday_5_4, R.id.holiday_5_5, R.id.holiday_5_6
        )
        private val rowIds = intArrayOf(R.id.widget_row_0, R.id.widget_row_1, R.id.widget_row_2, R.id.widget_row_3, R.id.widget_row_4, R.id.widget_row_5)
        private val memoIds = arrayOf(
            intArrayOf(R.id.memo1_0_0, R.id.memo1_0_1, R.id.memo1_0_2, R.id.memo1_0_3, R.id.memo1_0_4, R.id.memo1_0_5, R.id.memo1_0_6, R.id.memo1_1_0, R.id.memo1_1_1, R.id.memo1_1_2, R.id.memo1_1_3, R.id.memo1_1_4, R.id.memo1_1_5, R.id.memo1_1_6, R.id.memo1_2_0, R.id.memo1_2_1, R.id.memo1_2_2, R.id.memo1_2_3, R.id.memo1_2_4, R.id.memo1_2_5, R.id.memo1_2_6, R.id.memo1_3_0, R.id.memo1_3_1, R.id.memo1_3_2, R.id.memo1_3_3, R.id.memo1_3_4, R.id.memo1_3_5, R.id.memo1_3_6, R.id.memo1_4_0, R.id.memo1_4_1, R.id.memo1_4_2, R.id.memo1_4_3, R.id.memo1_4_4, R.id.memo1_4_5, R.id.memo1_4_6, R.id.memo1_5_0, R.id.memo1_5_1, R.id.memo1_5_2, R.id.memo1_5_3, R.id.memo1_5_4, R.id.memo1_5_5, R.id.memo1_5_6),
            intArrayOf(R.id.memo2_0_0, R.id.memo2_0_1, R.id.memo2_0_2, R.id.memo2_0_3, R.id.memo2_0_4, R.id.memo2_0_5, R.id.memo2_0_6, R.id.memo2_1_0, R.id.memo2_1_1, R.id.memo2_1_2, R.id.memo2_1_3, R.id.memo2_1_4, R.id.memo2_1_5, R.id.memo2_1_6, R.id.memo2_2_0, R.id.memo2_2_1, R.id.memo2_2_2, R.id.memo2_2_3, R.id.memo2_2_4, R.id.memo2_2_5, R.id.memo2_2_6, R.id.memo2_3_0, R.id.memo2_3_1, R.id.memo2_3_2, R.id.memo2_3_3, R.id.memo2_3_4, R.id.memo2_3_5, R.id.memo2_3_6, R.id.memo2_4_0, R.id.memo2_4_1, R.id.memo2_4_2, R.id.memo2_4_3, R.id.memo2_4_4, R.id.memo2_4_5, R.id.memo2_4_6, R.id.memo2_5_0, R.id.memo2_5_1, R.id.memo2_5_2, R.id.memo2_5_3, R.id.memo2_5_4, R.id.memo2_5_5, R.id.memo2_5_6),
            intArrayOf(R.id.memo3_0_0, R.id.memo3_0_1, R.id.memo3_0_2, R.id.memo3_0_3, R.id.memo3_0_4, R.id.memo3_0_5, R.id.memo3_0_6, R.id.memo3_1_0, R.id.memo3_1_1, R.id.memo3_1_2, R.id.memo3_1_3, R.id.memo3_1_4, R.id.memo3_1_5, R.id.memo3_1_6, R.id.memo3_2_0, R.id.memo3_2_1, R.id.memo3_2_2, R.id.memo3_2_3, R.id.memo3_2_4, R.id.memo3_2_5, R.id.memo3_2_6, R.id.memo3_3_0, R.id.memo3_3_1, R.id.memo3_3_2, R.id.memo3_3_3, R.id.memo3_3_4, R.id.memo3_3_5, R.id.memo3_3_6, R.id.memo3_4_0, R.id.memo3_4_1, R.id.memo3_4_2, R.id.memo3_4_3, R.id.memo3_4_4, R.id.memo3_4_5, R.id.memo3_4_6, R.id.memo3_5_0, R.id.memo3_5_1, R.id.memo3_5_2, R.id.memo3_5_3, R.id.memo3_5_4, R.id.memo3_5_5, R.id.memo3_5_6)
        )
    }
}

class WeekCalendarWidgetProvider : CalendarWidgetProvider() {
    override val singleWeek = true
}
