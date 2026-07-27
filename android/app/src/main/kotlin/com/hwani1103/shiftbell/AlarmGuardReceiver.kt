// AlarmGuardReceiver.kt

package com.hwani1103.shiftbell

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
        private const val TWENTY_MIN_CHANNEL_ID = "shiftbell_pre_v3"  // ⭐ 채널 ID 변경 + "알람" 키워드 제거
        private val shownNotifications = java.util.Collections.synchronizedSet(mutableSetOf<Int>())

        fun removeShownNotification(alarmId: Int) {
            shownNotifications.remove(alarmId)
            Log.d("AlarmGuardReceiver", "🗑️ Notification 이력 제거: ID=$alarmId")
        }

        // ⭐ Flutter 경로에서 알람 삭제 시 전체 초기화 (유령 Notification 방지)
        fun clearAllShownNotifications() {
            shownNotifications.clear()
            Log.d("AlarmGuardReceiver", "🗑️ shownNotifications 전체 초기화")
        }

        // ⭐ 직접 호출용 정적 메서드 (sendBroadcast 없이도 동작)
        fun triggerCheck(context: Context) {
            Log.d("AlarmGuardReceiver", "⏰ 직접 트리거")

            // 갱신 체크
            AlarmRefreshUtil.checkAndTriggerRefresh(context)

            // 다음 알람 체크 + 8888 상태 갱신
            val instance = AlarmGuardReceiver()
            val nextAlarm = instance.getNextAlarmFromDB(context)
            instance.updateTwentyMinuteNotification(context, nextAlarm)

            // 다음 Wakeup 예약
            instance.scheduleNextWakeup(context)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmGuardReceiver", "⏰ Wakeup 수신")

        // ⭐ 신규: 갱신 체크 & 실행 (Native에서 직접!)
        AlarmRefreshUtil.checkAndTriggerRefresh(context)

        // 다음 알람 체크 + 8888 상태 갱신 (20분 이내면 표시, 아니면 정리)
        val nextAlarm = getNextAlarmFromDB(context)
        updateTwentyMinuteNotification(context, nextAlarm)

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
    
    // ⭐ CRITICAL FIX: 8888(20분 전 알림)의 표시/유지/취소를 여기 한 곳에서만 결정함.
    // 예전엔 AlarmActivity/Overlay의 끄기·타임아웃, Dart의 cancelNotification 등
    // 여러 곳에서 "일단 8888 지우기"를 산발적으로 했는데, 8888은 특정 알람 전용이
    // 아니라 "지금 시점에 20분 이내로 가장 가까운 알람"을 가리키는 공용 슬롯이라,
    // 알람 A를 끄면서 8888을 지웠는데 그게 사실 알람 B(다른 가까운 알람)의 정당한
    // 리마인더였던 경우 B의 리마인더가 통째로 사라지고 다시 안 뜨는 버그가 있었음
    // (shownNotifications에 B가 이미 있다고 기록되어 있어서 재표시도 안 됐음).
    // 이제 "지울지 말지"까지 이 함수가 매번 최신 상태 기준으로 다시 결정함.
    private fun updateTwentyMinuteNotification(context: Context, alarm: AlarmData?) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (alarm == null) {
            notificationManager.cancel(TWENTY_MIN_NOTIFICATION_ID)
            return
        }

        val now = System.currentTimeMillis()
        val timeUntil = alarm.timestamp - now

        if (timeUntil <= 0 || timeUntil > 20 * 60 * 1000) {
            // 다음 알람이 아직 20분 밖이거나 이미 지났으면 지금 보여줄 게 없음
            notificationManager.cancel(TWENTY_MIN_NOTIFICATION_ID)
            return
        }

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
    
    // ⭐ 정보 표시 전용 (탭하면 앱만 열림). 예전엔 여기에 끄기/5분후 버튼이 있었는데,
    // 아직 울리지도 않은 알람을 제어하는 경로가 달력/다음알람 탭과 겹쳐서 버그가 잦았음.
    // 실제 끄기/스누즈는 알람이 울리는 상태(AlarmActivity/Overlay, 필요시 7777 알림)에서만 가능함.
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

        val notification = NotificationCompat.Builder(context, TWENTY_MIN_CHANNEL_ID)
            .setContentTitle("잠시 후 알람이 울립니다 (${alarm.time})")
            .setContentText(alarm.shiftType)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)  // ⭐ STATUS 사용 (삼성 시스템 스누즈 완전 방지)
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)  // ⭐ 시스템 스누즈 버튼 제거
            .setGroup("shiftbell_notifications")  // ⭐ 그룹 설정 (삼성 시스템 스누즈 방지)
            .setGroupSummary(false)
            .setLocalOnly(true)  // ⭐ 로컬 전용 (삼성 시스템 스누즈 방지)
            .setStyle(NotificationCompat.BigTextStyle().bigText(alarm.shiftType))  // ⭐ 스타일 설정 (삼성 시스템 스누즈 방지)
            .setContentIntent(openAppPendingIntent)
            .build()

        notificationManager.notify(TWENTY_MIN_NOTIFICATION_ID, notification)

        Log.d("AlarmGuardReceiver", "📢 20분 전 알림 표시: ${alarm.time}")
    }
    
    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // ⭐ 무음 Notification: 소리/진동 없이 조용하게 표시
            val channel = NotificationChannel(
                TWENTY_MIN_CHANNEL_ID,
                "사전 알림",  // ⭐ "알람" 키워드 제거 (삼성 시스템 스누즈 방지)
                NotificationManager.IMPORTANCE_LOW  // 소리/진동 없음
            ).apply {
                description = "20분 전 사전 알림"
                enableVibration(false)
                setSound(null, null)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun getNextAlarmFromDB(context: Context): AlarmData? {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.getReadableDatabaseWithRetry() ?: return null  // ⭐ 재시도 로직 사용

            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.getDefault()
            ).format(Date())

            cursor = db.query(
                "alarms",
                null,
                "date > ?",
                arrayOf(now),
                null,
                null,
                "date ASC, id ASC",  // ⭐ 동일 시각일 때 낮은 ID 우선
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

            alarm
        } catch (e: Exception) {
            Log.e("AlarmGuardReceiver", "DB 읽기 실패", e)
            null
        } finally {
            cursor?.close()
            db?.close()
        }
    }
    
    data class AlarmData(
        val id: Int,
        val timestamp: Long,
        val time: String,
        val shiftType: String
    )
}