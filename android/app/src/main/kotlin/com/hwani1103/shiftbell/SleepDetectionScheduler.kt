package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * ⭐ 실제 수면 기록/자동 추정("C번 요구사항") - 화면 on/off를 상시 감시하는 대신,
 * "수면 가능 시간대"에만 [AlarmManager]로 20분 간격 주기적 샘플링을 예약한다
 * (수면기록_자동추정_조사.md 3장 "채택한 아키텍처" 참고). 기존 `AlarmGuardReceiver`가
 * 이미 쓰는 것과 똑같은 정확한 알람 방식이라 배터리/OS 정책 리스크가 새로 생기지
 * 않는다.
 *
 * 항상 [ensureScheduled]만 호출하면 됨 - 내부에서 알아서 "지금 창 안인지/창 시작
 * 전인지/오늘은 창이 없는지"를 판단해 딱 하나의 다음 알람만 예약한다(같은
 * PendingIntent로 다시 예약하면 이전 예약이 자동으로 대체됨 - 별도 cancel 불필요).
 */
object SleepDetectionScheduler {
    private const val TAG = "SleepDetectionScheduler"
    private const val REQUEST_CODE = 0x53_4C_45_50 // "SLEP"의 대략적 hex, 다른 알람과 충돌 방지용 고유 코드
    private const val SAMPLE_INTERVAL_MINUTES = 20L

    // ⭐ 2026-09-22(영어화 P0-2) - 수면·회복 탭(Flutter condition_tab.dart)은 한국어 로케일에서만
    // 존재하고(main.dart _showConditionTab) 그 탭이 꺼져 있으면(설정 → "수면·회복 화면 사용하지
    // 않기") 기록을 볼 방법도 없다. 그런데 이 스케줄러는 그 둘과 무관하게 항상 20분마다 기기를
    // 깨워 sleep_records에 기록해 왔음 - 영어 사용자는 자기가 쓰지도 보지도 못하는 기능이 매일 밤
    // 배터리를 쓰고 데이터를 쌓고 있었던 것(개인정보처리방침에도 없는 상태로 수집되는 셈). 로케일이
    // 한국어가 아니거나 탭이 꺼져 있으면 예약하지 않고, 이미 잡혀 있던 다음 체크도 취소한다.
    // SleepWidgetProvider.isConditionTabEnabled와 같은 파일/키를 읽음(Flutter shared_preferences
    // 플러그인 - DP 아닌 일반 prefs, 잠금 해제 전이라 아직 못 읽으면 기본값 true로 안전하게 폴백).
    fun isSleepDetectionEnabled(context: Context): Boolean {
        if (Locale.getDefault().language != "ko") return false
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.condition_tab_enabled", true)
    }

    fun ensureScheduled(context: Context) {
        if (!isSleepDetectionEnabled(context)) {
            cancel(context)
            return
        }
        try {
            val now = System.currentTimeMillis()
            val window = SleepScheduleResolver.computeWindowForNow(context, now)

            val windowWakeMillis = when {
                window != null && now >= window.startMillis && now < window.endMillis ->
                    now + SAMPLE_INTERVAL_MINUTES * 60_000L
                window != null && now < window.startMillis -> window.startMillis
                else -> nextMidnightCheckMillis()
            }

            // 감지 창이 먼저 닫혀도 진행 중 AUTO_DETECTED 행의 start+9h에는 반드시
            // 다시 판정한다. 기한은 prefs에 복제하지 않고 매번 DB 행에서 파생한다.
            val candidateDeadline = SleepDetectionReceiver.ongoingAutoDeadlineMillis(context)
            val nextWakeMillis = if (candidateDeadline == null) {
                windowWakeMillis
            } else {
                minOf(windowWakeMillis, candidateDeadline.coerceAtLeast(now + 1_000L))
            }

            schedule(context, nextWakeMillis)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 수면 감지 예약 실패", e)
        }
    }

    // ⭐ 오늘은 수면 가능 시간대 자체가 없거나(스케줄 미설정 등) 이미 지난 경우의
    // 가벼운 백스톱 - 자정 직후 재판단해서 다음날 창이 생기면 그때부터 다시 돎.
    private fun nextMidnightCheckMillis(): Long {
        return Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 5)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun schedule(context: Context, atMillis: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = buildPendingIntent(context)
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent)
        Log.d(TAG, "⏰ 수면 감지 다음 체크 예약: ${Date(atMillis)}")
    }

    /** 감지를 완전히 멈출 때(위 [isSleepDetectionEnabled]가 false일 때 [ensureScheduled]가 호출). */
    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(buildPendingIntent(context))
    }

    private fun buildPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, SleepDetectionReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
