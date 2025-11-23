// AlarmGuardReceiver.kt

package com.example.shiftbell

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.*

class AlarmGuardReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TWENTY_MIN_NOTIFICATION_ID = 8888
        private const val TWENTY_MIN_CHANNEL_ID = "twenty_min_channel"
        private val shownNotifications = mutableSetOf<Int>()
        
        fun removeShownNotification(alarmId: Int) {
            shownNotifications.remove(alarmId)
            Log.d("AlarmGuardReceiver", "🗑️ Notification 이력 제거: ID=$alarmId")
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmGuardReceiver", "⏰ Wakeup 수신")
        
        // ⭐ 신규: 갱신 체크 & 실행 (Native에서 직접!)
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        
        // 다음 알람 체크 (20분 이내면 Notification)
        val nextAlarm = getNextAlarmFromDB(context)
        
        if (nextAlarm != null) {
            checkAndNotify(context, nextAlarm)
        }
        
        // 다음 Wakeup 예약
        scheduleNextWakeup(context)
    }
    
    private fun scheduleNextWakeup(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val nextAlarm = getNextAlarmFromDB(context)
        
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        
        val now = System.currentTimeMillis()
        
        if (nextAlarm == null) {
            Log.d("AlarmGuardReceiver", "⚠️ 알람 없음 - 자정 체크 예약: ${Date(midnight)}")
            scheduleWakeup(context, alarmManager, midnight)
            return
        }
        
        val wakeupTime = nextAlarm.timestamp - (20 * 60 * 1000)
        
        if (wakeupTime <= now) {
            Log.d("AlarmGuardReceiver", "⚠️ 이미 20분 이내 - 5분 후 재체크")
            scheduleWakeup(context, alarmManager, now + 5 * 60 * 1000)
        } else if (midnight < wakeupTime) {
            Log.d("AlarmGuardReceiver", "⏰ 자정 체크 예약: ${Date(midnight)}")
            scheduleWakeup(context, alarmManager, midnight)
        } else {
            Log.d("AlarmGuardReceiver", "⏰ 20분 전 예약: ${Date(wakeupTime)}")
            scheduleWakeup(context, alarmManager, wakeupTime)
        }
    }
    
    private fun scheduleWakeup(context: Context, alarmManager: AlarmManager, wakeupTime: Long) {
        val intent = Intent(context, AlarmGuardReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                wakeupTime,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                wakeupTime,
                pendingIntent
            )
        }
        
        Log.d("AlarmGuardReceiver", "✅ 다음 Wakeup 예약: ${Date(wakeupTime)}")
    }
    
    private fun checkAndNotify(context: Context, alarm: AlarmData) {
        val now = System.currentTimeMillis()
        val timeUntil = alarm.timestamp - now
        
        if (timeUntil > 0 && timeUntil <= 20 * 60 * 1000) {
            Log.d("AlarmGuardReceiver", "🔍 알람 20분 이내: ${alarm.time} (${alarm.shiftType})")
            
            if (!isAlarmScheduled(context, alarm.id)) {
                Log.e("AlarmGuardReceiver", "❌ 알람 누락! 재등록")
                reScheduleAlarm(context, alarm)
            } else {
                Log.d("AlarmGuardReceiver", "✅ 알람 정상")
            }
            
            if (shownNotifications.contains(alarm.id)) {
                Log.d("AlarmGuardReceiver", "⏭️ Notification 스킵 (이미 표시함)")
            } else {
                show20MinuteNotification(context, alarm)
                shownNotifications.add(alarm.id)
                Log.d("AlarmGuardReceiver", "✅ Notification 표시 (ID: ${alarm.id})")
            }
        }
    }
    
    private fun isAlarmScheduled(context: Context, alarmId: Int): Boolean {
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        
        return pendingIntent != null
    }
    
    private fun reScheduleAlarm(context: Context, alarm: AlarmData) {
        try {
            val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                data = android.net.Uri.parse("shiftbell://alarm/${alarm.id}")
                putExtra(CustomAlarmReceiver.EXTRA_ID, alarm.id)
                putExtra(CustomAlarmReceiver.EXTRA_LABEL, alarm.shiftType)
                putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                alarm.id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    alarm.timestamp,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    alarm.timestamp,
                    pendingIntent
                )
            }
            
            Log.d("AlarmGuardReceiver", "✅ 알람 재등록 완료: ID=${alarm.id}")
        } catch (e: Exception) {
            Log.e("AlarmGuardReceiver", "❌ 알람 재등록 실패", e)
        }
    }
    
    private fun show20MinuteNotification(context: Context, alarm: AlarmData) {
        createNotificationChannel(context)
        
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
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
        
        val cancelIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = "CANCEL_ALARM"
            putExtra("alarmId", alarm.id)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, alarm.shiftType)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            alarm.id + 10000,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val extendIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = "EXTEND_ALARM"
            putExtra("alarmId", alarm.id)
            putExtra("timestamp", alarm.timestamp)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, alarm.shiftType)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
        }
        val extendPendingIntent = PendingIntent.getBroadcast(
            context,
            alarm.id + 20000,
            extendIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(context, TWENTY_MIN_CHANNEL_ID)
            .setContentTitle("잠시 후 알람이 울립니다 (${alarm.time})")
            .setContentText(alarm.shiftType)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(openAppPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "끄기", cancelPendingIntent)
            .addAction(android.R.drawable.ic_menu_add, "5분 후", extendPendingIntent)
            .build()
        
        notificationManager.notify(TWENTY_MIN_NOTIFICATION_ID, notification)
        
        Log.d("AlarmGuardReceiver", "📢 20분 전 알림 표시: ${alarm.time}")
    }
    
    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            val channel = NotificationChannel(
                TWENTY_MIN_CHANNEL_ID,
                "알람 사전 알림",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "알람 20분 전 알림"
                enableVibration(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun getNextAlarmFromDB(context: Context): AlarmData? {
        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase
            
            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.getDefault()
            ).format(Date())
            
            val cursor = db.query(
                "alarms",
                null,
                "date > ?",
                arrayOf(now),
                null,
                null,
                "date ASC",
                "1"
            )
            
            var alarm: AlarmData? = null
            
            if (cursor.moveToFirst()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                val dateStr = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                
                val timestamp = SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss",
                    Locale.getDefault()
                ).parse(dateStr)?.time
                
                if (timestamp != null) {
                    val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp))
                    alarm = AlarmData(id, timestamp, time, shiftType)
                }
            }
            
            cursor.close()
            db.close()
            
            alarm
        } catch (e: Exception) {
            Log.e("AlarmGuardReceiver", "DB 읽기 실패", e)
            null
        }
    }
    
    data class AlarmData(
        val id: Int,
        val timestamp: Long,
        val time: String,
        val shiftType: String
    )
}