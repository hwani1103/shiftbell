package com.hwani1103.shiftbell

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ⭐ 실제 수면 기록 위젯의 취침/기상 버튼 처리("C번 요구사항"). 앱을 열지 않고
 * 그 자리에서 바로 sleep_records에 쓰고 위젯을 다시 그린다(스펙 2~3장 - 원터치로
 * 끝나야 함, Activity를 띄우지 않음).
 *
 * ⭐ 2026-09-01 - 토글(버튼 1개) 방식에서 "수면"/"기상" 버튼 2개로 재설계 -
 * ACTION_SLEEP/ACTION_WAKE 각각 명시적인 동작만 수행하고, 지금 상태와 안 맞는
 * 액션(예: 이미 수면 중인데 또 "수면"을 누름)은 조용히 무시한다(잘못된 이중
 * 기록 방지) - 위젯이 항상 지금 의미 있는 버튼을 강조색으로 보여주므로
 * (SleepWidgetProvider 참고) 실제로는 거의 발생하지 않는 경로.
 *
 * ⭐ 2026-09-01 추가 - "위젯을 스마트하게" 요청 반영:
 * 1. **자동 감지가 진행 중(AUTO_DETECTED)일 때 "수면"을 누르면 그냥 무시한다**
 *    (덮어쓰지 않음) - 자동 감지가 이미 잡아둔 더 정확한 취침 시작 시각(최대
 *    ±20분 오차, 첫 꺼짐 샘플로 소급됨)을 "지금 누른 시각"으로 새로 시작하는
 *    MANUAL 기록이 덮어써버리면 오히려 정확도가 떨어짐. "기상"을 누르면 그
 *    자동 감지 후보를 그대로 확정(CONFIRMED)해서 끝내는 게 더 정확함 - 앱을
 *    열어 "맞아요"를 누르는 것과 사실상 동일한 효과를 위젯에서 바로 준다.
 * 2. **너무 짧은(2분 미만) 수면은 저장하지 않고 버린다** - 위젯을 반복해서
 *    누르거나(연타), 실수로 "수면"→"기상"을 몇 초 안에 잇달아 누르는 경우
 *    같은 무의미한 기록이 쌓이는 걸 막기 위함. 버려질 때만 짧은 Toast로
 *    알려준다(정상 기록은 위젯 갱신만으로 충분히 보이므로 매번 Toast 안 띄움).
 *
 * ⚠️ 근무 중이든 아니든 검증 없이 항상 그대로 기록한다(수면기록_자동추정_설계.md
 * 2장 - "근무시간과 겹치는 수면 기록도 정상적으로 저장할 수 있어야 한다"는 원칙을
 * 위젯 경로에도 동일하게 적용) - 이건 "언제 잤는지" 검증이 아니라 "찰나의 실수
 * 탭"만 걸러내는 것이라 원칙과 충돌하지 않음.
 */
class SleepWidgetActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SleepWidgetActionReceiver"
        private const val ISO_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"

        // ⭐ MANUAL 기록 - 이보다 짧으면 "의미 있는 수면"으로 보지 않고 버린다
        // (연타/실수 탭 방지). 근거자료 값이 아니라 순수 UX 예외처리용.
        private const val MIN_MEANINGFUL_MINUTES = 2L

        // ⭐ 2026-09-01 후속4 - AUTO_DETECTED를 위젯에서 바로 확정(promoteToConfirmed)할
        // 때는 "메인 수면 최소 2시간" 기준(SleepDetectionReceiver.MIN_MAIN_SLEEP_MINUTES와
        // 동일 값 유지할 것)을 그대로 적용한다 - 자동 감지는 메인 잠 전용이므로
        // MANUAL의 2분 기준을 그대로 쓰면 너무 관대함.
        private const val MIN_MAIN_SLEEP_MINUTES = 120L
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val db = DatabaseHelper.getInstance(context).getWritableDatabaseWithRetry()
            if (db == null) {
                Log.w(TAG, "⚠️ DB 아직 준비 안 됨 - 버튼 입력 무시")
                return
            }

            val now = System.currentTimeMillis()
            val nowStr = SimpleDateFormat(ISO_FORMAT, Locale.US).format(Date(now))

            val ongoingManual = db.query(
                "sleep_records", arrayOf("id", "start_time"),
                "source = 'MANUAL' AND end_time IS NULL", null, null, null, null, "1"
            ).use { cursor -> if (cursor.moveToFirst()) Pair(cursor.getLong(0), cursor.getString(1)) else null }

            val ongoingAuto = db.query(
                "sleep_records", arrayOf("id", "start_time"),
                "source = 'AUTO_DETECTED' AND end_time IS NULL", null, null, null, null, "1"
            ).use { cursor -> if (cursor.moveToFirst()) Pair(cursor.getLong(0), cursor.getString(1)) else null }

            when (intent.action) {
                SleepWidgetProvider.ACTION_WAKE -> {
                    when {
                        ongoingManual != null -> finishOngoing(context, db, ongoingManual, nowStr, now, promoteToConfirmed = false)
                        ongoingAuto != null -> finishOngoing(context, db, ongoingAuto, nowStr, now, promoteToConfirmed = true)
                        else -> Log.d(TAG, "⏭️ 진행 중인 수면이 없어 기상 무시")
                    }
                }
                SleepWidgetProvider.ACTION_SLEEP -> {
                    when {
                        ongoingManual != null -> Log.d(TAG, "⏭️ 이미 수면 중이라 취침 무시 (id=${ongoingManual.first})")
                        // ⭐ 자동 감지가 잡아둔 더 정확한 시작 시각을 덮어쓰지 않기 위해 무시.
                        ongoingAuto != null -> Log.d(TAG, "⏭️ 이미 자동으로 수면 중 인식됨 - 취침 무시 (id=${ongoingAuto.first})")
                        else -> {
                            val values = ContentValues().apply {
                                put("start_time", nowStr)
                                putNull("end_time")
                                put("source", "MANUAL")
                                put("status", "CONFIRMED")
                                put("created_at", nowStr)
                                put("updated_at", nowStr)
                            }
                            val id = db.insert("sleep_records", null, values)
                            Log.d(TAG, "😴 취침 기록 (id=$id)")
                        }
                    }
                }
                else -> return
            }

            SleepWidgetProvider.requestUpdate(context)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 위젯 버튼 처리 실패", e)
        }
    }

    /**
     * 진행 중이던 레코드([ongoing] = id, start_time)를 [nowStr]에 종료한다.
     * [promoteToConfirmed](자동 감지 후보를 위젯에서 바로 마무리하는 경우)에 따라
     * 최소 길이 기준이 다르다 - MANUAL은 [MIN_MEANINGFUL_MINUTES](2분, 연타 방지),
     * AUTO 확정은 [MIN_MAIN_SLEEP_MINUTES](2시간, "메인 잠 전용" 기준). 미만이면
     * 저장하지 않고 아예 삭제한다. [promoteToConfirmed]가 true면 status도 CONFIRMED로
     * 같이 바꿔서 앱의 "맞아요" 확인을 다시 거치지 않게 한다.
     */
    private fun finishOngoing(
        context: Context,
        db: android.database.sqlite.SQLiteDatabase,
        ongoing: Pair<Long, String>,
        nowStr: String,
        nowMillis: Long,
        promoteToConfirmed: Boolean
    ) {
        val (id, startStr) = ongoing
        val startMillis = parseIso(startStr)
        val durationMinutes = if (startMillis != null) (nowMillis - startMillis) / 60_000L else Long.MAX_VALUE
        val minMinutes = if (promoteToConfirmed) MIN_MAIN_SLEEP_MINUTES else MIN_MEANINGFUL_MINUTES

        if (durationMinutes < minMinutes) {
            db.delete("sleep_records", "id = ?", arrayOf(id.toString()))
            Log.d(TAG, "🗑️ 너무 짧아서(${durationMinutes}분) 기록 버림 (id=$id, 확정시도=$promoteToConfirmed)")
            Toast.makeText(context, "너무 짧아서 기록하지 않았어요", Toast.LENGTH_SHORT).show()
            return
        }

        val values = ContentValues().apply {
            put("end_time", nowStr)
            if (promoteToConfirmed) {
                put("status", "CONFIRMED")
            } else {
                // ⭐ 2026-09-04 - 위젯 🌙/☀️ 버튼으로 직접 기록한 것(앱 다이얼로그에서
                // 시각을 타이핑한 것과 구분)임을 완료 시점에 표시해둠 - 진행 중일 때는
                // 여전히 "MANUAL"이라 SleepWidgetProvider.hasOngoing()/ongoingStartMillis()
                // 등 기존 "source='MANUAL' AND end_time IS NULL" 조회는 전혀 안 바뀜.
                // (2026-09-04엔 이 값 기준으로 Dart 쪽 표시를 10분 단위로 반올림했었으나
                // 2026-09-05에 원복 - sleep_format_util.dart 참고. source 구분 자체는
                // 계속 유지 - "어느 경로로 기록됐는지" 이력 정보라 표시 방식과 무관하게 남겨둠.)
                put("source", "WIDGET_MANUAL")
            }
            put("updated_at", nowStr)
        }
        db.update("sleep_records", values, "id = ?", arrayOf(id.toString()))
        Log.d(TAG, "☀️ 기상 기록 (id=$id, 확정=$promoteToConfirmed)")
    }

    private fun parseIso(s: String?): Long? {
        if (s == null) return null
        return try {
            SimpleDateFormat(ISO_FORMAT, Locale.US).parse(s)?.time
        } catch (e: Exception) {
            null
        }
    }
}
