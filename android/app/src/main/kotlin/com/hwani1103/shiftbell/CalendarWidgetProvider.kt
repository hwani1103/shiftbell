package com.hwani1103.shiftbell

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
import android.widget.RemoteViews
import java.util.*

/**
 * ⭐ 홈 화면 캘린더 위젯. 앱을 안 열어도 전주/이번주/다음주(월~일이 아니라 달력탭과 같은
 * 일~토 기준) 근무 일정 + 오늘 강조 + 근무색을 그대로 보여줌.
 *
 * 크기가 2가지 - 위젯을 충분히 크게 리사이즈하면(onAppWidgetOptionsChanged) "컴팩트"(3주,
 * calendar_widget.xml)에서 "큰"(달력 월 전체 6주, calendar_widget_full.xml)으로 자동
 * 전환됨. 위젯 인스턴스마다 독립적으로 크기를 기억하므로 updateAll()이 매번 각 id의
 * 현재 크기를 다시 확인해서 그에 맞는 레이아웃으로 그림.
 *
 * 데이터는 항상 그 순간 DB(shift_schedule)를 직접 읽어서 그림 - 별도 캐시 테이블을 두지
 * 않음. 그래서 "근무명 변경/색상 변경/날짜별 근무 변경이 위젯에도 반영돼야 한다"는 요구가
 * 캐시 무효화 로직 없이 자동으로 항상 충족됨 (캐시가 없으니 오래될 수도 없음).
 *
 * 갱신 트리거 2단:
 *  1) 즉시: schedule_provider.dart가 스케줄을 저장/변경할 때마다
 *     MainActivity의 "refreshCalendarWidget" MethodChannel을 호출 → requestUpdate() 직접 실행.
 *  2) 주기적: AlarmGuardReceiver가 이미 자정/20분전마다 깨어나는 기존 하트비트에
 *     같이 얹어서 requestUpdate() 호출 (앱을 아예 안 열어도 "오늘" 표시와 3주 창이
 *     매일 자정에 맞춰 넘어감). 알람 갱신 로직과는 완전히 독립된 read-only 경로라
 *     같이 실행돼도 알람 시스템에 영향 없음.
 *  둘 다 실패해도 Android의 updatePeriodMillis(30분)가 최후 backstop으로 남아있음.
 *
 * 렌더링에서 발생하는 모든 예외는 이 안에서 잡아서 삼킴 - AppWidgetProvider의 콜백은
 * 앱 자신의 프로세스에서 실행되므로, 여기서 uncaught exception이 나면 위젯이 아니라
 * 앱 전체가 크래시할 수 있음. 위젯 렌더링 실패가 알람 등 다른 기능까지 끌고 내려가는
 * 일은 절대 없어야 해서 이 클래스 전체를 방어적으로 작성함.
 */
class CalendarWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "CalendarWidgetProvider"
        private const val LARGE_MODE_MIN_HEIGHT_DP = 400

        // ⭐ 라이트 모드 색상 (app_theme.dart lightTheme과 동일한 값)
        private const val LIGHT_TEXT_NORMAL = "#FF000000"
        private const val LIGHT_TEXT_SUNDAY = "#FFF44336"
        private const val LIGHT_TEXT_TODAY = "#FFFFFFFF"
        private const val LIGHT_TEXT_TODAY_HOLIDAY = "#FFF44336"
        private const val LIGHT_HEADER_TEXT = "#FF000000"
        private const val LIGHT_NO_SHIFT_COLOR = "#FFF5F5F5"
        // ⭐ 이번 달이 아닌 날짜(전주/다음주가 다른 달로 걸칠 때) - 달력탭 isOutside와 동일하게
        // 반투명 처리 (calendar_tab.dart: onSurfaceVariant.withOpacity(0.5) / red.withOpacity(0.3))
        private const val LIGHT_TEXT_OUTSIDE = "#80616161"
        private const val LIGHT_TEXT_OUTSIDE_SUNDAY = "#4DF44336"

        // ⭐ 다크 모드 색상 (app_theme.dart darkTheme과 동일한 값)
        private const val DARK_TEXT_NORMAL = "#FFF5F7FB"
        private const val DARK_TEXT_SUNDAY = "#FFE57373"
        private const val DARK_TEXT_TODAY = "#FF1A1F2E"
        private const val DARK_TEXT_TODAY_HOLIDAY = "#FFB71C1C"
        private const val DARK_HEADER_TEXT = "#FFF5F7FB"
        private const val DARK_NO_SHIFT_COLOR = "#FF2E3547"
        // ⭐ 이번 달이 아닌 날짜 (calendar_tab.dart: onSurfaceVariant.withOpacity(0.5) /
        // red.shade300.withOpacity(0.5))
        private const val DARK_TEXT_OUTSIDE = "#80D8DBE5"
        private const val DARK_TEXT_OUTSIDE_SUNDAY = "#80E57373"

        // ⭐ 근무색 배경 위 텍스트 자동 대비 색상 (shift_schedule.dart isBright/getTextColor와
        // 동일 공식 - 두 곳이 서로 다른 기준으로 계산하면 앱과 위젯에서 같은 색상인데
        // 글씨 색이 다르게 보이는 위화감이 생길 수 있어서 그대로 복제함)
        private const val PILL_TEXT_DARK = "#FF212121"
        private const val PILL_TEXT_LIGHT = "#FFFFFFFF"

        private val WEEKDAY_LABELS = arrayOf("일", "월", "화", "수", "목", "금", "토")

        // ⭐ 즉시 갱신 요청 (Flutter 저장 직후, 또는 AlarmGuardReceiver 하트비트에서 호출)
        fun requestUpdate(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, CalendarWidgetProvider::class.java))
                if (ids.isEmpty()) return  // 위젯이 홈 화면에 하나도 없으면 할 일 없음
                updateAll(context, manager, ids)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯 갱신 요청 실패", e)
            }
        }

        // ⭐ 위젯 인스턴스마다 사용자가 다르게 리사이즈했을 수 있어서(컴팩트 3주 vs
        // 큰 6주), id 하나당 각자의 현재 크기에 맞는 RemoteViews를 따로 만들어서 push함.
        private fun updateAll(context: Context, manager: AppWidgetManager, ids: IntArray) {
            for (id in ids) {
                try {
                    val views = buildRemoteViews(context, isLargeMode(manager, id))
                    manager.updateAppWidget(id, views)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 위젯($id) 렌더링 실패", e)
                }
            }
            Log.d(TAG, "✅ 위젯 ${ids.size}개 갱신 완료")
        }

        // ⭐ 사용자가 위젯을 충분히 크게 리사이즈했는지 - 세로 여유가 있어야 6주(달력탭과
        // 동일한 전체 달력 그리드)를 담기에 안 답답하다고 판단해서 세로 높이만 기준으로 삼음.
        // ⚠️ 처음엔 210dp를 기준으로 잡았는데, 실제 갤럭시(One UI)에서 dumpsys appwidget으로
        // 확인해보니 "4x3"(3주로 유지되길 원하는 크기) 배치가 이미 minHeight=344dp를 보고해서
        // 항상 큰 모드로 튀는 버그가 있었음. 4x3=344dp, 4x4 추정 ~459dp(=344/3*4) 실측/추정치
        // 사이의 중간값(400dp)으로 다시 잡음 - 다른 런처는 그리드 셀 크기가 또 다를 수 있어서
        // 완벽히 보편적이진 않지만, 절대 dp 기준 외에는 표준 API로 얻을 방법이 없음.
        private fun isLargeMode(manager: AppWidgetManager, appWidgetId: Int): Boolean {
            return try {
                val options = manager.getAppWidgetOptions(appWidgetId)
                val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
                Log.d(TAG, "📏 위젯($appWidgetId) minHeight=${minHeight}dp")
                minHeight >= LARGE_MODE_MIN_HEIGHT_DP
            } catch (e: Exception) {
                false
            }
        }

        private const val PREFS_NAME = "widget_state"
        private const val KEY_IS_DARK = "is_dark_mode"
        private const val KEY_IS_DARK_SET = "is_dark_mode_set"

        // ⭐ Flutter가 테마를 바꿀 때마다 setWidgetTheme MethodChannel로 호출함
        // (theme_provider.dart의 setThemeMode / main.dart의 앱 시작 시점 둘 다).
        fun setThemeOverride(context: Context, isDark: Boolean) {
            try {
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                    .putBoolean(KEY_IS_DARK, isDark)
                    .putBoolean(KEY_IS_DARK_SET, true)
                    .apply()
                requestUpdate(context)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯 테마 저장 실패", e)
            }
        }

        // ⭐ 앱이 명시적으로 알려준 테마(라이트/다크, 수동 설정 포함)가 있으면 그걸 그대로
        // 따름. 아직 한 번도 전달받은 적 없으면(예: 이 기능 추가 전 이미 배치된 위젯을
        // 최초 갱신하는 순간) 시스템 다크모드 설정으로 폴백함 - main.dart의
        // "수동 설정 없으면 시스템 밝기 따라감" 로직과 동일한 우선순위.
        private fun isDarkMode(context: Context): Boolean {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                if (prefs.getBoolean(KEY_IS_DARK_SET, false)) {
                    return prefs.getBoolean(KEY_IS_DARK, false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯 테마 읽기 실패 - 시스템 설정으로 폴백", e)
            }
            val flags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            return flags == Configuration.UI_MODE_NIGHT_YES
        }

        private fun buildRemoteViews(context: Context, isLarge: Boolean): RemoteViews {
            val layoutRes = if (isLarge) R.layout.calendar_widget_full else R.layout.calendar_widget
            val rowCount = if (isLarge) 6 else 3
            val views = RemoteViews(context.packageName, layoutRes)
            val isDark = isDarkMode(context)
            val density = context.resources.displayMetrics.density

            views.setInt(
                R.id.widget_panel, "setBackgroundResource",
                if (isDark) R.drawable.widget_panel_dark else R.drawable.widget_panel_light
            )

            // ⭐ 위젯 전체 탭 → 앱 실행, 달력 탭(index=1)으로 바로 이동
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("openTab", 1)
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_panel, pendingIntent)

            val schedule = CalendarWidgetScheduleResolver.readSchedule(context)
            if (schedule == null) {
                // ⭐ 아직 앱에서 스케줄 설정을 아예 안 한 상태 - 안내 문구만 보여줌
                views.setViewVisibility(R.id.empty_message, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_content, android.view.View.GONE)
                return views
            }
            views.setViewVisibility(R.id.empty_message, android.view.View.GONE)
            views.setViewVisibility(R.id.widget_content, android.view.View.VISIBLE)

            val headerTextColor = Color.parseColor(if (isDark) DARK_HEADER_TEXT else LIGHT_HEADER_TEXT)
            val headerIds = intArrayOf(R.id.hdr_0, R.id.hdr_1, R.id.hdr_2, R.id.hdr_3, R.id.hdr_4, R.id.hdr_5, R.id.hdr_6)
            for (c in 0..6) {
                views.setTextViewText(headerIds[c], WEEKDAY_LABELS[c])
                views.setTextColor(headerIds[c], headerTextColor)
            }

            val today = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            // ⭐ 컴팩트(3주): 이번 주(일~토)의 일요일부터 -7일 = 전주 일요일이 창의 시작.
            // 큰(6주): 달력탭과 완전히 동일한 "이번 달 1일이 속한 주의 일요일"부터 시작
            // (calendar_tab.dart의 calendarStart 계산과 동일한 공식 - Dart weekday(월=1~일=7)
            // 대신 Calendar.DAY_OF_WEEK(일=1~토=7)를 쓰지만 "일요일까지 며칠 전인지"는 동일함).
            val windowStart = if (isLarge) {
                val firstOfMonth = (today.clone() as Calendar).apply { set(Calendar.DAY_OF_MONTH, 1) }
                val daysFromSunday = firstOfMonth.get(Calendar.DAY_OF_WEEK) - Calendar.SUNDAY
                (firstOfMonth.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -daysFromSunday) }
            } else {
                val daysSinceSunday = today.get(Calendar.DAY_OF_WEEK) - Calendar.SUNDAY
                (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -daysSinceSunday - 7) }
            }
            val windowEnd = (windowStart.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, rowCount * 7 - 1) }

            // ⭐ 달력탭처럼 날짜별 메모(최대 3개)도 같이 보여줌 - 위젯에 보이는 창 범위
            // 전체(전주~다음주 또는 달력 6주)를 한 번에 읽어와서 셀 렌더링 때 재사용.
            val memosByDate = CalendarWidgetScheduleResolver.readMemos(
                context, dateKeyFor(windowStart), dateKeyFor(windowEnd)
            )

            val cellPillIds = arrayOf(
                intArrayOf(R.id.pill_0_0, R.id.pill_0_1, R.id.pill_0_2, R.id.pill_0_3, R.id.pill_0_4, R.id.pill_0_5, R.id.pill_0_6),
                intArrayOf(R.id.pill_1_0, R.id.pill_1_1, R.id.pill_1_2, R.id.pill_1_3, R.id.pill_1_4, R.id.pill_1_5, R.id.pill_1_6),
                intArrayOf(R.id.pill_2_0, R.id.pill_2_1, R.id.pill_2_2, R.id.pill_2_3, R.id.pill_2_4, R.id.pill_2_5, R.id.pill_2_6),
                intArrayOf(R.id.pill_3_0, R.id.pill_3_1, R.id.pill_3_2, R.id.pill_3_3, R.id.pill_3_4, R.id.pill_3_5, R.id.pill_3_6),
                intArrayOf(R.id.pill_4_0, R.id.pill_4_1, R.id.pill_4_2, R.id.pill_4_3, R.id.pill_4_4, R.id.pill_4_5, R.id.pill_4_6),
                intArrayOf(R.id.pill_5_0, R.id.pill_5_1, R.id.pill_5_2, R.id.pill_5_3, R.id.pill_5_4, R.id.pill_5_5, R.id.pill_5_6)
            )
            // ⭐ 근무색 알약의 "둥근 배경"용 ImageView (텍스트 뷰인 pill_r_c와 겹쳐 놓임).
            // RemoteViews는 임의 색상 + 둥근 모서리를 동시에 가진 배경을 리소스 스왑만으로
            // 표현할 방법이 없어서(색이 사용자마다 제각각), 직접 그린 둥근 사각형 비트맵을
            // ImageView에 앉히는 방식으로 구현함 (모든 API 레벨에서 동작, API31+ 전용 기능 불필요).
            // ⭐ 6줄(큰) 레이아웃에만 있는 pill_3_x~pill_5_x 같은 id는 컴팩트 레이아웃엔 없지만,
            // R.id는 앱 전체에서 하나의 네임스페이스라 참조 자체는 항상 유효함 - 아래 루프가
            // rowCount로 걸러주기 때문에 컴팩트 모드에서는 애초에 이 id들을 건드리지 않음.
            val cellPillBgIds = arrayOf(
                intArrayOf(R.id.pillbg_0_0, R.id.pillbg_0_1, R.id.pillbg_0_2, R.id.pillbg_0_3, R.id.pillbg_0_4, R.id.pillbg_0_5, R.id.pillbg_0_6),
                intArrayOf(R.id.pillbg_1_0, R.id.pillbg_1_1, R.id.pillbg_1_2, R.id.pillbg_1_3, R.id.pillbg_1_4, R.id.pillbg_1_5, R.id.pillbg_1_6),
                intArrayOf(R.id.pillbg_2_0, R.id.pillbg_2_1, R.id.pillbg_2_2, R.id.pillbg_2_3, R.id.pillbg_2_4, R.id.pillbg_2_5, R.id.pillbg_2_6),
                intArrayOf(R.id.pillbg_3_0, R.id.pillbg_3_1, R.id.pillbg_3_2, R.id.pillbg_3_3, R.id.pillbg_3_4, R.id.pillbg_3_5, R.id.pillbg_3_6),
                intArrayOf(R.id.pillbg_4_0, R.id.pillbg_4_1, R.id.pillbg_4_2, R.id.pillbg_4_3, R.id.pillbg_4_4, R.id.pillbg_4_5, R.id.pillbg_4_6),
                intArrayOf(R.id.pillbg_5_0, R.id.pillbg_5_1, R.id.pillbg_5_2, R.id.pillbg_5_3, R.id.pillbg_5_4, R.id.pillbg_5_5, R.id.pillbg_5_6)
            )
            // ⭐ 같은 색이 여러 셀에 반복되는 경우가 많아서(같은 근무가 여러 날 배정) 색상별로
            // 비트맵을 한 번만 그려서 재사용 - 42칸이라도 실제 Bitmap 생성은 보통 몇 개뿐.
            val pillBitmapCache = mutableMapOf<Int, Bitmap>()
            val cellNumIds = arrayOf(
                intArrayOf(R.id.num_0_0, R.id.num_0_1, R.id.num_0_2, R.id.num_0_3, R.id.num_0_4, R.id.num_0_5, R.id.num_0_6),
                intArrayOf(R.id.num_1_0, R.id.num_1_1, R.id.num_1_2, R.id.num_1_3, R.id.num_1_4, R.id.num_1_5, R.id.num_1_6),
                intArrayOf(R.id.num_2_0, R.id.num_2_1, R.id.num_2_2, R.id.num_2_3, R.id.num_2_4, R.id.num_2_5, R.id.num_2_6),
                intArrayOf(R.id.num_3_0, R.id.num_3_1, R.id.num_3_2, R.id.num_3_3, R.id.num_3_4, R.id.num_3_5, R.id.num_3_6),
                intArrayOf(R.id.num_4_0, R.id.num_4_1, R.id.num_4_2, R.id.num_4_3, R.id.num_4_4, R.id.num_4_5, R.id.num_4_6),
                intArrayOf(R.id.num_5_0, R.id.num_5_1, R.id.num_5_2, R.id.num_5_3, R.id.num_5_4, R.id.num_5_5, R.id.num_5_6)
            )
            // ⭐ num_r_c를 감싸는 배경 없는 래퍼 - 메모 3개일 때 숫자를 위로 띄우는 여백을
            // num_r_c 자신에게 주면(setViewPadding) 오늘 강조 배경(setBackgroundResource)이
            // 패딩 전체를 덮어버려서 뱃지가 길쭉하게 늘어나 보이는 문제가 있었음. 배경 없는
            // 이 래퍼에 여백을 주면 num_r_c는 항상 고정 크기(=배경도 항상 딱 맞는 뱃지
            // 크기)를 유지한 채로 통째로 위/아래로만 이동함.
            val cellNumWrapIds = arrayOf(
                intArrayOf(R.id.numwrap_0_0, R.id.numwrap_0_1, R.id.numwrap_0_2, R.id.numwrap_0_3, R.id.numwrap_0_4, R.id.numwrap_0_5, R.id.numwrap_0_6),
                intArrayOf(R.id.numwrap_1_0, R.id.numwrap_1_1, R.id.numwrap_1_2, R.id.numwrap_1_3, R.id.numwrap_1_4, R.id.numwrap_1_5, R.id.numwrap_1_6),
                intArrayOf(R.id.numwrap_2_0, R.id.numwrap_2_1, R.id.numwrap_2_2, R.id.numwrap_2_3, R.id.numwrap_2_4, R.id.numwrap_2_5, R.id.numwrap_2_6),
                intArrayOf(R.id.numwrap_3_0, R.id.numwrap_3_1, R.id.numwrap_3_2, R.id.numwrap_3_3, R.id.numwrap_3_4, R.id.numwrap_3_5, R.id.numwrap_3_6),
                intArrayOf(R.id.numwrap_4_0, R.id.numwrap_4_1, R.id.numwrap_4_2, R.id.numwrap_4_3, R.id.numwrap_4_4, R.id.numwrap_4_5, R.id.numwrap_4_6),
                intArrayOf(R.id.numwrap_5_0, R.id.numwrap_5_1, R.id.numwrap_5_2, R.id.numwrap_5_3, R.id.numwrap_5_4, R.id.numwrap_5_5, R.id.numwrap_5_6)
            )
            // ⭐ 셀당 메모 슬롯 최대 3개 (달력탭의 memos.take(3)과 동일). 각 슬롯은
            // 해당 날짜에 그만큼 메모가 없으면 GONE 처리됨. [슬롯][행][열] 3중 배열.
            val cellMemoIds = arrayOf(
                arrayOf(
                    intArrayOf(R.id.memo1_0_0, R.id.memo1_0_1, R.id.memo1_0_2, R.id.memo1_0_3, R.id.memo1_0_4, R.id.memo1_0_5, R.id.memo1_0_6),
                    intArrayOf(R.id.memo1_1_0, R.id.memo1_1_1, R.id.memo1_1_2, R.id.memo1_1_3, R.id.memo1_1_4, R.id.memo1_1_5, R.id.memo1_1_6),
                    intArrayOf(R.id.memo1_2_0, R.id.memo1_2_1, R.id.memo1_2_2, R.id.memo1_2_3, R.id.memo1_2_4, R.id.memo1_2_5, R.id.memo1_2_6),
                    intArrayOf(R.id.memo1_3_0, R.id.memo1_3_1, R.id.memo1_3_2, R.id.memo1_3_3, R.id.memo1_3_4, R.id.memo1_3_5, R.id.memo1_3_6),
                    intArrayOf(R.id.memo1_4_0, R.id.memo1_4_1, R.id.memo1_4_2, R.id.memo1_4_3, R.id.memo1_4_4, R.id.memo1_4_5, R.id.memo1_4_6),
                    intArrayOf(R.id.memo1_5_0, R.id.memo1_5_1, R.id.memo1_5_2, R.id.memo1_5_3, R.id.memo1_5_4, R.id.memo1_5_5, R.id.memo1_5_6)
                ),
                arrayOf(
                    intArrayOf(R.id.memo2_0_0, R.id.memo2_0_1, R.id.memo2_0_2, R.id.memo2_0_3, R.id.memo2_0_4, R.id.memo2_0_5, R.id.memo2_0_6),
                    intArrayOf(R.id.memo2_1_0, R.id.memo2_1_1, R.id.memo2_1_2, R.id.memo2_1_3, R.id.memo2_1_4, R.id.memo2_1_5, R.id.memo2_1_6),
                    intArrayOf(R.id.memo2_2_0, R.id.memo2_2_1, R.id.memo2_2_2, R.id.memo2_2_3, R.id.memo2_2_4, R.id.memo2_2_5, R.id.memo2_2_6),
                    intArrayOf(R.id.memo2_3_0, R.id.memo2_3_1, R.id.memo2_3_2, R.id.memo2_3_3, R.id.memo2_3_4, R.id.memo2_3_5, R.id.memo2_3_6),
                    intArrayOf(R.id.memo2_4_0, R.id.memo2_4_1, R.id.memo2_4_2, R.id.memo2_4_3, R.id.memo2_4_4, R.id.memo2_4_5, R.id.memo2_4_6),
                    intArrayOf(R.id.memo2_5_0, R.id.memo2_5_1, R.id.memo2_5_2, R.id.memo2_5_3, R.id.memo2_5_4, R.id.memo2_5_5, R.id.memo2_5_6)
                ),
                arrayOf(
                    intArrayOf(R.id.memo3_0_0, R.id.memo3_0_1, R.id.memo3_0_2, R.id.memo3_0_3, R.id.memo3_0_4, R.id.memo3_0_5, R.id.memo3_0_6),
                    intArrayOf(R.id.memo3_1_0, R.id.memo3_1_1, R.id.memo3_1_2, R.id.memo3_1_3, R.id.memo3_1_4, R.id.memo3_1_5, R.id.memo3_1_6),
                    intArrayOf(R.id.memo3_2_0, R.id.memo3_2_1, R.id.memo3_2_2, R.id.memo3_2_3, R.id.memo3_2_4, R.id.memo3_2_5, R.id.memo3_2_6),
                    intArrayOf(R.id.memo3_3_0, R.id.memo3_3_1, R.id.memo3_3_2, R.id.memo3_3_3, R.id.memo3_3_4, R.id.memo3_3_5, R.id.memo3_3_6),
                    intArrayOf(R.id.memo3_4_0, R.id.memo3_4_1, R.id.memo3_4_2, R.id.memo3_4_3, R.id.memo3_4_4, R.id.memo3_4_5, R.id.memo3_4_6),
                    intArrayOf(R.id.memo3_5_0, R.id.memo3_5_1, R.id.memo3_5_2, R.id.memo3_5_3, R.id.memo3_5_4, R.id.memo3_5_5, R.id.memo3_5_6)
                )
            )

            val normalTextColor = Color.parseColor(if (isDark) DARK_TEXT_NORMAL else LIGHT_TEXT_NORMAL)
            val sundayTextColor = Color.parseColor(if (isDark) DARK_TEXT_SUNDAY else LIGHT_TEXT_SUNDAY)
            val outsideTextColor = Color.parseColor(if (isDark) DARK_TEXT_OUTSIDE else LIGHT_TEXT_OUTSIDE)
            val outsideSundayTextColor = Color.parseColor(if (isDark) DARK_TEXT_OUTSIDE_SUNDAY else LIGHT_TEXT_OUTSIDE_SUNDAY)
            val todayTextColor = Color.parseColor(if (isDark) DARK_TEXT_TODAY else LIGHT_TEXT_TODAY)
            val todayHolidayTextColor = Color.parseColor(if (isDark) DARK_TEXT_TODAY_HOLIDAY else LIGHT_TEXT_TODAY_HOLIDAY)
            val noShiftColor = Color.parseColor(if (isDark) DARK_NO_SHIFT_COLOR else LIGHT_NO_SHIFT_COLOR)
            val todayNormalBg = if (isDark) R.drawable.widget_today_normal_dark else R.drawable.widget_today_normal_light
            val todayHolidayBg = if (isDark) R.drawable.widget_today_holiday_dark else R.drawable.widget_today_holiday_light
            // ⭐ 메모 박스 배경/글자색 - 달력탭 메모 박스와 동일 톤 (색상은 셀마다 다를 필요가
            // 없어서 근무색 알약과 달리 정적 drawable 리소스 하나로 충분함)
            val memoBg = if (isDark) R.drawable.widget_memo_bg_dark else R.drawable.widget_memo_bg_light
            val memoTextColor = normalTextColor

            for (r in 0 until rowCount) {
                for (c in 0..6) {
                    val cal = (windowStart.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, r * 7 + c) }
                    val isToday = isSameDay(cal, today)
                    val isSunday = c == 0  // 항상 0열 = 일요일 (창이 항상 일요일부터 시작)
                    // ⭐ 일요일이 아니어도 공휴일이면 숫자가 빨간색이어야 함 (예: 공휴일인 금요일).
                    // 달력탭처럼 이름 텍스트까지는 안 보여줘도, 숫자 색만큼은 반영함.
                    val isRedDay = isSunday || CalendarWidgetHolidays.isHoliday(cal)
                    // ⭐ 위젯엔 달력탭 같은 "보고 있는 달" 개념이 없어서, 실제 오늘이 속한
                    // 달을 기준으로 "이번 달이 아닌 날짜"(전주/다음주가 다른 달로 걸치는 경우)를 판단
                    val isOutsideMonth = !isSameMonth(cal, today)

                    val shiftType = try {
                        CalendarWidgetScheduleResolver.shiftForDate(schedule, cal)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 날짜별 근무 계산 실패", e)
                        "미설정"
                    }

                    val hasShift = shiftType.isNotEmpty() && shiftType != "미설정"
                    val pillColor = when {
                        !hasShift -> Color.TRANSPARENT
                        shiftType == "없음" -> noShiftColor
                        else -> schedule.shiftColors[shiftType] ?: Color.TRANSPARENT
                    }
                    if (hasShift) {
                        val bitmap = pillBitmapCache.getOrPut(pillColor) { roundedPillBitmap(pillColor) }
                        views.setImageViewBitmap(cellPillBgIds[r][c], bitmap)
                        views.setTextViewText(cellPillIds[r][c], shiftType)
                        views.setTextColor(cellPillIds[r][c], pillTextColorFor(pillColor))
                    } else {
                        views.setImageViewResource(cellPillBgIds[r][c], 0)  // ⭐ 배경 비움 (미설정인 날)
                        views.setTextViewText(cellPillIds[r][c], "")
                    }

                    views.setTextViewText(cellNumIds[r][c], cal.get(Calendar.DAY_OF_MONTH).toString())

                    if (isToday) {
                        views.setInt(cellNumIds[r][c], "setBackgroundResource", if (isRedDay) todayHolidayBg else todayNormalBg)
                        views.setTextColor(cellNumIds[r][c], if (isRedDay) todayHolidayTextColor else todayTextColor)
                    } else {
                        views.setInt(cellNumIds[r][c], "setBackgroundColor", Color.TRANSPARENT)
                        val numColor = when {
                            isOutsideMonth && isRedDay -> outsideSundayTextColor
                            isOutsideMonth -> outsideTextColor
                            isRedDay -> sundayTextColor
                            else -> normalTextColor
                        }
                        views.setTextColor(cellNumIds[r][c], numColor)
                    }

                    // ⭐ 메모 최대 3개 - 있는 만큼만 채우고 나머지 슬롯은 숨김
                    val memos = memosByDate[dateKeyFor(cal)] ?: emptyList()
                    for (slot in 0..2) {
                        val memoId = cellMemoIds[slot][r][c]
                        if (slot < memos.size) {
                            views.setTextViewText(memoId, memos[slot])
                            views.setInt(memoId, "setBackgroundResource", memoBg)
                            views.setTextColor(memoId, memoTextColor)
                            views.setViewVisibility(memoId, android.view.View.VISIBLE)
                        } else {
                            views.setViewVisibility(memoId, android.view.View.GONE)
                        }
                    }
                    // ⭐ 달력탭과 동일하게 - 메모가 3개 꽉 차면 숫자를 위로 살짝 띄워서
                    // 메모 박스 3줄과 안 겹치게 함 (calendar_tab.dart의
                    // "memoCount >= 3 ? 20.h 아래 여백" 로직과 동일한 목적).
                    // 배경 없는 래퍼(numwrap)에만 여백을 줘서 num_r_c 자신(=오늘 강조
                    // 배경 포함)은 항상 고정 크기 뱃지를 유지한 채로 통째로 이동함.
                    val numExtraBottomDp = if (memos.size >= 3) 30 else 0
                    views.setViewPadding(cellNumWrapIds[r][c], 0, 0, 0, (numExtraBottomDp * density).toInt())
                }
            }

            return views
        }

        // ⭐ Calendar → "yyyy-MM-dd" 문자열 (date_memos 테이블 키 형식과 동일)
        private fun dateKeyFor(cal: Calendar): String {
            return "%04d-%02d-%02d".format(
                cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH)
            )
        }

        private fun isSameDay(a: Calendar, b: Calendar): Boolean {
            return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
                a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
        }

        private fun isSameMonth(a: Calendar, b: Calendar): Boolean {
            return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
                a.get(Calendar.MONTH) == b.get(Calendar.MONTH)
        }

        // ⭐ 근무색 알약 배경용 둥근 사각형 비트맵. ImageView가 scaleType="fitXY"로
        // 늘려서 채우기 때문에 실제 셀 크기(런처마다/리사이즈마다 다름)를 몰라도
        // 상관없음 - 작은 고정 크기로 그려도 늘어나면서 계속 둥글게 보임.
        private fun roundedPillBitmap(color: Int): Bitmap {
            val width = 120
            val height = 60
            val radius = 14f
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, paint)
            return bitmap
        }

        // ⭐ shift_schedule.dart의 isBright()/getTextColor()와 동일한 공식
        // (luminance = r*0.299 + g*0.587 + b*0.114, 200 초과면 밝은 배경으로 판단)
        private fun pillTextColorFor(bgColor: Int): Int {
            val r = Color.red(bgColor)
            val g = Color.green(bgColor)
            val b = Color.blue(bgColor)
            val luminance = r * 0.299 + g * 0.587 + b * 0.114
            return Color.parseColor(if (luminance > 200) PILL_TEXT_DARK else PILL_TEXT_LIGHT)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        try {
            updateAll(context, appWidgetManager, appWidgetIds)
        } catch (e: Exception) {
            Log.e(TAG, "❌ onUpdate 실패", e)
        }
    }

    // ⭐ 사용자가 위젯 크기를 드래그로 바꿀 때마다 호출됨. 컴팩트(3주) ↔ 큰(6주, 달력탭과
    // 동일한 달력 월 전체 그리드) 레이아웃을 이 시점에 즉시 전환함.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        try {
            val minHeight = newOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            Log.d(TAG, "📏 onAppWidgetOptionsChanged($appWidgetId) minHeight=${minHeight}dp")
            val views = buildRemoteViews(context, minHeight >= LARGE_MODE_MIN_HEIGHT_DP)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            Log.e(TAG, "❌ onAppWidgetOptionsChanged 실패", e)
        }
    }
}
