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
                // ⭐ 테스트용: Native last_alarm_refresh 리셋
                "resetNativeRefreshFlag" -> {
                    resetNativeRefreshFlag()
                    result.success(null)
                }
                // ⭐ 테스트용: Native 갱신 강제 실행
                "forceNativeRefresh" -> {
                    forceNativeRefresh()
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
                // ⭐ Overlay 종료 (외부에서 알람 끄기)
                "dismissOverlay" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val intent = Intent(AlarmOverlayService.ACTION_DISMISS_OVERLAY).apply {
                        setPackage(packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                        putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                    }
                    sendBroadcast(intent)
                    Log.d("MainActivity", "📡 Overlay DISMISS 브로드캐스트 발송: ID=$alarmId")
                    result.success(null)
                }
                // ⭐ Overlay 스누즈 (외부에서 알람 5분 후)
                "snoozeOverlay" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val intent = Intent(AlarmOverlayService.ACTION_SNOOZE_OVERLAY).apply {
                        setPackage(packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                        putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                    }
                    sendBroadcast(intent)
                    Log.d("MainActivity", "📡 Overlay SNOOZE 브로드캐스트 발송: ID=$alarmId")
                    result.success(null)
                }
                // ⭐ 진동 테스트 (설정 화면에서 미리보기)
                "testVibration" -> {
                    val strength = call.argument<Int>("strength") ?: 1
                    testVibration(strength)
                    result.success(null)
                }
                // ⭐ 알람 음량 미리듣기 (STREAM_ALARM 사용)
                "playPreviewSound" -> {
                    val soundFile = call.argument<String>("soundFile") ?: "alarmbell1"
                    val volume = call.argument<Double>("volume")?.toFloat() ?: 0.7f
                    playPreviewSound(soundFile, volume)
                    result.success(null)
                }
                // ⭐ 미리듣기 중지
                "stopPreviewSound" -> {
                    stopPreviewSound()
                    result.success(null)
                }
                // ⭐ 미리듣기 볼륨 변경 (슬라이더 실시간 반영)
                "updatePreviewVolume" -> {
                    val volume = call.argument<Double>("volume")?.toFloat() ?: 0.7f
                    updatePreviewVolume(volume)
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

    // ⭐ 테스트용: Native SharedPreferences의 last_alarm_refresh 리셋
    private fun resetNativeRefreshFlag() {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            createDeviceProtectedStorageContext()
        } else {
            applicationContext
        }
        val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        prefs.edit().putLong("last_alarm_refresh", 0L).apply()
        Log.d("MainActivity", "✅ Native last_alarm_refresh 리셋 완료")
    }

    // ⭐ 테스트용: Native 갱신 강제 실행 (리셋 후 트리거)
    private fun forceNativeRefresh() {
        resetNativeRefreshFlag()
        val intent = Intent("com.example.shiftbell.REFRESH_ALARMS").apply {
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d("MainActivity", "✅ Native 갱신 강제 실행 완료")
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

        // ⭐ 스누즈 Notification은 정보만 표시 (버튼 없음)
        val notification = NotificationCompat.Builder(this, "twenty_min_channel")
            .setContentTitle("알람이 $newTime 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setSilent(true)
            .setContentIntent(openAppPendingIntent)
            .build()
        
        notificationManager.notify(8889, notification)  // ⭐ 8889: 스누즈/타임아웃 전용 (20분전 8888과 공존)

        Log.d("MainActivity", "📢 Notification 업데이트: $newTime")
    }

    // ⭐ 진동 테스트 (약 1초간)
    private fun testVibration(strength: Int) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator

        // 진동 패턴 (1초간)
        val pattern = when(strength) {
            1 -> longArrayOf(0, 500, 200, 300)   // 약하게: 짧은 진동
            3 -> longArrayOf(0, 800, 200)        // 강하게: 긴 진동
            else -> longArrayOf(0, 500)
        }

        // 진동 세기
        val amplitude = when(strength) {
            1 -> 100   // 약하게
            3 -> 255   // 강하게 (최대)
            else -> 150
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val amplitudes = pattern.map { if (it == 0L) 0 else amplitude }.toIntArray()
            vibrator.vibrate(
                android.os.VibrationEffect.createWaveform(pattern, amplitudes, -1)  // -1 = 반복 안함
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }

        Log.d("MainActivity", "🔔 진동 테스트: 세기=$strength")
    }

    // ⭐ 미리듣기용 MediaPlayer
    private var previewMediaPlayer: android.media.MediaPlayer? = null

    // ⭐ 알람 음량 미리듣기 (STREAM_ALARM 사용 - 실제 알람과 동일)
    private fun playPreviewSound(soundFile: String, volume: Float) {
        stopPreviewSound()  // 기존 재생 중지

        try {
            // 시스템 알람 볼륨을 최대로 설정 (실제 알람과 동일)
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            val maxVolume = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM)
            audioManager.setStreamVolume(android.media.AudioManager.STREAM_ALARM, maxVolume, 0)

            // res/raw 리소스 ID 가져오기
            val resourceId = resources.getIdentifier(soundFile, "raw", packageName)

            if (resourceId == 0) {
                Log.e("MainActivity", "리소스 못 찾음: res/raw/$soundFile.mp3")
                return
            }

            val soundUri = android.net.Uri.parse("android.resource://$packageName/$resourceId")

            previewMediaPlayer = android.media.MediaPlayer().apply {
                setDataSource(this@MainActivity, soundUri)

                // 핵심: STREAM_ALARM 사용 (실제 알람과 동일)
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )

                // 음량 설정 (슬라이더 값)
                setVolume(volume, volume)

                isLooping = false  // 미리듣기는 반복 안 함
                prepare()
                start()
            }

            Log.d("MainActivity", "🔊 미리듣기 재생: $soundFile, 음량 ${(volume * 100).toInt()}%")

        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 미리듣기 재생 실패", e)
        }
    }

    // ⭐ 미리듣기 중지
    private fun stopPreviewSound() {
        previewMediaPlayer?.apply {
            if (isPlaying) {
                stop()
            }
            release()
        }
        previewMediaPlayer = null
        Log.d("MainActivity", "🔇 미리듣기 중지")
    }

    // ⭐ 미리듣기 볼륨 변경 (슬라이더 실시간 반영)
    private fun updatePreviewVolume(volume: Float) {
        previewMediaPlayer?.setVolume(volume, volume)
        Log.d("MainActivity", "🔊 미리듣기 볼륨 변경: ${(volume * 100).toInt()}%")
    }
}