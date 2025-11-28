// android/app/src/main/kotlin/com/example/shiftbell/NotificationHelper.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

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

    /**
     * 스누즈 결과 Notification 표시 (8889)
     * 1. 기존 8888 삭제
     * 2. 8889 표시
     * 3. 30초 후 자동 삭제 예약
     * 4. AlarmGuardReceiver.triggerCheck() 호출
     */
    fun showUpdatedNotification(
        context: Context,
        newTimeStr: String,
        label: String
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 1단계: 기존 8888 삭제
        notificationManager.cancel(8888)
        Log.d("NotificationHelper", "🗑️ 8888 Notification 삭제")

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
            .setSmallIcon(android.R.drawable.ic_dialog_info)
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
