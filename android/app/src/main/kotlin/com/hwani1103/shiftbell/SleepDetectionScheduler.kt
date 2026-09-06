package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar
import java.util.Date

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

    fun ensureScheduled(context: Context) {
        try {
            val now = System.currentTimeMillis()
            val window = SleepScheduleResolver.computeWindowForNow(context, now)

            val nextWakeMillis = when {
                window != null && now >= window.startMillis && now < window.endMillis ->
                    now + SAMPLE_INTERVAL_MINUTES * 60_000L
                window != null && now < window.startMillis -> window.startMillis
                else -> nextMidnightCheckMillis()
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

    /** 재부팅 등으로 완전히 멈춰야 할 때만 사용(1차 버전에선 호출부 없음 - 항상
     * ensureScheduled가 알아서 최신 상태로 재예약하므로 명시적 정지가 필요 없음).
     * 향후 "자동 감지 끄기" 설정이 생기면 이 함수를 호출하면 됨. */
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
