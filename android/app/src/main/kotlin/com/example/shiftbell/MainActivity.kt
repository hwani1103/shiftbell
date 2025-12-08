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
        // ⭐ 윈도우 배경을 즉시 설정 (wallpaper 노출 방지)
        window.setBackgroundDrawableResource(android.R.color.transparent)

        super.onCreate(savedInstanceState)

        // ⭐ BroadcastReceiver 등록은 onResume으로 이동 예정
        val filter = IntentFilter("com.example.shiftbell.FLUTTER_REFRESH")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(refreshReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(refreshReceiver, filter)
        }
        Log.d("MainActivity", "✅ RefreshReceiver 등록 완료")

        // ⭐ Intent 처리는 나중에 (윈도우 표시 후)
        window.decorView.post {
            handleStopAlarmIntent(intent)
            handleOpenTabIntent(intent)
        }
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
    notificationManager.cancel(8888)  // 20분 전 알림
    notificationManager.cancel(8889)  // 스누즈/타임아웃 알림
    Log.d("MainActivity", "📢 Notification 삭제 (ID: 8888, 8889)")
    result.success(null)
}
                // ⭐ 모든 Notification 삭제
                "cancelAllNotifications" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                    Log.d("MainActivity", "🗑️ 모든 Notification 삭제 완료")
                    result.success(null)
                }
                // ⭐ shownNotifications 전체 초기화 (유령 Notification 방지)
                "clearShownNotifications" -> {
                    AlarmGuardReceiver.clearAllShownNotifications()
                    Log.d("MainActivity", "🗑️ shownNotifications 전체 초기화 완료")
                    result.success(null)
                }
                // ⭐ AlarmGuardReceiver 취소
                "cancelAlarmGuard" -> {
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val intent = Intent(this, AlarmGuardReceiver::class.java)
                    val pendingIntent = PendingIntent.getBroadcast(
                        this,
                        999999, // AlarmGuardReceiver의 고유 ID
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarmManager.cancel(pendingIntent)
                    pendingIntent.cancel()
                    Log.d("MainActivity", "🗑️ AlarmGuardReceiver 취소 완료")
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
                // ⭐ 알람이 울리는 중인지 확인
                "isAlarmRinging" -> {
                    val isRinging = AlarmPlayer.getInstance(applicationContext).isAlarmRinging()
                    result.success(isRinging)
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
        // ⭐ sendBroadcast 대신 직접 호출 (더 확실하게 동작)
        AlarmGuardReceiver.triggerCheck(this)
        Log.d("MainActivity", "✅ AlarmGuardReceiver 직접 트리거")
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

        // ⭐ 알람 등록 후 AlarmGuardReceiver 직접 트리거 (20분 이내면 Notification 표시)
        AlarmGuardReceiver.triggerCheck(this)
        Log.d("MainActivity", "✅ 알람 등록 완료: ID=$id, AlarmGuardReceiver 직접 트리거")
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

        // ⭐ shownNotifications에서 제거 (같은 ID 재사용 시 notification 표시 위해)
        AlarmGuardReceiver.removeShownNotification(id)
        Log.d("MainActivity", "✅ 알람 취소 및 shownNotifications 제거: ID=$id")
    }
    
    // ⭐ 신규: Notification 업데이트 함수 (Flutter에서 스누즈 시 호출)
    private fun updateExistingNotification(alarmId: Int, newTime: String, label: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ⭐ 1단계: 기존 8888 삭제
        notificationManager.cancel(8888)
        Log.d("MainActivity", "🗑️ 8888 Notification 삭제")

        // ⭐ 스누즈 결과 전용 채널 ("알람" 키워드 제거 - 삼성 시스템 스누즈 방지)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "shiftbell_result_v3",
                "결과 알림",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "스누즈/타임아웃 결과"
                enableVibration(false)
                setSound(null, null)
                setShowBadge(false)
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

        // ⭐ 2단계: 8889 표시 (스누즈 결과)
        val notification = NotificationCompat.Builder(this, "shiftbell_result_v3")
            .setContentTitle("$newTime 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setGroup("shiftbell_notifications")  // ⭐ 그룹 설정 (삼성 시스템 스누즈 방지)
            .setGroupSummary(false)
            .setLocalOnly(true)  // ⭐ 로컬 전용 (삼성 시스템 스누즈 방지)
            .setStyle(NotificationCompat.BigTextStyle().bigText(label))  // ⭐ 스타일 설정 (삼성 시스템 스누즈 방지)
            .setContentIntent(openAppPendingIntent)
            .build()

        notificationManager.notify(8889, notification)
        Log.d("MainActivity", "📢 8889 Notification 표시: $newTime")

        // ⭐ 3단계: 30초 후 8889 자동 삭제 예약
        scheduleNotificationDeletion()

        // ⭐ 4단계: 다음 알람의 8888 Notification 표시
        AlarmGuardReceiver.triggerCheck(this)
        Log.d("MainActivity", "✅ AlarmGuardReceiver.triggerCheck() → 다음 알람 8888 표시")
    }

    private fun scheduleNotificationDeletion() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val deleteIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_DELETE_SNOOZE_NOTIFICATION
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            9999,  // 고정 requestCode (8889 삭제 전용)
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val deleteTime = System.currentTimeMillis() + 30_000  // 30초 후

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExact(AlarmManager.RTC, deleteTime, pendingIntent)
        } else {
            alarmManager.set(AlarmManager.RTC, deleteTime, pendingIntent)
        }

        Log.d("MainActivity", "⏰ 30초 후 8889 삭제 예약")
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
    private var originalAlarmVolume: Int = -1  // ⭐ 원래 시스템 알람 볼륨 저장

    // ⭐ 알람 음량 미리듣기 (STREAM_ALARM 사용 - 실제 알람과 동일)
    private fun playPreviewSound(soundFile: String, volume: Float) {
        stopPreviewSound()  // 기존 재생 중지

        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager

            // ⭐ 원래 시스템 알람 볼륨 저장 (처음 한 번만)
            if (originalAlarmVolume == -1) {
                originalAlarmVolume = audioManager.getStreamVolume(android.media.AudioManager.STREAM_ALARM)
                Log.d("MainActivity", "📊 원래 시스템 알람 볼륨 저장: $originalAlarmVolume")
            }

            // ⭐ 시스템 알람 볼륨을 50%로 임시 변경 (미리듣기용)
            val maxVolume = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM)
            val halfVolume = maxVolume / 2
            audioManager.setStreamVolume(android.media.AudioManager.STREAM_ALARM, halfVolume, 0)

            // ⭐ 사운드 URI 결정 (default = 시스템 기본 알람음)
            val soundUri = if (soundFile == "default") {
                android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
            } else {
                // res/raw 리소스 ID 가져오기
                val resourceId = resources.getIdentifier(soundFile, "raw", packageName)
                if (resourceId == 0) {
                    Log.e("MainActivity", "리소스 못 찾음: res/raw/$soundFile.mp3")
                    return
                }
                android.net.Uri.parse("android.resource://$packageName/$resourceId")
            }

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

        // ⭐ 시스템 알람 볼륨 복원
        if (originalAlarmVolume != -1) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                audioManager.setStreamVolume(android.media.AudioManager.STREAM_ALARM, originalAlarmVolume, 0)
                Log.d("MainActivity", "🔄 시스템 알람 볼륨 복원: $originalAlarmVolume")
                originalAlarmVolume = -1  // 초기화
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ 볼륨 복원 실패", e)
            }
        }

        Log.d("MainActivity", "🔇 미리듣기 중지")
    }

    // ⭐ 미리듣기 볼륨 변경 (슬라이더 실시간 반영)
    private fun updatePreviewVolume(volume: Float) {
        previewMediaPlayer?.setVolume(volume, volume)
        Log.d("MainActivity", "🔊 미리듣기 볼륨 변경: ${(volume * 100).toInt()}%")
    }
}