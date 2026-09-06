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
            views.setImageViewBitmap(R.id.sleep_shift_chip_bg, roundedChipBitmap(shiftColor))
            views.setTextViewText(R.id.sleep_shift_chip_text, shiftLabel)
            views.setTextColor(R.id.sleep_shift_chip_text, chipTextColorFor(shiftColor))

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
            return views
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

        // ⭐ 근무색 칩과 동일한 방식(달력 위젯의 roundedPillBitmap과 같은 패턴) -
        // ImageView가 fitXY로 늘려 채우므로 작은 고정 크기로 그려도 문제 없음.
        private fun roundedChipBitmap(color: Int): Bitmap {
            val width = 100
            val height = 50
            val radius = 12f
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, paint)
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
