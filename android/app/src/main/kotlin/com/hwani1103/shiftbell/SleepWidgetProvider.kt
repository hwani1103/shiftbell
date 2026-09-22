package com.hwani1103.shiftbell

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import java.util.Calendar

/**
 * ⭐ 실제 수면 기록 위젯("C번 요구사항") - 홈 화면 캘린더 위젯([CalendarWidgetProvider],
 * 수정 없음)과 **완전히 별개**의 새 위젯. "오늘: OO"/"상태: OO" 두 줄 +
 * "수면"/"기상" 버튼 2개(수면기록_자동추정_설계.md 6장, 2026-09-01 재설계 -
 * 토글 버튼 1개 → 명시적 버튼 2개로 변경. 사용자 피드백: 토글 방식은 지금
 * 상태가 뭔지/버튼을 누르면 뭐가 될지 헷갈림).
 *
 * ⭐ 2026-09-01 추가 - "위젯을 스마트하게" 요청: 사용자가 버튼을 한 번도 안 눌러도
 * 자동 감지(`SleepDetectionReceiver`)가 진행 중(`AUTO_DETECTED`, `end_time IS NULL`)
 * 후보를 만들어뒀으면 위젯도 "수면 중"으로 보여준다("추정"임을 문구로 구분).
 * [SleepingState] 참고 - MANUAL/AUTO를 합쳐 "지금 자고 있다고 볼 수 있는가"를 계산.
 *
 * ⭐ 2026-09-22(사용자 요청) - 3x1 → **2x1**. 보여주는 것은 "오늘 근무명 · 수면 · 기상" 세
 * 가지뿐이라 "오늘 근무" 같은 라벨은 뺐다(근무명 칩 자체가 곧 라벨). 오늘 배정된 근무가
 * 없으면(불규칙 근무의 빈 날 등) 칩에 "근무없음". 폭이 좁은 화면에서도 겹치지 않도록
 * 칩의 최대 폭을 런처가 알려주는 **실제 위젯 폭**(OPTION_APPWIDGET_MIN_WIDTH)에서 계산하고,
 * 폭이 줄면 글자를 먼저 줄인 뒤에야 말줄임한다([roundedChipBitmap]).
 *
 * 렌더링에서 발생하는 모든 예외는 이 안에서 잡아서 삼킨다 - CalendarWidgetProvider.kt와
 * 동일한 방어 원칙(위젯 렌더링 실패가 앱 전체를 끌고 내려가면 안 됨).
 */
class SleepWidgetProvider : AppWidgetProvider() {

    /** 지금 "자고 있다고 볼 수 있는" 근거가 무엇인지 - 위젯 문구/버튼 강조에 씀. */
    enum class SleepingState { NONE, MANUAL, AUTO }

    companion object {
        private const val TAG = "SleepWidgetProvider"
        const val ACTION_SLEEP = "com.hwani1103.shiftbell.SLEEP_WIDGET_SLEEP"
        const val ACTION_WAKE = "com.hwani1103.shiftbell.SLEEP_WIDGET_WAKE"

        private const val UNSET_SENTINEL = "미설정"

        // ⭐ 2x1의 공식 최소 폭 = 70*2-30 = 110dp(sleep_widget_info.xml). 런처가 폭을 못 알려주면
        // 가장 좁은 경우를 가정해 절대 넘치지 않는 쪽으로 그린다.
        private const val DEFAULT_WIDGET_WIDTH_DP = 110

        // ⭐ 2026-09-01 후속13(사용자 요청) - 근무명 칩은 달력탭/캘린더 위젯과 동일하게
        // 그 근무명에 배정된 색을 그대로 씀(shiftChip 참고). 상태는 처음엔 칩(색상
        // 배경 pill)으로 만들었었는데, 후속15에서 일부 런처 캐싱 문제로 칩을
        // 없애고 평범한 텍스트로 되돌림(statusValue 참고) - 그래서 상태 전용
        // 색상 상수(활동/수면)는 이제 안 씀, 근무명 칩용 상수만 남김.
        private const val NEUTRAL_CHIP_COLOR = 0xFF9E9E9E.toInt() // 근무 스케줄 미설정 등 예외용 회색
        private const val CHIP_TEXT_DARK = "#FF212121"
        private const val CHIP_TEXT_LIGHT = "#FFFFFFFF"

        fun requestUpdate(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, SleepWidgetProvider::class.java))
                if (ids.isEmpty()) return
                for (id in ids) {
                    try {
                        manager.updateAppWidget(id, buildRemoteViews(context, widgetWidthDp(manager.getAppWidgetOptions(id))))
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 위젯($id) 렌더링 실패", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯 갱신 요청 실패", e)
            }
        }

        /** 런처가 알려준 현재 위젯 폭(dp). 못 받으면 2x1 최소 폭으로 가정. */
        private fun widgetWidthDp(options: Bundle?): Int {
            val w = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
            return if (w > 0) w else DEFAULT_WIDGET_WIDTH_DP
        }

        private fun buildRemoteViews(context: Context, widthDp: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.sleep_widget)

            // ⭐ 칩이 차지할 수 있는 최대 폭 = 안쪽 폭의 약 42%. 나머지는 수면/기상 버튼이 나눠 쓰므로
            // 좁은 화면에서 칩이 커져 버튼을 밀어내는 일이 없다(하한 34dp: "주간" 같은 두 글자는 항상 들어감).
            val chipMaxDp = ((widthDp - 15) * 0.42f).coerceIn(34f, 64f)
            val (shiftLabel, shiftColor) = shiftChip(context)
            views.setImageViewBitmap(
                R.id.sleep_shift_chip_bg,
                roundedChipBitmap(context, shiftColor, shiftLabel, chipTextColorFor(shiftColor), chipMaxDp)
            )

            // ⭐ 2026-09-13 - "컨디션 화면 사용하지 않기"로 그 탭을 숨기면, 이
            // 위젯이 그 탭으로 들어가는 우회 경로가 되어버림(main.dart의
            // DisableTabButton 주석 참고 - 사용자 지적). 탭이 꺼져 있으면
            // 위젯 전체를 반투명(비활성 느낌)으로 바꾸고, 버튼도 눌러도
            // 반응 없게 만들며, 상태 줄에 이유를 적어준다.
            if (!isConditionTabEnabled(context)) {
                renderDisabled(context, views)
                return views
            }
            views.setFloat(R.id.sleep_widget_root, "setAlpha", 1f)

            // ⭐ 2026-09-18 - "상태(활동중/수면중)" 줄 자체를 없앰(사용자 요청 - 위젯이
            // 커진 만큼 근무명·버튼 두 요소만 크게 보여주는 쪽을 택함). 다만 "지금 자고
            // 있다고 볼 수 있는가"는 여전히 계산해서 버튼 강조(sleeping)에만 쓴다.
            val state = currentSleepingState(context)

            // ⭐ 지금 의미 있는 쪽 버튼(수면 중이면 "기상", 아니면 "수면")을 강조색으로,
            // 반대쪽은 회색으로 - 지금 상태와 무엇을 눌러야 하는지를 명확히 함.
            val sleeping = state != SleepingState.NONE
            views.setInt(
                R.id.sleep_button_sleep, "setBackgroundResource",
                if (sleeping) R.drawable.sleep_widget_button_bg_inactive else R.drawable.sleep_widget_button_bg
            )
            views.setInt(
                R.id.sleep_button_wake, "setBackgroundResource",
                if (sleeping) R.drawable.sleep_widget_button_bg else R.drawable.sleep_widget_button_bg_inactive
            )

            views.setOnClickPendingIntent(R.id.sleep_button_sleep, actionPendingIntent(context, ACTION_SLEEP, 1))
            views.setOnClickPendingIntent(R.id.sleep_button_wake, actionPendingIntent(context, ACTION_WAKE, 2))

            // ⭐ 2026-09-07 - 수면/기상 버튼 이외 영역을 탭하면 앱이 컨디션 탭으로
            // 바로 열리게(요청). 버튼 두 개가 이미 자기 영역에 각자
            // setOnClickPendingIntent를 갖고 있어서, 루트에 별도로 걸어도
            // RemoteViews가 알아서 "버튼 영역은 버튼 것, 나머지는 루트 것"으로
            // 나눠 처리한다(자식 클릭 영역이 항상 우선). 컨디션 탭의 실제 인덱스는
            // 로케일에 따라 달라져서(Dart main.dart의 _showConditionTab) 여기선
            // 고정 숫자를 못 보내고, kOpenConditionTabSentinel과 값이 같은
            // 음수(-2)를 보낸다 - Dart openTab 핸들러가 런타임에 진짜 인덱스로
            // 바꾼다.
            views.setOnClickPendingIntent(R.id.sleep_widget_root, openConditionTabPendingIntent(context))
            return views
        }

        // ⭐ Flutter shared_preferences 플러그인이 실제로 쓰는 그 파일/키를 그대로
        // 읽음(파일명 "FlutterSharedPreferences", 키는 전부 "flutter." 접두사 -
        // tab_visibility_provider.dart의 _kConditionTabEnabledKey와 반드시 같은
        // 이름이어야 함). CLAUDE.md의 "Flutter SharedPreferences와 Native
        // alarm_state(Device Protected)는 서로 다른 경로" 경고와는 별개 사안 -
        // 이건 Device Protected가 필요 없는 일반 홈 화면 위젯이라 평범한
        // SharedPreferences를 그대로 읽어도 됨(잠금 해제 전 알람처럼 반드시
        // 동작해야 하는 경로가 아님).
        private fun isConditionTabEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            return prefs.getBoolean("flutter.condition_tab_enabled", true)
        }

        private fun renderDisabled(context: Context, views: RemoteViews) {
            views.setFloat(R.id.sleep_widget_root, "setAlpha", 0.4f)
            // ⭐ 2026-09-18 - 상태 줄이 없어졌으니, "왜 흐릿한지"는 근무명 자리에 대신 적는다.
            // 2026-09-22 - 평소엔 라벨이 없어서(레이아웃에서 gone) 이 경우에만 보이게 한다.
            views.setTextViewText(R.id.sleep_shift_label, context.getString(R.string.sleep_widget_tab_off))
            views.setViewVisibility(R.id.sleep_shift_label, android.view.View.VISIBLE)
            views.setViewVisibility(R.id.sleep_shift_chip_bg, android.view.View.GONE)
            views.setInt(R.id.sleep_button_sleep, "setBackgroundResource", R.drawable.sleep_widget_button_bg_inactive)
            views.setInt(R.id.sleep_button_wake, "setBackgroundResource", R.drawable.sleep_widget_button_bg_inactive)
            // ⭐ onClickPendingIntent를 아예 안 걸어서(버튼/루트 전부) 탭해도
            // 반응이 없게 함 - RemoteViews는 매번 새로 만드므로 이전 갱신 때
            // 걸어둔 PendingIntent가 남아있을 걱정 없음(buildRemoteViews는
            // 항상 새 RemoteViews 인스턴스에서 시작).
        }

        private fun openConditionTabPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("openTab", -2) // kOpenConditionTabSentinel(Dart main.dart)과 반드시 같은 값
            }
            return PendingIntent.getActivity(
                context, 3, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun actionPendingIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, SleepWidgetActionReceiver::class.java).apply { this.action = action }
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        // ⭐ "오늘 근무명" 칩(텍스트, 배경색) - CalendarWidgetScheduleResolver(기존,
        // 수정 없음)를 읽기 전용으로 재사용. 2026-09-22 - "오늘 근무" 라벨을 없애고 근무명
        // 자체(주간/야간/휴무...)만 보여준다. 오늘 배정된 근무가 없으면(불규칙 근무의 빈 날 등)
        // "근무없음". 색은 그 근무명에 배정된 색(schedule.shiftColors - 달력탭/캘린더
        // 위젯과 동일한 소스).
        private fun shiftChip(context: Context): Pair<String, Int> {
            return try {
                val schedule = CalendarWidgetScheduleResolver.readSchedule(context) ?: return context.getString(R.string.sleep_widget_not_set) to NEUTRAL_CHIP_COLOR
                val today = Calendar.getInstance()
                val name = CalendarWidgetScheduleResolver.shiftForDate(schedule, today)
                if (name == UNSET_SENTINEL) return context.getString(R.string.sleep_widget_no_shift) to NEUTRAL_CHIP_COLOR
                val color = schedule.shiftColors[name] ?: NEUTRAL_CHIP_COLOR
                name to color
            } catch (e: Exception) {
                Log.e(TAG, "❌ 근무명 계산 실패", e)
                context.getString(R.string.sleep_widget_unknown) to NEUTRAL_CHIP_COLOR
            }
        }

        // ⭐ 2026-09-13(2차) - 원래는 "고정 크기 배경 비트맵(ImageView, fitXY) +
        // 별도 텍스트뷰(wrap_content)"를 겹쳐서 칩을 만들었는데(달력 위젯의
        // roundedPillBitmap과 같은 패턴을 따라함), 달력 위젯과 달리 이 칩은
        // 고정 폭 그리드 셀 안이 아니라 혼자 wrap_content로 떠 있어서 - 배경
        // 뷰와 글자 뷰가 "따로" wrap_content 크기를 계산하다 보니 기기/런처에
        // 따라 둘의 실제 크기가 어긋나 글자가 배경 밖으로 삐져나오거나(가로)
        // 위아래로 안 맞는(세로) 문제가 실측 확인됨(에뮬레이터+실기기 여러 대).
        // → 배경과 글자를 애초에 한 비트맵에 같이 그려서 "정렬이 어긋날 수
        // 있는 두 개의 뷰" 자체를 없앰 - 이 비트맵 하나의 실제 크기가 곧
        // ImageView의 wrap_content 크기가 되므로 항상 글자와 배경이 정확히
        // 일치함. 상태 칩(statusValue)도 예전에 같은 종류의 문제(런처 캐싱)로
        // 결국 칩 자체를 없앴던 전례가 있음(위 NEUTRAL_CHIP_COLOR 주석 참고) -
        // 이번엔 칩을 없애는 대신 이 방식으로 구조적으로 해결함.
        private fun roundedChipBitmap(
            context: Context,
            color: Int,
            text: String,
            textColor: Int,
            maxWidthDp: Float
        ): Bitmap {
            val density = context.resources.displayMetrics.density
            val scaledDensity = context.resources.displayMetrics.scaledDensity
            val paddingH = 5f * density
            val paddingV = 3f * density
            val maxWidth = maxWidthDp * density
            val maxTextWidth = maxWidth - paddingH * 2

            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = textColor
                this.isFakeBoldText = true
                this.textAlign = Paint.Align.LEFT
            }

            // ⭐ 2026-09-22 - 폭이 모자라면 말줄임 전에 글자부터 줄인다(11sp → 최소 9sp). "근무없음"
            // 같은 네 글자도 좁은 화면에서 끝까지 읽히게 하려는 것. 9sp에서도 넘칠 때만 "…"로 자른다.
            var sizeSp = 11f
            textPaint.textSize = sizeSp * scaledDensity
            while (textPaint.measureText(text) > maxTextWidth && sizeSp > 9f) {
                sizeSp -= 0.5f
                textPaint.textSize = sizeSp * scaledDensity
            }

            var fittedText = text
            var codePoints = fittedText.codePointCount(0, fittedText.length)
            while (textPaint.measureText(fittedText) > maxTextWidth && codePoints > 1) {
                codePoints--
                val end = text.offsetByCodePoints(0, codePoints)
                fittedText = text.substring(0, end) + "…"
            }

            val metrics = textPaint.fontMetrics
            val textWidth = textPaint.measureText(fittedText)
            val width = (textWidth + paddingH * 2).coerceAtMost(maxWidth).toInt().coerceAtLeast(1)
            val height = (metrics.descent - metrics.ascent + paddingV * 2).toInt().coerceAtLeast(1)

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // ⭐ 위 크기를 전부 실제 기기 밀도(density) 기준 px로 계산했으므로,
            // 이 비트맵의 density도 명시적으로 기기 밀도와 맞춰야 ImageView가
            // wrap_content로 다시 확대/축소하지 않고 그린 그대로의 크기로 씀.
            bitmap.density = context.resources.displayMetrics.densityDpi
            val canvas = Canvas(bitmap)
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            // 알약 모양(수면/기상 버튼과 같은 결) - 반지름 = 높이의 절반.
            val radius = height / 2f
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, bgPaint)
            // ⭐ 텍스트를 세로 중앙에 정확히 배치 - baseline = 상단 여백 + 글자 자체의
            // ascent 크기(음수라 빼줌). 가로는 여백 안에서 가운데 정렬.
            val baseline = paddingV - metrics.ascent
            canvas.drawText(fittedText, (width - textWidth) / 2f, baseline, textPaint)
            return bitmap
        }

        // ⭐ CalendarWidgetProvider.pillTextColorFor와 동일 공식(shift_schedule.dart의
        // isBright()/getTextColor()와도 동일 - luminance 200 초과면 밝은 배경으로 판단).
        private fun chipTextColorFor(bgColor: Int): Int {
            val r = Color.red(bgColor)
            val g = Color.green(bgColor)
            val b = Color.blue(bgColor)
            val luminance = r * 0.299 + g * 0.587 + b * 0.114
            return Color.parseColor(if (luminance > 200) CHIP_TEXT_DARK else CHIP_TEXT_LIGHT)
        }

        /**
         * ⭐ MANUAL 진행 중이면 [SleepingState.MANUAL], 없고 AUTO_DETECTED 진행 중이면
         * [SleepingState.AUTO], 둘 다 없으면 [SleepingState.NONE]. MANUAL이 항상 우선
         * (수면기록_자동추정_설계.md 0장 원칙과 동일선상).
         */
        fun currentSleepingState(context: Context): SleepingState {
            val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry() ?: return SleepingState.NONE
            return try {
                if (hasOngoing(db, "MANUAL")) SleepingState.MANUAL
                else if (hasOngoing(db, "AUTO_DETECTED")) SleepingState.AUTO
                else SleepingState.NONE
            } catch (e: Exception) {
                Log.e(TAG, "❌ 수면 중 여부 확인 실패", e)
                SleepingState.NONE
            }
        }

        private fun hasOngoing(db: SQLiteDatabase, source: String): Boolean {
            return db.query(
                "sleep_records", arrayOf("id"),
                "source = ? AND end_time IS NULL", arrayOf(source), null, null, null, "1"
            ).use { it.moveToFirst() }
        }

        // ⭐ 2026-09-05 - "위젯 상태에 시간(오늘 수면 N시간)까지 나오니, 기상 직후
        // 한동안 뜨는 그 요약이 오히려 헷갈린다"는 지적으로 단순화함. 실제 있었던
        // 문제: 이 "오늘 수면 (N시간)"은 순수하게 "가장 최근에 위젯으로 완료한
        // 수면 기록 하나"만 보고 판단하는데(날짜/근무 연관성은 전혀 안 봄), 컨디션
        // 탭(sleep_shift_relation.dart)은 그 수면을 "어제 야간의 주 수면"으로
        // 정확히 분류해서 오늘 몫으로 안 셈 - 같은 기록을 두 화면이 서로 다른
        // 기준으로 설명해서 모순되게 보였음(위젯 "오늘 수면 3시간58분" vs 컨디션
        // 탭 "오늘 수면 미기록"). 두 화면 기준을 억지로 맞추는 대신, 위젯은 원래
        // 목적(지금 자고 있는지 아닌지 빨리 확인)에만 집중하도록 "활동중"/"수면중"
        // (자동감지면 "수면중(추정)") 세 문구만 남기고 소요시간 표시 자체를 없앰
        // (요청: "상태 그냥 활동중, 수면중 그 두개만 보이고 몇시간 잤는지는 안
        // 보이게"). 그날 실제 수면시간/근무 연관 분류는 여전히 컨디션 탭·"최근
        // 수면 기록" 미니 달력이 정확하게 보여줌 - 그쪽만 보면 됨.
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            try {
                appWidgetManager.updateAppWidget(
                    id, buildRemoteViews(context, widgetWidthDp(appWidgetManager.getAppWidgetOptions(id)))
                )
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯($id) onUpdate 렌더링 실패", e)
            }
        }
    }

    /**
     * ⭐ 2026-09-22 - 런처가 위젯 크기를 바꿔 알려줄 때(화면 회전, 그리드 설정 변경 등) 칩 폭을
     * 새 폭에 맞춰 다시 그린다. 칩은 고정 px 비트맵이라 이걸 안 하면 폭이 줄었을 때 버튼을 민다.
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        try {
            appWidgetManager.updateAppWidget(appWidgetId, buildRemoteViews(context, widgetWidthDp(newOptions)))
        } catch (e: Exception) {
            Log.e(TAG, "❌ 위젯($appWidgetId) 크기 변경 렌더링 실패", e)
        }
    }
}
