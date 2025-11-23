// android/app/src/main/kotlin/com/example/shiftbell/MainActivity.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import androidx.core.app.NotificationCompat


class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.shiftbell/alarm"
    private var methodChannel: MethodChannel? = null
    
    // ⭐ 갱신 요청 수신용 Receiver
    private val refreshReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MainActivity", "📡 Flutter UI 갱신 요청")
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            methodChannel?.invokeMethod("refreshAlarms", null)
        }, 300)
    }
}
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // ⭐ BroadcastReceiver 등록
        val filter = IntentFilter("com.example.shiftbell.FLUTTER_REFRESH")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(refreshReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(refreshReceiver, filter)
        }
        Log.d("MainActivity", "✅ RefreshReceiver 등록 완료")
        
        handleStopAlarmIntent(intent)
        handleOpenTabIntent(intent)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(refreshReceiver)
            Log.d("MainActivity", "✅ RefreshReceiver 해제")
        } catch (e: Exception) {
            Log.e("MainActivity", "RefreshReceiver 해제 실패", e)
        }
    }
    
    // ✅ 변경
override fun onResume() {
    super.onResume()
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        methodChannel?.invokeMethod("refreshAlarms", null)
    }, 300)
}
    
    // ✅ 변경
override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    handleStopAlarmIntent(intent)
    handleOpenTabIntent(intent)
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        methodChannel?.invokeMethod("refreshAlarms", null)
    }, 300)
}
    
    // ⭐ 알림 탭 시 다음알람 탭으로 이동
    private fun handleOpenTabIntent(intent: Intent?) {
        val tabIndex = intent?.getIntExtra("openTab", -1) ?: -1
        if (tabIndex >= 0) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("openTab", tabIndex)
            }
        }
    }
    
    
    private fun handleStopAlarmIntent(intent: Intent?) {
        when (intent?.action) {
            "STOP_ALARM" -> {
                val notificationId = intent.getIntExtra("notificationId", 0)
                
                AlarmPlayer.getInstance(applicationContext).stopAlarm()
                
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
                
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAlarmStopped", notificationId)
                }
            }
            "SNOOZE_ALARM" -> {
                val notificationId = intent.getIntExtra("notificationId", 0)
                
                AlarmPlayer.getInstance(applicationContext).stopAlarm()
                
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
                
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAlarmSnoozed", notificationId)
                }
            }
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleGuardWakeup" -> {
                    scheduleGuardWakeup()
                    result.success(null)
                }
                "getDeviceProtectedStoragePath" -> {
                    val path = getDeviceProtectedStoragePath()
                    result.success(path)
                }
                "scheduleNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val timestamp = call.argument<Long>("timestamp") ?: 0L
                    val label = call.argument<String>("label") ?: "알람"
                    val soundType = call.argument<String>("soundType") ?: "loud"
                    
                    scheduleNativeAlarm(id, timestamp, label, soundType)
                    result.success(null)
                }
                "cancelNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    cancelNativeAlarm(id)
                    result.success(null)
                }
                "stopAlarm" -> {
                    AlarmPlayer.getInstance(applicationContext).stopAlarm()
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "checkOverlayPermission" -> {
                    val hasPermission = checkOverlayPermission()
                    result.success(hasPermission)
                }
                "triggerMidnightCheck" -> {
                    triggerMidnightCheck()
                    result.success(null)
                }
                "triggerGuardCheck" -> {
                    triggerGuardCheck()
                    result.success(null)
                }
                "updateNotification" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val newTime = call.argument<String>("newTime") ?: ""
                    val label = call.argument<String>("label") ?: "알람"
                    updateExistingNotification(alarmId, newTime, label)
                    result.success(null)
                }
                // ⭐ 신규 추가
"cancelNotification" -> {
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(8888)
    Log.d("MainActivity", "📢 Notification 삭제 (ID: 8888)")
    result.success(null)
}
                else -> result.notImplemented()
            }
        }
    }
    
    // ⭐ AlarmGuardReceiver 초기 예약
    private fun scheduleGuardWakeup() {
        val intent = Intent(this, AlarmGuardReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val midnight = java.util.Calendar.getInstance().apply {
            add(java.util.Calendar.DAY_OF_MONTH, 1)
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                midnight,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                midnight,
                pendingIntent
            )
        }
    }
    
    private fun triggerMidnightCheck() {
        val intent = Intent(this, AlarmGuardReceiver::class.java)
        sendBroadcast(intent)
    }
    
    private fun triggerGuardCheck() {
        val intent = Intent(this, AlarmGuardReceiver::class.java)
        sendBroadcast(intent)
        Log.d("MainActivity", "✅ AlarmGuardReceiver 수동 트리거")
    }
    
    private fun getDeviceProtectedStoragePath(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val deviceProtectedContext = createDeviceProtectedStorageContext()
            deviceProtectedContext.getDatabasePath("shiftbell.db").absolutePath
        } else {
            getDatabasePath("shiftbell.db").absolutePath
        }
    }
    
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
        }
    }
    
    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
    
    private fun scheduleNativeAlarm(id: Int, timestamp: Long, label: String, soundType: String) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val intent = Intent(this, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$id")
            putExtra(CustomAlarmReceiver.EXTRA_ID, id)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent
            )
        }
    }
    
    private fun cancelNativeAlarm(id: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$id")
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }
    
    // ⭐ 신규: Notification 업데이트 함수
    private fun updateExistingNotification(alarmId: Int, newTime: String, label: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "twenty_min_channel",
                "알람 사전 알림",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "알람 20분 전 알림"
                enableVibration(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("openTab", 0)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val cancelIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = "CANCEL_ALARM"
            putExtra("alarmId", alarmId)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId + 10000,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // ⭐ 새 timestamp 계산 (현재 시간 기준)
        val timeParts = newTime.split(":")
        val now = java.util.Calendar.getInstance()
        val newTimestamp = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, timeParts[0].toInt())
            set(java.util.Calendar.MINUTE, timeParts[1].toInt())
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
            
            // 시간이 과거면 다음날로
            if (timeInMillis < now.timeInMillis) {
                add(java.util.Calendar.DAY_OF_MONTH, 1)
            }
        }.timeInMillis
        
        val extendIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = "EXTEND_ALARM"
            putExtra("alarmId", alarmId)
            putExtra("timestamp", newTimestamp)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
        }
        val extendPendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId + 20000,
            extendIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, "twenty_min_channel")
            .setContentTitle("알람이 $newTime 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "끄기", cancelPendingIntent)
            .addAction(android.R.drawable.ic_menu_add, "5분 후", extendPendingIntent)
            .build()
        
        notificationManager.notify(8888, notification)
        
        Log.d("MainActivity", "📢 Notification 업데이트: $newTime")
    }
}