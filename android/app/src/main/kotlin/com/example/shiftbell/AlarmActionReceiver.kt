// android/app/src/main/kotlin/com/example/shiftbell/AlarmActionReceiver.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("alarmId", 0)
        
        when (intent.action) {
            "CANCEL_ALARM" -> {
                Log.d("AlarmAction", "🗑️ 알람 취소: ID=$alarmId")
                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"

                // ⭐ Overlay가 울리고 있을 수 있으므로 종료 신호 발송
                val dismissIntent = Intent(AlarmOverlayService.ACTION_DISMISS_OVERLAY).apply {
                    setPackage(context.packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                    putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                }
                context.sendBroadcast(dismissIntent)
                Log.d("AlarmAction", "📡 Overlay DISMISS 브로드캐스트 발송")

                cancelAlarm(context, alarmId, label, soundType)

                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8888)
            }
            "EXTEND_ALARM" -> {
                val timestamp = intent.getLongExtra("timestamp", 0L)
                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"
                Log.d("AlarmAction", "⏰ 알람 5분 연장: ID=$alarmId")

                // ⭐ Overlay가 울리고 있을 수 있으므로 종료 신호 발송
                val snoozeIntent = Intent(AlarmOverlayService.ACTION_SNOOZE_OVERLAY).apply {
                    setPackage(context.packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                    putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                }
                context.sendBroadcast(snoozeIntent)
                Log.d("AlarmAction", "📡 Overlay SNOOZE 브로드캐스트 발송")

                extendAlarm(context, alarmId, timestamp, label, soundType)
            }
        }
    }
    
    private fun cancelAlarm(context: Context, alarmId: Int, label: String, soundType: String) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    
    val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
        data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
        putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
        putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
        putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
    }
    
    val pendingIntent = PendingIntent.getBroadcast(
        context,
        alarmId,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    alarmManager.cancel(pendingIntent)
    
    Log.d("AlarmAction", "✅ Native 알람 취소 완료: ID=$alarmId")
    
    try {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.writableDatabase
        db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        db.close()
        Log.d("AlarmAction", "✅ DB 알람 삭제 완료: ID=$alarmId")

        // ⭐ shownNotifications에서 제거 (다음 알람 Notification 표시 위해)
        AlarmGuardReceiver.removeShownNotification(alarmId)

        // ⭐ 수정: AlarmRefreshWorker → AlarmRefreshUtil
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        Log.d("AlarmAction", "✅ 갱신 체크 완료")

        val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
        context.sendBroadcast(guardIntent)
        Log.d("AlarmAction", "✅ AlarmGuardReceiver 즉시 재실행")
        
    } catch (e: Exception) {
        Log.e("AlarmAction", "❌ DB 삭제 실패", e)
    }
}
    
    private fun extendAlarm(context: Context, alarmId: Int, originalTimestamp: Long, label: String, soundType: String) {
        val newTimestamp = originalTimestamp + (5 * 60 * 1000)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val cancelIntent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(cancelPendingIntent)
        cancelPendingIntent.cancel()
        Log.d("AlarmAction", "✅ 기존 알람 취소: ID=$alarmId")
        
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
            putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                newTimestamp,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                newTimestamp,
                pendingIntent
            )
        }
        
        Log.d("AlarmAction", "✅ 알람 5분 연장 완료: ID=$alarmId, 새 시각=${java.util.Date(newTimestamp)}")
        
        try {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.writableDatabase
        
        val calendar = java.util.Calendar.getInstance().apply {
            timeInMillis = newTimestamp
        }
        
        val dateStr = java.text.SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss",
            java.util.Locale.getDefault()
        ).format(java.util.Date(newTimestamp))
        
        val timeStr = java.text.SimpleDateFormat(
            "HH:mm",
            java.util.Locale.getDefault()
        ).format(java.util.Date(newTimestamp))
        
        val values = android.content.ContentValues().apply {
            put("date", dateStr)
            put("time", timeStr)
        }
        
        val rowsAffected = db.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))
        db.close()
        
        Log.d("AlarmAction", "✅ DB 업데이트 완료: ID=$alarmId, time=$timeStr, date=$dateStr, rows=$rowsAffected")

        // ⭐ 수정: AlarmRefreshWorker → AlarmRefreshUtil
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        Log.d("AlarmAction", "✅ 갱신 체크 완료")

        val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
        context.sendBroadcast(guardIntent)
        Log.d("AlarmAction", "✅ AlarmGuardReceiver 즉시 재실행")

        // ⭐ Notification 업데이트 (연장되었습니다 표시)
        showUpdatedNotification(context, alarmId, newTimestamp, timeStr, label, soundType)
        Log.d("AlarmAction", "✅ Notification 업데이트 완료")

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        context.startActivity(launchIntent)
        Log.d("AlarmAction", "✅ 앱 포그라운드 이동")

    } catch (e: Exception) {
        Log.e("AlarmAction", "❌ DB 업데이트 실패", e)
    }
    }
    
    private fun showUpdatedNotification(
        context: Context,
        alarmId: Int,
        newTimestamp: Long,
        newTimeStr: String,
        label: String,
        soundType: String
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // ⭐ 무음 Notification 채널
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "twenty_min_channel",
                "알람 사전 알림",
                NotificationManager.IMPORTANCE_LOW  // 소리/진동 없음
            ).apply {
                description = "알람 20분 전 알림"
                enableVibration(false)
                setSound(null, null)
                setShowBadge(true)
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

        // ⭐ 스누즈 Notification은 정보만 표시 (버튼 없음)
        val notification = NotificationCompat.Builder(context, "twenty_min_channel")
            .setContentTitle("알람이 $newTimeStr 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setSilent(true)
            .setContentIntent(openAppPendingIntent)
            .build()
        
        notificationManager.notify(8889, notification)  // ⭐ 8889: 스누즈/타임아웃 전용 (20분전 8888과 공존)

        Log.d("AlarmAction", "📢 Notification 업데이트: $newTimeStr")
    }
}