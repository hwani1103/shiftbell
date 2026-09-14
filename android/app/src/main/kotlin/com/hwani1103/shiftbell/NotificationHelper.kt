// android/app/src/main/kotlin/com/example/shiftbell/NotificationHelper.kt

package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Notification 관련 공통 유틸리티
 * - showUpdatedNotification: 스누즈 결과 Notification 표시
 * - scheduleNotificationDeletion: 30초 후 8889 자동 삭제
 */
object NotificationHelper {

    private const val CHANNEL_ID = "shiftbell_result_v3"
    private const val CHANNEL_NAME = "결과 알림"
    private const val NOTIFICATION_ID_SNOOZE = 8889
    private const val DELETE_REQUEST_CODE = 9999
    private const val TAG = "NotificationHelper"

    /** 울리는 중인 알람의 제어 알림 ID (한 번에 한 울림만 있으므로 고정) */
    const val RING_CONTROL_ID = 7777

    /**
     * 스누즈 결과 Notification 표시 (8889)
     * 1. 8889 표시
     * 2. 30초 후 자동 삭제 예약
     * 3. AlarmGuardReceiver.triggerCheck() 호출 (8888은 그 안에서 전담 갱신됨)
     */
    fun showUpdatedNotification(
        context: Context,
        newTimeStr: String,
        label: String
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ⭐ 8888은 AlarmGuardReceiver가 전담 (아래 triggerCheck가 재계산함) - 여기서 직접 cancel하지 않음

        // 채널 생성 ("알람" 키워드 제거 - 삼성 시스템 스누즈 방지)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "스누즈/타임아웃 결과"
                enableVibration(false)
                setSound(null, null)
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("openTab", 0)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2단계: 8889 표시 (스누즈 결과)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("$newTimeStr 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)  // ⭐ 알람시계 아이콘
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setGroup("shiftbell_notifications")  // 삼성 시스템 스누즈 방지
            .setGroupSummary(false)
            .setLocalOnly(true)  // 삼성 시스템 스누즈 방지
            .setStyle(NotificationCompat.BigTextStyle().bigText(label))  // 삼성 시스템 스누즈 방지
            .setContentIntent(openAppPendingIntent)
            .build()

        notificationManager.notify(NOTIFICATION_ID_SNOOZE, notification)
        Log.d("NotificationHelper", "📢 8889 Notification 표시: $newTimeStr")

        // 3단계: 30초 후 8889 자동 삭제 예약
        scheduleNotificationDeletion(context)

        // 4단계: 다음 알람의 8888 Notification 표시
        AlarmGuardReceiver.triggerCheck(context)
        Log.d("NotificationHelper", "✅ AlarmGuardReceiver.triggerCheck() → 다음 알람 8888 표시")
    }

    /**
     * ⭐ 2026-09-14 (출시전 감사 #4) - 울리는 즉시 게시하고 울림이 끝날 때까지 유지하는 제어 알림(7777).
     *
     * 예전엔 끌 수단이 화면(잠금화면 AlarmActivity/해제 상태 오버레이)뿐이었음:
     *  - 잠금 상태에서 백그라운드 Activity 실행이 예외 없이 조용히 막히면 폴백도 안 타서 소리만 남음
     *  - 오버레이 권한이 없을 때의 폴백 알림엔 끄기/스누즈 버튼이 없었음
     *  - 7777은 잠금화면에서 홈을 눌렀을 때만 게시됐음
     * 이제 CustomAlarmReceiver가 소리와 동시에 이 알림을 올리고(전체화면 인텐트 + 탭하면 알람 화면 +
     * 끄기/5분 후 버튼), 화면·오버레이는 그다음에 시도함. 알림은 끄기·스누즈·인계·타임아웃에서만 지움
     * (AlarmActionHelper.closeRingUi 등) - 화면이 떠도 지우지 않아 홈으로 나가도 제어 수단이 남음.
     * 버튼은 전부 (ID, 회차)를 담아 #3 회차 관문(AlarmActionHelper.claimRingEnd)을 통과함.
     * 알림 권한까지 꺼져 있으면 보이지 않음 → 그 경우의 끄기 수단은 화면·오버레이와 #3 자동 종료뿐(잔여 위험).
     * 삼성 "시스템 스누즈" 회피용 설정(CATEGORY_CALL·그룹·localOnly·BigTextStyle, 채널명에 "알람" 없음)은
     * 기존 폴백 알림 그대로 유지.
     */
    fun showRingControlNotification(context: Context, alarmId: Int, round: Long, label: String, durationMinutes: Int) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 게시 전 상태 점검 - 막혀 있어도 게시는 시도하고(권한이 나중에 켜질 수 있음) 로그로 원인을 남김
        try {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                Log.w(TAG, "⚠️ 알림 권한 꺼짐 - 제어 알림이 안 보임(끄기 수단은 화면·오버레이·자동 종료뿐)")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                !notificationManager.canUseFullScreenIntent()) {
                Log.w(TAG, "⚠️ 전체화면 알림 허용 안 됨 - 잠금 상태에서 알람 화면이 자동으로 안 뜰 수 있음")
            }
        } catch (e: Exception) {
            Log.w(TAG, "알림 상태 점검 실패", e)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CustomAlarmReceiver.CHANNEL_ID,
                "Shiftbell",  // ⭐ "알람" 제거 (삼성 시스템 스누즈 방지)
                NotificationManager.IMPORTANCE_HIGH  // fullScreenIntent를 위해 HIGH 유지
            ).apply {
                description = "근무 시간 알림"
                enableVibration(false)
                setSound(null, null)  // 알림 자체는 무음 - 소리는 AlarmPlayer
            }
            notificationManager.createNotificationChannel(channel)
            val current = notificationManager.getNotificationChannel(CustomAlarmReceiver.CHANNEL_ID)
            if (current != null && current.importance == NotificationManager.IMPORTANCE_NONE) {
                Log.w(TAG, "⚠️ 알람 알림 채널이 사용자 설정으로 차단됨 - 제어 알림이 안 보임")
            }
        }

        val screenIntent = Intent(context, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
            putExtra("alarmId", alarmId)
            putExtra("label", label)
            putExtra("alarmDuration", durationMinutes)
            putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
        }
        val screenPendingIntent = PendingIntent.getActivity(
            context, alarmId, screenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val dismissPendingIntent = PendingIntent.getBroadcast(
            context, alarmId + 10000,
            Intent(context, AlarmActionReceiver::class.java).apply {
                action = AlarmActionReceiver.ACTION_DISMISS_FROM_NOTIFICATION
                putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context, alarmId + 20000,
            Intent(context, AlarmActionReceiver::class.java).apply {
                action = AlarmActionReceiver.ACTION_SNOOZE_FROM_NOTIFICATION
                putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CustomAlarmReceiver.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("알람 울림 중")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)  // ⭐ 삼성 시스템 스누즈 방지, full-screen 지원
            .setFullScreenIntent(screenPendingIntent, true)
            .setContentIntent(screenPendingIntent)
            // 알림을 치우는 것도 "알람 확인"(끄기)으로 취급 - 기존 7777과 같은 규칙
            .setDeleteIntent(dismissPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setGroup("shiftbell_notifications")  // ⭐ 삼성 시스템 스누즈 방지
            .setGroupSummary(false)
            .setLocalOnly(true)  // ⭐ 삼성 시스템 스누즈 방지
            .setStyle(NotificationCompat.BigTextStyle().bigText("알람 울림 중"))  // ⭐ 삼성 시스템 스누즈 방지
            .addAction(android.R.drawable.ic_lock_idle_alarm, "5분 후", snoozePendingIntent)
            .addAction(android.R.drawable.ic_delete, "알람 끄기", dismissPendingIntent)
            .build()

        try {
            notificationManager.notify(RING_CONTROL_ID, notification)
            Log.d(TAG, "✅ 제어 알림 게시: id=$alarmId 회차=$round")
        } catch (e: Exception) {
            // Android 13+ 알림 권한 미허용 등
            Log.e(TAG, "❌ 제어 알림 게시 실패: id=$alarmId", e)
        }
    }

    /**
     * 30초 후 8889 Notification 자동 삭제 예약
     */
    private fun scheduleNotificationDeletion(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val deleteIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_DELETE_SNOOZE_NOTIFICATION
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            DELETE_REQUEST_CODE,
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val deleteTime = System.currentTimeMillis() + 30_000  // 30초 후

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExact(AlarmManager.RTC, deleteTime, pendingIntent)
        } else {
            alarmManager.set(AlarmManager.RTC, deleteTime, pendingIntent)
        }

        Log.d("NotificationHelper", "⏰ 30초 후 8889 삭제 예약")
    }
}
