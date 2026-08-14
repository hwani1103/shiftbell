// android/app/src/main/kotlin/com/example/shiftbell/MainActivity.kt

package com.hwani1103.shiftbell

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
    private val CHANNEL = "com.hwani1103.shiftbell/alarm"
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
        val filter = IntentFilter("com.hwani1103.shiftbell.FLUTTER_REFRESH")
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
    // ⭐ CRITICAL FIX: triggerCheck()는 DB를 동기적으로(블로킹) 읽음. onResume()은
    // 메인 스레드에서 실행되는데, 여기서 바로 부르면 - 특히 설치 직후 첫 실행처럼
    // Dart(sqflite)가 같은 DB 파일을 동시에 처음 생성하고 있는 순간과 겹치면 -
    // SQLite 락 경합으로 메인 스레드가 몇 초간 멈출 수 있음. 메인 스레드가 막히면
    // Flutter 엔진의 첫 프레임 렌더링도 같이 막혀서, 스플래시(앱 로고) 화면에서
    // 멈춘 것처럼 보임. 재실행 시 재현이 안 되는 이유: 그땐 DB가 이미 다 만들어져
    // 있어서 경합 자체가 없음 - "설치 직후 딱 한 번만" 증상과 정확히 일치함.
    // 20분 전 알림/다음 wakeup 예약은 UI 렌더링과 무관하니 백그라운드 스레드로 옮김.
    Thread {
        AlarmGuardReceiver.triggerCheck(this)
    }.start()
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
                // ⭐ 정확한 알람 권한 (Android 12+). 이게 꺼지면 알람이 정확한 시각에
                // 예약이 안 될 수 있는데, 지금까지 앱이 이걸 아예 확인을 안 하고 있었음.
                "checkExactAlarmPermission" -> {
                    result.success(checkExactAlarmPermission())
                }
                "requestExactAlarmPermission" -> {
                    requestExactAlarmPermission()
                    result.success(null)
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
                // ⭐ 신규 추가
"cancelNotification" -> {
    // ⭐ 8888은 AlarmGuardReceiver가 전담 (여기서 직접 cancel하지 않음 - 다른 알람의 8888을 잘못 지울 수 있음)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(8889)  // 스누즈/타임아웃 알림
    AlarmGuardReceiver.triggerCheck(this)
    Log.d("MainActivity", "📢 Notification 삭제 (ID: 8889) + 8888 재계산")
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
                // ⭐ 홈 화면 캘린더 위젯 즉시 갱신 (스케줄 저장/변경 직후 Flutter가 호출)
                "refreshCalendarWidget" -> {
                    CalendarWidgetProvider.requestUpdate(applicationContext)
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
        val intent = Intent("com.hwani1103.shiftbell.REFRESH_ALARMS").apply {
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

    // ⭐ 정확한 알람 권한 확인 (Android 12=API31 미만은 이 권한 개념 자체가 없어서 항상 true)
    private fun checkExactAlarmPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    // ⭐ 정확한 알람 권한은 런타임 팝업이 없고, 시스템 설정 화면으로 보내는 것만 가능함
    // (오버레이 권한이랑 똑같은 방식)
    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val intent = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = android.net.Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ 정확한 알람 설정 화면 열기 실패", e)
            }
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
    private var previewLoudnessEnhancer: android.media.audiofx.LoudnessEnhancer? = null
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

                // ⭐ 실제 알람과 동일한 calibration 적용 (AlarmPlayer.kt와 동일한 커브)
                val calibrated = VolumeCalibration.linearGain(volume)
                setVolume(calibrated, calibrated)

                isLooping = false  // 미리듣기는 반복 안 함
                prepare()
                start()

                applyPreviewLoudnessBoost(audioSessionId, volume)
            }

            Log.d("MainActivity", "🔊 미리듣기 재생: $soundFile, 음량 ${(volume * 100).toInt()}%")

        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 미리듣기 재생 실패", e)
        }
    }

    // ⭐ 미리듣기용 LoudnessEnhancer 적용 (실제 알람과 동일 체감 음량)
    private fun applyPreviewLoudnessBoost(audioSessionId: Int, sliderVolume: Float) {
        try {
            previewLoudnessEnhancer?.release()
            previewLoudnessEnhancer = android.media.audiofx.LoudnessEnhancer(audioSessionId).apply {
                setTargetGain(VolumeCalibration.boostMillibels(sliderVolume))
                enabled = true
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "⚠️ 미리듣기 LoudnessEnhancer 미지원/실패", e)
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
        try {
            previewLoudnessEnhancer?.release()
        } catch (e: Exception) {
            Log.e("MainActivity", "미리듣기 LoudnessEnhancer 해제 실패", e)
        } finally {
            previewLoudnessEnhancer = null
        }

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
        val calibrated = VolumeCalibration.linearGain(volume)
        previewMediaPlayer?.setVolume(calibrated, calibrated)
        previewMediaPlayer?.audioSessionId?.let { applyPreviewLoudnessBoost(it, volume) }
        Log.d("MainActivity", "🔊 미리듣기 볼륨 변경: ${(volume * 100).toInt()}%")
    }
}