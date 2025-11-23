package com.example.shiftbell

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CustomAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_SOUND_TYPE = "soundType"
        const val EXTRA_LABEL = "label"
        const val EXTRA_ID = "id"
        const val CHANNEL_ID = "alarm_channel"
    }
    
    // CustomAlarmReceiver.kt - onReceive() 수정

override fun onReceive(context: Context, intent: Intent) {
    Log.e("CustomAlarmReceiver", "========== 알람 수신! ==========")

    val soundType = intent.getStringExtra(EXTRA_SOUND_TYPE) ?: "loud"
    val label = intent.getStringExtra(EXTRA_LABEL) ?: "알람"
    val id = intent.getIntExtra(EXTRA_ID, 0)

    Log.e("CustomAlarmReceiver", "ID: $id, Label: $label")

    // ⭐ 알람 발생 시 기존 Notification 삭제 (Overlay와 충돌 방지)
    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(8888)  // 20분 전 알림 삭제
    notificationManager.cancel(id)    // 해당 알람 ID의 알림도 삭제
    Log.e("CustomAlarmReceiver", "📢 기존 Notification 삭제")

    // ⭐ 신규: 알람 울릴 때 즉시 갱신 체크!
    AlarmRefreshUtil.checkAndTriggerRefresh(context)
    
    // ⭐ 알람 이력 기록
    try {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.writableDatabase
        
        val cursor = db.query(
            "alarms",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null, null, null
        )
        
        if (cursor.moveToFirst()) {
            val scheduledTime = cursor.getString(cursor.getColumnIndexOrThrow("time"))
            val scheduledDate = cursor.getString(cursor.getColumnIndexOrThrow("date"))
            val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type"))
            
            cursor.close()
            
            val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            
            val historyValues = ContentValues().apply {
                put("alarm_id", id)
                put("scheduled_time", scheduledTime)
                put("scheduled_date", scheduledDate)
                put("actual_ring_time", now)
                put("dismiss_type", "ringing")
                put("snooze_count", 0)
                put("shift_type", shiftType)
                put("created_at", now)
            }
            
            db.insert("alarm_history", null, historyValues)
            Log.d("CustomAlarmReceiver", "✅ 알람 이력 기록: ID=$id")
        } else {
            cursor.close()
        }
        
        db.close()
    } catch (e: Exception) {
        Log.e("CustomAlarmReceiver", "❌ 알람 이력 기록 실패", e)
    }
    
    // 알람 재생
    AlarmPlayer.getInstance(context.applicationContext).playAlarm(soundType)
    
    // 화면 강제로 깨우기
    wakeUpScreen(context)
    
    // 잠금 상태 확인
    val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
    val isLocked = keyguardManager.isKeyguardLocked
    
    Log.e("CustomAlarmReceiver", "잠금 상태: ${if (isLocked) "잠금" else "해제"}")
    
    Handler(Looper.getMainLooper()).postDelayed({
        if (isLocked) {
            Log.e("CustomAlarmReceiver", "✅ 잠금 상태 - AlarmActivity 실행")
            showAlarmActivity(context, id, label)
        } else {
            if (canDrawOverlays(context)) {
                Log.e("CustomAlarmReceiver", "✅ 잠금 해제 - Overlay 표시")
                showOverlayWindow(context, id, label)
            } else {
                Log.e("CustomAlarmReceiver", "⚠️ Overlay 권한 없음 - Notification")
                showNotification(context, id, label)
            }
        }
    }, 500)
}
    
    private fun wakeUpScreen(context: Context) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "ShiftBell:AlarmWakeLock"
            )
            wakeLock.acquire(10000) // 10초
            
            Log.e("CustomAlarmReceiver", "✅ 화면 깨움")
        } catch (e: Exception) {
            Log.e("CustomAlarmReceiver", "❌ 화면 깨우기 실패", e)
        }
    }
    
    private fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(context)
        } else {
            true
        }
    }
    
    private fun showAlarmActivity(context: Context, id: Int, label: String) {
    // ⭐ DB에서 alarm_type_id 조회 → duration 가져오기
    val duration = try {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.readableDatabase
        
        // 1. alarms 테이블에서 alarm_type_id 조회
        val alarmCursor = db.query(
            "alarms",
            arrayOf("alarm_type_id"),
            "id = ?",
            arrayOf(id.toString()),
            null, null, null
        )
        
        var alarmTypeId = 1  // 기본값
        if (alarmCursor.moveToFirst()) {
            alarmTypeId = alarmCursor.getInt(0)
        }
        alarmCursor.close()
        
        // 2. alarm_types 테이블에서 duration 조회
        val typeCursor = db.query(
            "alarm_types",
            arrayOf("duration"),
            "id = ?",
            arrayOf(alarmTypeId.toString()),
            null, null, null
        )
        
        var durationValue = 1  // 기본값 (테스트용 1분)
        if (typeCursor.moveToFirst()) {
            durationValue = typeCursor.getInt(0)
        }
        typeCursor.close()
        db.close()

        durationValue
    } catch (e: Exception) {
        Log.e("CustomAlarmReceiver", "duration 조회 실패", e)
        1  // 에러 시 기본값 (테스트용 1분)
    }
    
    val activityIntent = Intent(context, AlarmActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                Intent.FLAG_ACTIVITY_CLEAR_TASK or
                Intent.FLAG_ACTIVITY_NO_USER_ACTION
        putExtra("alarmId", id)
        putExtra("label", label)
        putExtra("alarmDuration", duration)  // ⭐ 신규
    }
    
    try {
        context.startActivity(activityIntent)
        Log.e("CustomAlarmReceiver", "✅ AlarmActivity 시작 (duration=${duration}분)")
    } catch (e: Exception) {
        Log.e("CustomAlarmReceiver", "❌ AlarmActivity 시작 실패", e)
        showNotification(context, id, label)
    }
}
    
    private fun showOverlayWindow(context: Context, id: Int, label: String) {
        Log.e("CustomAlarmReceiver", "✅ Overlay 표시 시작")
        
        val overlayIntent = Intent(context, AlarmOverlayService::class.java).apply {
            putExtra("alarmId", id)
        }
        
        context.startService(overlayIntent)
    }
    
    private fun showNotification(context: Context, id: Int, label: String) {
        Log.e("CustomAlarmReceiver", "⚠️ Notification으로 폴백")
        
        val fullScreenIntent = Intent(context, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("alarmId", id)
        }
        
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            id,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // 채널 생성
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "알람",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "알람 알림"
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("알람")
            .setContentText(label)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setAutoCancel(true)
            .build()
        
        notificationManager.notify(id, notification)
        
        Log.e("CustomAlarmReceiver", "✅ Notification 표시")
    }
}