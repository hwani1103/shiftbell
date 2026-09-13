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
                        manager.updateAppWidget(id, buildRemoteViews(context))
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 위젯($id) 렌더링 실패", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯 갱신 요청 실패", e)
            }
        }

        private fun buildRemoteViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.sleep_widget)

            val (shiftLabel, shiftColor) = shiftChip(context)
            views.setImageViewBitmap(
                R.id.sleep_shift_chip_bg,
                roundedChipBitmap(context, shiftColor, shiftLabel, chipTextColorFor(shiftColor))
            )

            // ⭐ 2026-09-13 - "컨디션 화면 사용하지 않기"로 그 탭을 숨기면, 이
            // 위젯이 그 탭으로 들어가는 우회 경로가 되어버림(main.dart의
            // DisableTabButton 주석 참고 - 사용자 지적). 탭이 꺼져 있으면
            // 위젯 전체를 반투명(비활성 느낌)으로 바꾸고, 버튼도 눌러도
            // 반응 없게 만들며, 상태 줄에 이유를 적어준다.
            if (!isConditionTabEnabled(context)) {
                renderDisabled(views)
                return views
            }
            views.setFloat(R.id.sleep_widget_root, "setAlpha", 1f)

            val state = currentSleepingState(context)
            val (statusLabel, statusDuration) = statusValue(state)
            views.setTextViewText(R.id.sleep_status_value_text, statusLabel)
            views.setTextViewText(R.id.sleep_status_duration_text, statusDuration)

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

        private fun renderDisabled(views: RemoteViews) {
            views.setFloat(R.id.sleep_widget_root, "setAlpha", 0.4f)
            views.setTextViewText(R.id.sleep_status_value_text, "컨디션 탭")
            views.setTextViewText(R.id.sleep_status_duration_text, "활성화 후 사용 가능")
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
        // 수정 없음)를 읽기 전용으로 재사용. 라벨("오늘 근무")은 이제 레이아웃
        // XML에 고정 텍스트로 있고, 여기선 칩 값(근무명)과 그 근무명에 배정된
        // 색(schedule.shiftColors - 달력탭/캘린더 위젯과 동일한 소스)만 계산.
        private fun shiftChip(context: Context): Pair<String, Int> {
            return try {
                val schedule = CalendarWidgetScheduleResolver.readSchedule(context) ?: return "미설정" to NEUTRAL_CHIP_COLOR
                val today = Calendar.getInstance()
                val name = CalendarWidgetScheduleResolver.shiftForDate(schedule, today)
                if (name == UNSET_SENTINEL) return "미배정" to NEUTRAL_CHIP_COLOR
                val color = schedule.shiftColors[name] ?: NEUTRAL_CHIP_COLOR
                name to color
            } catch (e: Exception) {
                Log.e(TAG, "❌ 근무명 계산 실패", e)
                "정보 없음" to NEUTRAL_CHIP_COLOR
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
        private fun roundedChipBitmap(context: Context, color: Int, text: String, textColor: Int): Bitmap {
            val density = context.resources.displayMetrics.density
            val textSizePx = 11f * context.resources.displayMetrics.scaledDensity
            val paddingH = 8f * density
            val paddingV = 2f * density
            val radius = 6f * density

            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = textColor
                this.textSize = textSizePx
                this.isFakeBoldText = true
                this.textAlign = Paint.Align.LEFT
            }
            val metrics = textPaint.fontMetrics
            val textWidth = textPaint.measureText(text)
            val width = (textWidth + paddingH * 2).toInt().coerceAtLeast(1)
            val height = (metrics.descent - metrics.ascent + paddingV * 2).toInt().coerceAtLeast(1)

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // ⭐ 위 크기를 전부 실제 기기 밀도(density) 기준 px로 계산했으므로,
            // 이 비트맵의 density도 명시적으로 기기 밀도와 맞춰야 ImageView가
            // wrap_content로 다시 확대/축소하지 않고 그린 그대로의 크기로 씀.
            bitmap.density = context.resources.displayMetrics.densityDpi
            val canvas = Canvas(bitmap)
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, bgPaint)
            // ⭐ 텍스트를 세로 중앙에 정확히 배치 - baseline = 상단 여백 + 글자 자체의
            // ascent 크기(음수라 빼줌). 가로는 왼쪽 여백만큼만 띄우면 됨(Align.LEFT).
            val baseline = paddingV - metrics.ascent
            canvas.drawText(text, paddingH, baseline, textPaint)
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
        private fun statusValue(state: SleepingState): Pair<String, String> {
            val label = when (state) {
                SleepingState.MANUAL -> "수면중"
                SleepingState.AUTO -> "수면중(추정)"
                SleepingState.NONE -> "활동중"
            }
            return label to ""
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            try {
                appWidgetManager.updateAppWidget(id, buildRemoteViews(context))
            } catch (e: Exception) {
                Log.e(TAG, "❌ 위젯($id) onUpdate 렌더링 실패", e)
            }
        }
    }
}
