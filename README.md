AlarmActivity.kt
package com.example.shiftbell

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.view.GestureDetector
import android.view.MotionEvent
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.GestureDetectorCompat
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs
import android.util.Log

class AlarmActivity : AppCompatActivity() {
    private var alarmId: Int = 0
    private lateinit var gestureDetector: GestureDetectorCompat
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        alarmId = intent.getIntExtra("alarmId", 0)
        
        // 잠금 화면 위에 표시 (잠금 유지)
        setupWindowFlags()
        
        // UI 설정
        setContentView(R.layout.activity_alarm)
        setupUI()
        
        // 스와이프 제스처
        gestureDetector = GestureDetectorCompat(this, SwipeGestureListener())
        
        // 전체 화면 터치 리스너
        findViewById<ConstraintLayout>(R.id.rootLayout).setOnTouchListener { _, event ->
            gestureDetector.onTouchEvent(event)
            true
        }
    }
    
    private fun setupWindowFlags() {
        // 잠금 화면 위에 표시 (잠금은 유지)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }
    
    private fun setupUI() {
        val timeText = findViewById<TextView>(R.id.timeText)
        
        val now = Calendar.getInstance()
        val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
        timeText.text = timeFormat.format(now.time)
        
        // 닫기 버튼
        findViewById<Button>(R.id.dismissButton).setOnClickListener {
            dismissAlarm()
        }
        
        // 5분 후 버튼
        findViewById<Button>(R.id.snoozeButton).setOnClickListener {
            snoozeAlarm()
        }
    }
    
    // 360도 스와이프 감지
    private inner class SwipeGestureListener : GestureDetector.SimpleOnGestureListener() {
        private val SWIPE_THRESHOLD = 100
        private val SWIPE_VELOCITY_THRESHOLD = 100
        
        override fun onFling(
            e1: MotionEvent?,
            e2: MotionEvent,
            velocityX: Float,
            velocityY: Float
        ): Boolean {
            if (e1 == null) return false
            
            val diffX = e2.x - e1.x
            val diffY = e2.y - e1.y
            
            // 상하좌우 어느 방향이든 충분히 스와이프하면 끄기
            if ((abs(diffX) > SWIPE_THRESHOLD || abs(diffY) > SWIPE_THRESHOLD) &&
                (abs(velocityX) > SWIPE_VELOCITY_THRESHOLD || abs(velocityY) > SWIPE_VELOCITY_THRESHOLD)) {
                Log.d("AlarmActivity", "스와이프 감지: 알람 끄기")
                dismissAlarm()
                return true
            }
            
            return false
        }
    }
    
    private fun dismissAlarm() {
        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        
        // 알림 제거
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(alarmId)
        
        // 홈 화면으로 이동
        goToHomeScreen()
        
        // Activity 종료
        finish()
    }
    
    private fun snoozeAlarm() {
        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        
        // 알림 제거
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(alarmId)
        
        // TODO: 5분 후 알람 재등록
        
        // 홈 화면으로 이동
        goToHomeScreen()
        
        // Activity 종료
        finish()
    }
    
    private fun goToHomeScreen() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
    }
    
    override fun onBackPressed() {
        // 뒤로가기 막기
    }
}

AlarmOverlayService.kt
package com.example.shiftbell

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.*
import android.util.Log

class AlarmOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var overlayView: android.view.View? = null
    private var alarmId: Int = 0
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        alarmId = intent?.getIntExtra("alarmId", 0) ?: 0
        
        // Overlay 권한 체크
        if (!canDrawOverlays()) {
            Log.e("AlarmOverlayService", "Overlay 권한 없음!")
            stopSelf()
            return START_NOT_STICKY
        }
        
        showOverlay()
        
        return START_NOT_STICKY
    }
    
    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
    
    private fun showOverlay() {
        if (overlayView != null) return // 이미 표시 중
        
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        
        // Overlay View 생성
        overlayView = LayoutInflater.from(this).inflate(R.layout.overlay_alarm, null)
        
        // 현재 시간 설정
        val timeText = overlayView?.findViewById<TextView>(R.id.timeText)
        val now = Calendar.getInstance()
        val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
        timeText?.text = timeFormat.format(now.time)
        
        // 끄기 버튼
        overlayView?.findViewById<Button>(R.id.dismissButton)?.setOnClickListener {
            dismissAlarm()
        }
        
        // 5분 후 버튼
        overlayView?.findViewById<Button>(R.id.snoozeButton)?.setOnClickListener {
            snoozeAlarm()
        }
        
        // Overlay 파라미터 설정
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        )
        
        // 상단에 위치
        params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        params.y = 0
        
        // 화면에 추가
        windowManager?.addView(overlayView, params)
        
        Log.d("AlarmOverlayService", "Overlay 표시 완료")
    }
    
    private fun dismissAlarm() {
        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        
        // Overlay 제거
        removeOverlay()
        
        // 서비스 종료
        stopSelf()
    }
    
    private fun snoozeAlarm() {
        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        
        // TODO: 5분 후 알람 재등록
        
        // Overlay 제거
        removeOverlay()
        
        // 서비스 종료
        stopSelf()
    }
    
    private fun removeOverlay() {
        if (overlayView != null) {
            windowManager?.removeView(overlayView)
            overlayView = null
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        removeOverlay()
    }
}

AlarmPlayer.kt
package com.example.shiftbell

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.Build
import android.util.Log

class AlarmPlayer(private val context: Context) {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    
    companion object {
        @Volatile
        private var INSTANCE: AlarmPlayer? = null
        
        fun getInstance(context: Context): AlarmPlayer {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AlarmPlayer(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }
    
    fun playAlarm(soundType: String) {
        Log.d("AlarmPlayer", "알람 재생: $soundType")
        stopAlarm() // 기존 알람 정지
        
        when(soundType) {
            "loud", "soft" -> playSound(soundType)
            "vibrate" -> playVibration()
            "silent" -> {} // 아무것도 안 함
        }
    }
    
    private fun playSound(soundType: String) {
        try {
            // 알람 소리 URI
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            
            mediaPlayer = MediaPlayer().apply {
                setDataSource(context, alarmUri)
                
                // 핵심: STREAM_ALARM 사용!
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                
                // 볼륨 설정
                val volume = if (soundType == "loud") 1.0f else 0.5f
                setVolume(volume, volume)
                
                isLooping = true
                prepare()
                start()
            }
            
            Log.d("AlarmPlayer", "소리 재생 시작: $soundType")
            
            // 진동도 추가
            playVibration()
            
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "소리 재생 실패", e)
        }
    }
    
    private fun playVibration() {
        vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val pattern = longArrayOf(0, 1000, 500, 1000) // 진동 패턴
            vibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, 0) // 0 = 반복
            )
        } else {
            @Suppress("DEPRECATION")
            val pattern = longArrayOf(0, 1000, 500, 1000)
            vibrator?.vibrate(pattern, 0)
        }
        
        Log.d("AlarmPlayer", "진동 시작")
    }
    
    fun stopAlarm() {
        Log.d("AlarmPlayer", "알람 중지")
        
        mediaPlayer?.apply {
            if (isPlaying) {
                stop()
                Log.d("AlarmPlayer", "소리 중지됨")
            }
            release()
        }
        mediaPlayer = null
        
        vibrator?.cancel()
        vibrator = null
    }
}

CustomAlarmReceiver.kt
package com.example.shiftbell

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class CustomAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_SOUND_TYPE = "soundType"
        const val EXTRA_LABEL = "label"
        const val EXTRA_ID = "id"
        const val CHANNEL_ID = "alarm_channel"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("CustomAlarmReceiver", "알람 수신!")
        
        val soundType = intent.getStringExtra(EXTRA_SOUND_TYPE) ?: "loud"
        val label = intent.getStringExtra(EXTRA_LABEL) ?: "알람"
        val id = intent.getIntExtra(EXTRA_ID, 0)
        
        // 알람 재생
        AlarmPlayer.getInstance(context.applicationContext).playAlarm(soundType)
        
        // 화면 상태 확인
        if (isScreenOn(context)) {
            Log.d("CustomAlarmReceiver", "화면 켜짐 → Overlay Window")
            
            // Overlay 권한 체크
            if (canDrawOverlays(context)) {
                showOverlayWindow(context, id, label)
            } else {
                Log.w("CustomAlarmReceiver", "Overlay 권한 없음 → 전체 화면으로 대체")
                launchFullScreenAlarm(context, id, label)
            }
        } else {
            Log.d("CustomAlarmReceiver", "화면 꺼짐 → Full Screen Activity")
            launchFullScreenAlarm(context, id, label)
        }
    }
    
    // Overlay 권한 체크
    private fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(context)
        } else {
            true
        }
    }
    
    // 화면 켜짐 여부 확인
    private fun isScreenOn(context: Context): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isInteractive
    }
    
    // 화면 꺼짐: 전체 화면 알람
    private fun launchFullScreenAlarm(context: Context, id: Int, label: String) {
        val fullScreenIntent = Intent(context, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TASK or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                    Intent.FLAG_ACTIVITY_NO_HISTORY
            putExtra("alarmId", id)
        }
        context.startActivity(fullScreenIntent)
    }
    
    // 화면 켜짐: Overlay Window (떠있는 작은 창)
    private fun showOverlayWindow(context: Context, id: Int, label: String) {
        val overlayIntent = Intent(context, AlarmOverlayService::class.java).apply {
            putExtra("alarmId", id)
        }
        
        // 일반 Service로 시작 (Foreground 불필요)
        context.startService(overlayIntent)
        
        Log.d("CustomAlarmReceiver", "Overlay 서비스 시작")
    }
}

MainActivity.kt
package com.example.shiftbell

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.shiftbell/alarm"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleStopAlarmIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleStopAlarmIntent(intent)
    }
    
    private fun handleStopAlarmIntent(intent: Intent?) {
        when (intent?.action) {
            "STOP_ALARM" -> {
                val notificationId = intent.getIntExtra("notificationId", 0)
                
                // 알람 소리 중지 (Singleton)
                AlarmPlayer.getInstance(applicationContext).stopAlarm()
                
                // 알림 제거
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
                
                // Flutter에 알람 중지 이벤트 전달 (선택)
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAlarmStopped", notificationId)
                }
            }
            "SNOOZE_ALARM" -> {
                val notificationId = intent.getIntExtra("notificationId", 0)
                
                // 알람 소리 중지
                AlarmPlayer.getInstance(applicationContext).stopAlarm()
                
                // 알림 제거
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
                
                // TODO: 5분 후 알람 재등록
                // Flutter에 스누즈 이벤트 전달
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAlarmSnoozed", notificationId)
                }
            }
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                    else -> result.notImplemented()
                }
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
        
        // 정확한 알람 설정
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
        val intent = Intent(this, CustomAlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }
}

activity_alarm.xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/rootLayout"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <!-- 시계 아이콘 -->
    <ImageView
        android:id="@+id/clockIcon"
        android:layout_width="120dp"
        android:layout_height="120dp"
        android:src="@android:drawable/ic_lock_idle_alarm"
        android:tint="#FFFFFF"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintVertical_bias="0.35"/>

    <!-- 현재 시간 -->
    <TextView
        android:id="@+id/timeText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="09:30"
        android:textSize="64sp"
        android:textColor="#FFFFFF"
        android:fontFamily="sans-serif-light"
        app:layout_constraintTop_toBottomOf="@id/clockIcon"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="24dp"/>

    <!-- X 버튼 (스와이프 안내) -->
    <TextView
        android:id="@+id/swipeHint"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="↔ 스와이프하여 끄기 ↕"
        android:textSize="18sp"
        android:textColor="#888888"
        app:layout_constraintTop_toBottomOf="@id/timeText"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="48dp"/>

    <!-- 하단 버튼들 -->
    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginBottom="48dp"
        android:layout_marginStart="32dp"
        android:layout_marginEnd="32dp">
        
        <!-- 닫기 버튼 -->
        <Button
            android:id="@+id/dismissButton"
            android:layout_width="0dp"
            android:layout_height="60dp"
            android:layout_weight="1"
            android:text="끄기"
            android:textSize="18sp"
            android:textColor="#FFFFFF"
            android:background="@android:color/holo_red_dark"
            android:layout_marginEnd="8dp"/>
        
        <!-- 5분 후 버튼 -->
        <Button
            android:id="@+id/snoozeButton"
            android:layout_width="0dp"
            android:layout_height="60dp"
            android:layout_weight="1"
            android:text="5분 후"
            android:textSize="18sp"
            android:textColor="#FFFFFF"
            android:background="@android:color/holo_blue_dark"
            android:layout_marginStart="8dp"/>
    </LinearLayout>

</androidx.constraintlayout.widget.ConstraintLayout>

overlay_alarm.xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:background="#DD000000"
    android:padding="24dp"
    android:gravity="center">

    <!-- 시계 아이콘 -->
    <ImageView
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:src="@android:drawable/ic_lock_idle_alarm"
        android:tint="#FFFFFF"
        android:layout_marginBottom="12dp"/>

    <!-- 현재 시간 -->
    <TextView
        android:id="@+id/timeText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="09:30"
        android:textSize="48sp"
        android:textColor="#FFFFFF"
        android:fontFamily="sans-serif-light"
        android:layout_marginBottom="16dp"/>

    <!-- 버튼들 -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center">
        
        <!-- 끄기 버튼 -->
        <Button
            android:id="@+id/dismissButton"
            android:layout_width="0dp"
            android:layout_height="56dp"
            android:layout_weight="1"
            android:text="끄기"
            android:textSize="16sp"
            android:textColor="#FFFFFF"
            android:background="@android:color/holo_red_dark"
            android:layout_marginEnd="8dp"/>
        
        <!-- 5분 후 버튼 -->
        <Button
            android:id="@+id/snoozeButton"
            android:layout_width="0dp"
            android:layout_height="56dp"
            android:layout_weight="1"
            android:text="5분 후"
            android:textSize="16sp"
            android:textColor="#FFFFFF"
            android:background="@android:color/holo_blue_dark"
            android:layout_marginStart="8dp"/>
    </LinearLayout>

</LinearLayout>

AndroidManifest.xml

<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    
    <!-- 알람 권한 -->
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    
    <!-- 알림 권한 -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    
    <!-- 진동 권한 -->
    <uses-permission android:name="android.permission.VIBRATE"/>
    
    <!-- 잠금 화면 해제 권한 -->
    <uses-permission android:name="android.permission.DISABLE_KEYGUARD"/>
    
    <!-- Overlay 권한 ⭐ -->
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    
    <!-- 포그라운드 서비스 (선택) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>

    <application
        android:label="교대시계"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        tools:replace="android:label">
        
        <!-- 메인 Activity - ⭐ 두 줄 삭제 -->
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTask"
    android:taskAffinity="com.example.shiftbell.main"
    android:theme="@style/LaunchTheme"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    android:hardwareAccelerated="true"
    android:windowSoftInputMode="adjustResize">
    <!-- ⭐ showWhenLocked, turnScreenOn 삭제됨 -->
    
    <meta-data
      android:name="io.flutter.embedding.android.NormalTheme"
      android:resource="@style/NormalTheme"
      />
    
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
</activity>

        <!-- 전체 화면 알람 Activity -->
        <activity
            android:name=".AlarmActivity"
            android:exported="false"
            android:launchMode="singleTask"
            android:taskAffinity="com.example.shiftbell.alarm"
            android:excludeFromRecents="true"
            android:theme="@style/Theme.AppCompat.NoActionBar"
            android:showWhenLocked="true"
            android:turnScreenOn="true"
            android:screenOrientation="portrait"
            android:noHistory="true"
            android:finishOnTaskLaunch="true"/>
        
        <!-- Overlay 알람 Service ⭐ -->
        <service
            android:name=".AlarmOverlayService"
            android:enabled="true"
            android:exported="false"/>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />

        <!-- 커스텀 알람 리시버 -->
        <receiver 
            android:name=".CustomAlarmReceiver"
            android:enabled="true"
            android:exported="false"/>
        

    </application>

    <!-- 배터리 최적화 제외 요청 쿼리 -->
    <queries>
        <intent>
            <action android:name="android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
        </intent>
    </queries>
</manifest>

build.gradle.kts
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.shiftbell"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        
        // Desugaring 활성화 ⭐
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.shiftbell"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Desugaring 라이브러리 ⭐
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    // ConstraintLayout
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    
    // AppCompat
    implementation("androidx.appcompat:appcompat:1.6.1")
    
    // Material (선택)
    implementation("com.google.android.material:material:1.11.0")
}

import 'package:flutter/services.dart';

@pragma('vm:entry-point')
class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  static const platform = MethodChannel('com.example.shiftbell/alarm');

  /// 알람 초기화
  Future<void> initialize() async {
    print('✅ AlarmService 초기화 완료');
  }

  /// 알람 등록
  Future<void> scheduleAlarm({
    required int id,
    required DateTime dateTime,
    required String label,
    String soundType = 'loud',
  }) async {
    try {
      // Native 방식으로 등록
      await platform.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'timestamp': dateTime.millisecondsSinceEpoch,
        'label': label,
        'soundType': soundType,
      });

      print('✅ 알람 등록 완료: $label - ${dateTime.toString()}');
      print('   ID: $id, 사운드: $soundType');
    } catch (e) {
      print('❌ 알람 등록 실패: $e');
      rethrow;
    }
  }

  /// 알람 취소
  Future<void> cancelAlarm(int id) async {
    try {
      await platform.invokeMethod('cancelNativeAlarm', {'id': id});
      print('✅ 알람 취소: ID $id');
    } catch (e) {
      print('❌ 알람 취소 실패: $e');
      rethrow;
    }
  }

  /// 알람 중지
  Future<void> stopAlarm() async {
    try {
      await platform.invokeMethod('stopAlarm');
      print('✅ 알람 중지');
    } catch (e) {
      print('❌ 알람 중지 실패: $e');
    }
  }

  /// 테스트용: 5초 후 알람
  Future<void> scheduleTestAlarm({
    String label = '테스트 알람',
    String soundType = 'loud',
  }) async {
    final testTime = DateTime.now().add(Duration(seconds: 5));
    await scheduleAlarm(
      id: 99999,
      dateTime: testTime,
      label: label,
      soundType: soundType,
    );
    print('🧪 테스트 알람: 5초 후 울림');
  }
  /// Overlay 권한 요청
  Future<void> requestOverlayPermission() async {
    try {
      await platform.invokeMethod('requestOverlayPermission');
      print('✅ Overlay 권한 요청');
    } catch (e) {
      print('❌ Overlay 권한 요청 실패: $e');
    }
  }
  
  /// Overlay 권한 체크
  Future<bool> checkOverlayPermission() async {
    try {
      final hasPermission = await platform.invokeMethod('checkOverlayPermission');
      print('🔍 Overlay 권한: ${hasPermission ? "있음" : "없음"}');
      return hasPermission ?? false;
    } catch (e) {
      print('❌ Overlay 권한 체크 실패: $e');
      return false;
    }
  }
}



permission_service.dart
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 모든 필수 권한 요청
  Future<bool> requestAllPermissions() async {
    print('🔐 권한 요청 시작...');

    // 1. 알림 권한 (Android 13+)
    final notification = await _requestNotification();
    
    // 2. 정확한 알람 권한 (Android 12+)
    final alarm = await _requestExactAlarm();
    
    // 3. Overlay 권한 (화면 위 표시)
    final overlay = await _requestSystemAlertWindow();
    
    // 4. 배터리 최적화 제외 (선택)
    final battery = await _requestBatteryOptimization();

    final allGranted = notification && alarm && overlay;
    
    if (allGranted) {
      print('✅ 모든 필수 권한 허용됨');
    } else {
      print('⚠️ 일부 권한 거부됨');
      print('   알림: $notification');
      print('   정확한 알람: $alarm');
      print('   화면 위 표시: $overlay');
      print('   배터리 최적화: $battery');
    }

    return allGranted;
  }

  /// 알림 권한 요청
  Future<bool> _requestNotification() async {
    final status = await Permission.notification.request();
    print('   📢 알림 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 정확한 알람 권한 요청
  Future<bool> _requestExactAlarm() async {
    final status = await Permission.scheduleExactAlarm.request();
    print('   ⏰ 정확한 알람 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 화면 위 표시 권한 요청 (Overlay)
  Future<bool> _requestSystemAlertWindow() async {
    final status = await Permission.systemAlertWindow.request();
    print('   📱 화면 위 표시 권한: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 배터리 최적화 제외 요청
  Future<bool> _requestBatteryOptimization() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    print('   🔋 배터리 최적화 제외: ${status.isGranted ? "허용" : "거부"}');
    return status.isGranted;
  }

  /// 권한 상태 확인
  Future<Map<String, bool>> checkPermissions() async {
    return {
      'notification': await Permission.notification.isGranted,
      'exactAlarm': await Permission.scheduleExactAlarm.isGranted,
      'overlay': await Permission.systemAlertWindow.isGranted,
      'battery': await Permission.ignoreBatteryOptimizations.isGranted,
    };
  }

  /// 권한 설정 화면으로 이동
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

main.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/alarm_service.dart';
import 'services/permission_service.dart';
import 'services/database_service.dart';
import 'screens/next_alarm_tab.dart';
import 'screens/calendar_tab.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 한글 로케일 초기화
  await initializeDateFormatting('ko_KR', null);
  
  // DB 초기화
  await DatabaseService.instance.database;
  
  // 서비스 초기화
  await AlarmService().initialize();
  
   // 온보딩 체크
  final schedule = await DatabaseService.instance.getShiftSchedule();

  runApp(MyApp(showOnboarding: schedule == null));
}

class MyApp extends StatelessWidget {
  final bool showOnboarding;
  
  const MyApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 780),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: '교대종',
          theme: ThemeData.light().copyWith(
            primaryColor: Colors.blue,
          ),
          home: showOnboarding ? OnboardingScreen() : MainScreen(),
          routes: {
            '/home': (context) => MainScreen(),
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1;
  
  final _tabs = [
    NextAlarmTab(),
    CalendarTab(),
    SettingsTab(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: '다음알람'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '달력'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}

class AlarmTestScreen extends StatefulWidget {
  const AlarmTestScreen({super.key});

  @override
  State<AlarmTestScreen> createState() => _AlarmTestScreenState();
}

class _AlarmTestScreenState extends State<AlarmTestScreen> {
  DateTime selectedDateTime = DateTime.now().add(const Duration(minutes: 1));
  String selectedSoundType = 'loud';
  bool permissionsGranted = false;
  bool overlayPermissionGranted = false;

  final soundTypes = {
    'loud': '🔊 시끄러운 알람',
    'soft': '🔉 조용한 알람',
    'vibrate': '📳 진동만',
    'silent': '🔕 무음',
  };

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final permissions = await PermissionService().checkPermissions();
    final overlayPermission = await AlarmService().checkOverlayPermission();
    
    setState(() {
      permissionsGranted = permissions['notification']! && 
                          permissions['exactAlarm']!;
      overlayPermissionGranted = overlayPermission;
    });
  }

  Future<void> _requestPermissions() async {
    final granted = await PermissionService().requestAllPermissions();
    
    await Future.delayed(const Duration(milliseconds: 500));
    final overlayPermission = await AlarmService().checkOverlayPermission();
    
    setState(() {
      permissionsGranted = granted;
      overlayPermissionGranted = overlayPermission;
    });
    
    if (granted && overlayPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 모든 권한 허용 완료')),
      );
    } else if (granted && !overlayPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ "다른 앱 위에 표시" 권한이 필요합니다'),
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ 권한이 필요합니다'),
          action: SnackBarAction(
            label: '설정',
            onPressed: () => PermissionService().openSettings(),
          ),
        ),
      );
    }
  }

  Future<void> _requestOverlayPermission() async {
    await AlarmService().requestOverlayPermission();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏳ 권한 설정 후 뒤로가기를 눌러주세요'),
        duration: Duration(seconds: 5),
      ),
    );
    
    await Future.delayed(const Duration(seconds: 3));
    _checkPermissions();
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );

    if (time == null) return;

    setState(() {
      selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _scheduleAlarm() async {
    if (!permissionsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 먼저 권한을 허용해주세요')),
      );
      return;
    }

    try {
      await AlarmService().scheduleAlarm(
        id: 1,
        dateTime: selectedDateTime,
        label: '테스트 알람',
        soundType: selectedSoundType,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 알람 등록 완료!\n${_formatDateTime(selectedDateTime)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 알람 등록 실패: $e')),
      );
    }
  }

  Future<void> _scheduleTestAlarm() async {
    if (!permissionsGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 먼저 권한을 허용해주세요')),
      );
      return;
    }

    await AlarmService().scheduleTestAlarm(
      label: '5초 테스트',
      soundType: selectedSoundType,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(overlayPermissionGranted 
          ? '🧪 5초 후 작은 팝업창이 뜹니다!'
          : '🧪 5초 후 전체 화면이 뜹니다!\n(Overlay 권한 없음)'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _cancelAlarm() async {
    await AlarmService().cancelAlarm(1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ 알람 취소됨')),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}월 ${dt.day}일 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 교대종 알람 테스트'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 권한 상태
            Card(
              color: permissionsGranted && overlayPermissionGranted 
                  ? Colors.green.shade50 
                  : Colors.orange.shade50,
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  children: [
                    Icon(
                      permissionsGranted && overlayPermissionGranted 
                          ? Icons.check_circle 
                          : Icons.warning,
                      color: permissionsGranted && overlayPermissionGranted 
                          ? Colors.green 
                          : Colors.orange,
                      size: 48.sp,
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      permissionsGranted && overlayPermissionGranted
                          ? '모든 권한 허용됨'
                          : '권한 필요',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '알림: ${permissionsGranted ? "✅" : "❌"}\n'
                      '다른 앱 위 표시: ${overlayPermissionGranted ? "✅" : "❌"}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.sp),
                    ),
                    if (!permissionsGranted || !overlayPermissionGranted) ...[
                      SizedBox(height: 12.h),
                      ElevatedButton(
                        onPressed: _requestPermissions,
                        child: const Text('기본 권한 요청'),
                      ),
                      if (!overlayPermissionGranted) ...[
                        SizedBox(height: 8.h),
                        OutlinedButton.icon(
                          onPressed: _requestOverlayPermission,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('다른 앱 위에 표시 권한'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '💡 작은 팝업창을 보려면 필수!',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // 알람 시간 선택
            Text(
              '알람 시간',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Card(
              child: ListTile(
                leading: Icon(Icons.access_time, color: Colors.blue, size: 24.sp),
                title: Text(_formatDateTime(selectedDateTime), style: TextStyle(fontSize: 16.sp)),
                subtitle: Text('탭하여 시간 변경', style: TextStyle(fontSize: 14.sp)),
                trailing: Icon(Icons.arrow_forward_ios, size: 16.sp),
                onTap: _selectDateTime,
              ),
            ),

            SizedBox(height: 24.h),

            // 알람 타입 선택
            Text(
              '알람 타입',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            ...soundTypes.entries.map((entry) {
              final isSelected = selectedSoundType == entry.key;
              return Card(
                color: isSelected ? Colors.blue.shade50 : null,
                child: ListTile(
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey,
                    size: 24.sp,
                  ),
                  title: Text(entry.value, style: TextStyle(fontSize: 16.sp)),
                  onTap: () {
                    setState(() {
                      selectedSoundType = entry.key;
                    });
                  },
                ),
              );
            }).toList(),

            SizedBox(height: 32.h),

            // 알람 등록 버튼
            ElevatedButton.icon(
              onPressed: _scheduleAlarm,
              icon: const Icon(Icons.alarm_add),
              label: const Text('알람 등록'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.all(16.h),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),

            SizedBox(height: 12.h),

            // 5초 테스트 버튼
            OutlinedButton.icon(
              onPressed: _scheduleTestAlarm,
              icon: const Icon(Icons.science),
              label: const Text('5초 후 테스트'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.all(16.h),
              ),
            ),

            SizedBox(height: 12.h),

            // 취소 버튼
            TextButton.icon(
              onPressed: _cancelAlarm,
              icon: const Icon(Icons.cancel),
              label: const Text('알람 취소'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.all(16.h),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


alarm.dart
class Alarm {
  final int? id;
  final String time; // HH:mm
  final DateTime? date;
  final String type; // 'fixed' or 'custom'
  final int alarmTypeId;
  final String? shiftType;

  Alarm({
    this.id,
    required this.time,
    this.date,
    required this.type,
    required this.alarmTypeId,
    this.shiftType,
  });

  factory Alarm.fromMap(Map<String, dynamic> map) {
    return Alarm(
      id: map['id'],
      time: map['time'],
      date: map['date'] != null ? DateTime.parse(map['date']) : null,
      type: map['type'],
      alarmTypeId: map['alarm_type_id'],
      shiftType: map['shift_type'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'date': date?.toIso8601String(),
      'type': type,
      'alarm_type_id': alarmTypeId,
      'shift_type': shiftType,
    };
  }

  // 예정된 알람인지
  bool get isScheduled {
    return date != null && date!.isAfter(DateTime.now());
  }
}

alarm_type.dart
class AlarmType {
  final int id;
  final String name;
  final String emoji;
  final String soundFile;
  final double volume;
  final bool isPreset;

  AlarmType({
    required this.id,
    required this.name,
    required this.emoji,
    required this.soundFile,
    required this.volume,
    required this.isPreset,
  });

  // DB → 객체
  factory AlarmType.fromMap(Map<String, dynamic> map) {
    return AlarmType(
      id: map['id'],
      name: map['name'],
      emoji: map['emoji'],
      soundFile: map['sound_file'],
      volume: map['volume'],
      isPreset: map['is_preset'] == 1,
    );
  }

  // 객체 → DB
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'sound_file': soundFile,
      'volume': volume,
      'is_preset': isPreset ? 1 : 0,
    };
  }

  // 기본 3개
  static final List<AlarmType> presets = [
    AlarmType(
      id: 1,
      name: '소리',
      emoji: '🔊',
      soundFile: 'loud',
      volume: 1.0,
      isPreset: true,
    ),
    AlarmType(
      id: 2,
      name: '진동',
      emoji: '📳',
      soundFile: 'vibrate',
      volume: 0.0,
      isPreset: true,
    ),
    AlarmType(
      id: 3,
      name: '무음',
      emoji: '🔕',
      soundFile: 'silent',
      volume: 0.0,
      isPreset: true,
    ),
  ];
}


database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/alarm_type.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import '../models/alarm_template.dart';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();
  
  static Database? _database;
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'shiftbell.db');
    
    return await openDatabase(
      path,
      version: 2,  // ⭐ 버전 업
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // alarm_types 테이블
    await db.execute('''
      CREATE TABLE alarm_types(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sound_file TEXT NOT NULL,
        volume REAL NOT NULL,
        is_preset INTEGER NOT NULL
      )
    ''');
    
    // shift_schedule 테이블 (⭐ shift_colors 추가)
    await db.execute('''
      CREATE TABLE shift_schedule(
        id INTEGER PRIMARY KEY,
        is_regular INTEGER NOT NULL,
        pattern TEXT,
        today_index INTEGER,
        shift_types TEXT NOT NULL,
        start_date TEXT,
        shift_colors TEXT
      )
    ''');

    // alarms 테이블
    await db.execute('''
      CREATE TABLE alarms(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT NOT NULL,
        date TEXT,
        type TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL,
        shift_type TEXT,
        FOREIGN KEY (alarm_type_id) REFERENCES alarm_types(id)
      )
    ''');
    
    // ⭐ shift_alarm_templates 테이블 (신규)
    await db.execute('''
      CREATE TABLE shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');
    
    // 기본 알람 타입 3개 삽입
    for (var type in AlarmType.presets) {
      await db.insert('alarm_types', type.toMap());
    }
    
    print('✅ 데이터베이스 초기화 완료');
  }
  
  // ⭐ 버전 업그레이드 (기존 DB에 컬럼/테이블 추가)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // shift_colors 컬럼 추가
      await db.execute('ALTER TABLE shift_schedule ADD COLUMN shift_colors TEXT');
      
      // shift_alarm_templates 테이블 추가
      await db.execute('''
        CREATE TABLE shift_alarm_templates(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_type TEXT NOT NULL,
          time TEXT NOT NULL,
          alarm_type_id INTEGER NOT NULL
        )
      ''');
      
      print('✅ DB 업그레이드 완료 (v$oldVersion → v$newVersion)');
    }
  }
  
  // === AlarmType CRUD ===
  
  Future<List<AlarmType>> getAllAlarmTypes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('alarm_types');
    return maps.map((map) => AlarmType.fromMap(map)).toList();
  }
  
  Future<AlarmType?> getAlarmType(int id) async {
    final db = await database;
    final maps = await db.query(
      'alarm_types',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return AlarmType.fromMap(maps.first);
  }
  
  Future<int> insertAlarmType(AlarmType type) async {
    final db = await database;
    return await db.insert('alarm_types', type.toMap());
  }
  
  Future<int> deleteAlarmType(int id) async {
    final db = await database;
    return await db.delete(
      'alarm_types',
      where: 'id = ? AND is_preset = 0',
      whereArgs: [id],
    );
  }
  
  // === Alarm CRUD ===
  
  Future<int> insertAlarm(Alarm alarm) async {
    final db = await database;
    return await db.insert('alarms', alarm.toMap());
  }
  
  Future<List<Alarm>> getAllAlarms() async {
    final db = await database;
    final maps = await db.query('alarms');
    return maps.map((map) => Alarm.fromMap(map)).toList();
  }
  
  Future<List<Alarm>> getAlarmsByDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final maps = await db.query(
      'alarms',
      where: 'date LIKE ?',
      whereArgs: ['$dateStr%'],
    );
    return maps.map((map) => Alarm.fromMap(map)).toList();
  }
  
  Future<List<Alarm>> getNextAlarms({int limit = 10}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final maps = await db.query(
      'alarms',
      where: 'date > ?',
      whereArgs: [now],
      orderBy: 'date ASC',
      limit: limit,
    );
    return maps.map((map) => Alarm.fromMap(map)).toList();
  }
  
  Future<int> updateAlarm(Alarm alarm) async {
    final db = await database;
    return await db.update(
      'alarms',
      alarm.toMap(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }
  
  Future<int> deleteAlarm(int id) async {
    final db = await database;
    return await db.delete(
      'alarms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<int> saveShiftSchedule(ShiftSchedule schedule) async {
    final db = await database;
    return await db.insert(
      'shift_schedule',
      schedule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ShiftSchedule?> getShiftSchedule() async {
    final db = await database;
    final maps = await db.query('shift_schedule', limit: 1);
    if (maps.isEmpty) return null;
    return ShiftSchedule.fromMap(maps.first);
  }

  Future<int> updateShiftSchedule(ShiftSchedule schedule) async {
    final db = await database;
    return await db.update(
      'shift_schedule',
      schedule.toMap(),
      where: 'id = ?',
      whereArgs: [schedule.id],
    );
  }

  Future<void> insertAlarmsInBatch(List<Alarm> alarms) async {
    final db = await database;
    final batch = db.batch();
    
    for (var alarm in alarms) {
      batch.insert('alarms', alarm.toMap());
    }
    
    await batch.commit(noResult: true);
    print('✅ ${alarms.length}개 알람 일괄 등록 완료');
  }

  Future<void> deleteAllAlarms() async {
    final db = await database;
    await db.delete('alarms');
    print('🗑️ 모든 알람 삭제 완료');
  }
  
  // === AlarmTemplate CRUD (⭐ 신규) ===
  
  Future<int> insertAlarmTemplate({
    required String shiftType,
    required String time,
    required int alarmTypeId,
  }) async {
    final db = await database;
    return await db.insert('shift_alarm_templates', {
      'shift_type': shiftType,
      'time': time,
      'alarm_type_id': alarmTypeId,
    });
  }
  
  Future<List<AlarmTemplate>> getAlarmTemplates(String shiftType) async {
    final db = await database;
    final maps = await db.query(
      'shift_alarm_templates',
      where: 'shift_type = ?',
      whereArgs: [shiftType],
    );
    return maps.map((m) => AlarmTemplate.fromMap(m)).toList();
  }
  
  Future<List<AlarmTemplate>> getAllAlarmTemplates() async {
    final db = await database;
    final maps = await db.query('shift_alarm_templates');
    return maps.map((m) => AlarmTemplate.fromMap(m)).toList();
  }
  
  Future<int> deleteAlarmTemplate(int id) async {
    final db = await database;
    return await db.delete(
      'shift_alarm_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> deleteAllAlarmTemplates() async {
    final db = await database;
    await db.delete('shift_alarm_templates');
    print('🗑️ 모든 알람 템플릿 삭제 완료');
  }
}



next_alarm_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../models/alarm.dart';
import '../models/alarm_type.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';

class NextAlarmTab extends StatefulWidget {
  const NextAlarmTab({super.key});

  @override
  State<NextAlarmTab> createState() => _NextAlarmTabState();
}

class _NextAlarmTabState extends State<NextAlarmTab> {
  Alarm? _nextAlarm;
  AlarmType? _alarmType;
  Timer? _countdownTimer;
  String _timeUntilText = '';
  
  @override
  void initState() {
    super.initState();
    _loadNextAlarm();
    
    // ⭐ 1분마다 카운트다운만 갱신
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_nextAlarm != null && mounted) {
        // 알람 시각이 지났으면 DB 다시 읽기
        if (DateTime.now().isAfter(_nextAlarm!.date!)) {
          _loadNextAlarm();
        } else {
          // 카운트다운만 갱신
          setState(() {
            _timeUntilText = _getTimeUntil(_nextAlarm!.date!);
          });
        }
      }
    });
  }
  
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
  
  // ⭐ 외부에서 호출 가능하도록 public 메서드
  Future<void> refresh() async {
    await _loadNextAlarm();
  }
  
  Future<void> _loadNextAlarm() async {
    final alarms = await DatabaseService.instance.getNextAlarms(limit: 1);
    
    if (alarms.isEmpty) {
      setState(() {
        _nextAlarm = null;
        _alarmType = null;
        _timeUntilText = '';
      });
      return;
    }
    
    final alarm = alarms.first;
    final type = await DatabaseService.instance.getAlarmType(alarm.alarmTypeId);
    
    setState(() {
      _nextAlarm = alarm;
      _alarmType = type;
      _timeUntilText = _getTimeUntil(alarm.date!);
    });
  }
  
  String _getTimeUntil(DateTime alarmTime) {
    final diff = alarmTime.difference(DateTime.now());
    
    if (diff.inHours > 0) {
      return '${diff.inHours}시간 ${diff.inMinutes % 60}분 후에';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}분 후에';
    } else {
      return '곧';
    }
  }
  
  Future<void> _dismissAlarm() async {
    if (_nextAlarm == null) return;
    
    // DB에서 삭제
    await DatabaseService.instance.deleteAlarm(_nextAlarm!.id!);
    
    // Native 알람 취소
    await AlarmService().cancelAlarm(_nextAlarm!.id!);
    
    // 재로딩
    _loadNextAlarm();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알람이 취소되었습니다')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_nextAlarm == null || _alarmType == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('⏰', style: TextStyle(fontSize: 100.sp)),
              SizedBox(height: 24.h),
              Text(
                '예정된 알람이 없습니다',
                style: TextStyle(fontSize: 20.sp, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 시간 (가장 크게)
              Text(
                _nextAlarm!.time,
                style: TextStyle(
                  fontSize: 96.sp,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                ),
              ),
              
              SizedBox(height: 24.h),
              
              // 카운트다운 (⭐ _timeUntilText 사용)
              Text(
                '$_timeUntilText 알람이 울립니다',
                style: TextStyle(fontSize: 20.sp, color: Colors.white70),
              ),
              
              SizedBox(height: 64.h),
              
              // 알람 타입 정보
              Container(
                padding: EdgeInsets.all(32.w),
                margin: EdgeInsets.symmetric(horizontal: 32.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Column(
                  children: [
                    Text(
                      _alarmType!.emoji,
                      style: TextStyle(fontSize: 64.sp),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      '소리: ${_alarmType!.volume > 0 ? "켜짐" : "꺼짐"}',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white70),
                    ),
                    Text(
                      '진동: ${_alarmType!.soundFile == "vibrate" ? "켜짐" : "꺼짐"}',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white70),
                    ),
                    Text(
                      '다시 알림: 5분 후 / 3회',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 64.h),
              
              // 끄기 버튼
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: ElevatedButton(
                  onPressed: _dismissAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    minimumSize: Size(double.infinity, 60.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    '끄기',
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

calendar_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/database_service.dart';
import '../models/shift_schedule.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  ShiftSchedule? _schedule;
  // 중복 제거된 근무 종류 목록
List<String> get _uniqueShifts {
  if (_schedule?.pattern == null) return [];
  return _schedule!.pattern!.toSet().toList();
}
// 배경: 밝은 파스텔
Color _getShiftBackgroundColor(String shift) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  // ⭐ DB에서 색상 사용
  final hue = _schedule?.shiftColors?[shift]?.toDouble();
  
  if (hue != null) {
    return HSLColor.fromAHSL(1.0, hue, 0.5, 0.90).toColor();
  }
  
  // Fallback (DB 색상 없으면)
  return Colors.grey.shade100;
}

Color _getShiftTextColor(String shift) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  // ⭐ DB에서 색상 사용
  final hue = _schedule?.shiftColors?[shift]?.toDouble();
  
  if (hue != null) {
    return HSLColor.fromAHSL(1.0, hue, 0.8, 0.25).toColor();
  }
  
  // Fallback
  return Colors.grey.shade700;
}


  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }
  
  Future<void> _loadSchedule() async {
    final schedule = await DatabaseService.instance.getShiftSchedule();
    setState(() => _schedule = schedule);
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          child: Column(
            children: [
              // 커스텀 헤더
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 18.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_focusedDay.year}년 ${_focusedDay.month}월',
                      style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _focusedDay = DateTime.now();
                          _selectedDay = null;
                        });
                      },
                      child: Text(
                        'today',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 달력
              Expanded(
                child: TableCalendar(
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2026, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  locale: 'ko_KR',
                  
                  headerVisible: false,
                  rowHeight: 70.h,
                  
                  daysOfWeekHeight: 45.h,
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black),
                    weekendStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  
                  calendarStyle: CalendarStyle(
                    cellMargin: EdgeInsets.all(0),
                    cellPadding: EdgeInsets.all(0),
                    
                    tableBorder: TableBorder.all(
                      color: Colors.black,
                      width: 0.3,
                    ),
                    
                    defaultTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.black),
                    weekendTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.black),
                    outsideTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.grey),
                    
                    todayDecoration: BoxDecoration(
                      color: Color(0xFFFFF8DC),
                    ),
                    todayTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.black),
                    
                    selectedDecoration: BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      return _buildDateCell(day, false, false);
                    },
                    outsideBuilder: (context, day, focusedDay) {
                      return _buildDateCell(day, false, true);
                    },
                    todayBuilder: (context, day, focusedDay) {
                      return _buildDateCell(day, true, false);
                    },
                  ),
                  
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                    _showDayDetailPopup(selectedDay);
                  },
                  
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
 // _buildDateCell 함수 수정

Widget _buildDateCell(DateTime day, bool isToday, bool isOutside) {
  final shiftText = _schedule?.getShiftForDate(day) ?? '';
  final isSunday = day.weekday == DateTime.sunday;
  
  Color dateColor;
  if (isSunday) {
    dateColor = isOutside ? Colors.red.withOpacity(0.3) : Colors.red;
  } else {
    dateColor = isOutside ? Colors.grey : Colors.black;
  }
  
  return Container(
    // ⭐ 배경 제거
    padding: EdgeInsets.all(4.w),
    child: Column(
      children: [
        // 상단: 근무 종류
        if (shiftText.isNotEmpty && shiftText != '미설정')
          Container(
            width: double.infinity,
            height: 18.h,
            decoration: BoxDecoration(
              color: _getShiftBackgroundColor(shiftText),
              borderRadius: BorderRadius.circular(2.r),
            ),
            child: Center(
              child: Text(
                shiftText,
                style: TextStyle(
                  fontSize: 9.sp,
                  color: _getShiftTextColor(shiftText),
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
        else
          SizedBox(height: 18.h),
        
        Expanded(
  child: Center(
    child: isToday
        ? Container(
            width: 28.w,  // ⭐ 고정 크기
            height: 28.w,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          )
        : Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: dateColor,
            ),
          ),
  ),
),
      ],
    ),
  );
}
  
  void _showDayDetailPopup(DateTime day) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📅 ${day.month}월 ${day.day}일',
                      style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16.h),
                    Text('현재: [${_schedule?.getShiftForDate(day) ?? '미설정'}]', style: TextStyle(fontSize: 16.sp)),
                    SizedBox(height: 16.h),
                    Text('고정 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    Text('없음', style: TextStyle(fontSize: 16.sp)),
                    SizedBox(height: 16.h),
                    Text('커스텀 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    Text('없음', style: TextStyle(fontSize: 16.sp)),
                  ],
                ),
              ),
              
              const Divider(),
              
              Expanded(
                flex: 6,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '근무일 변경',
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 12.h),
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('주간'),
                          ),
                          SizedBox(height: 8.h),
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('야간'),
                          ),
                          SizedBox(height: 8.h),
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('휴무'),
                          ),
                        ],
                      ),
                    ),
                    
                    const VerticalDivider(),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '커스텀 알람',
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 12.h),
                          Text('(없음)', style: TextStyle(color: Colors.grey, fontSize: 14.sp)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

shift_schedule.dart
import 'dart:convert';

class ShiftSchedule {
  final int? id;
  final bool isRegular;
  final List<String>? pattern;
  final int? todayIndex;
  final List<String> shiftTypes;
  final DateTime? startDate;
  final Map<String, int>? shiftColors;  // ⭐ 신규

  ShiftSchedule({
    this.id,
    required this.isRegular,
    this.pattern,
    this.todayIndex,
    required this.shiftTypes,
    this.startDate,
    this.shiftColors,  // ⭐ 신규
  });

  factory ShiftSchedule.fromMap(Map<String, dynamic> map) {
    return ShiftSchedule(
      id: map['id'],
      isRegular: map['is_regular'] == 1,
      pattern: map['pattern'] != null ? (map['pattern'] as String).split(',') : null,
      todayIndex: map['today_index'],
      shiftTypes: (map['shift_types'] as String).split(','),
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date']) : null,
      shiftColors: map['shift_colors'] != null  // ⭐ 신규
          ? Map<String, int>.from(jsonDecode(map['shift_colors']))
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'is_regular': isRegular ? 1 : 0,
      'pattern': pattern?.join(','),
      'today_index': todayIndex,
      'shift_types': shiftTypes.join(','),
      'start_date': startDate?.toIso8601String(),
      'shift_colors': shiftColors != null ? jsonEncode(shiftColors) : null,  // ⭐ 신규
    };
  }

  String getShiftForDate(DateTime date) {
    if (!isRegular || pattern == null || todayIndex == null || startDate == null) {
      return '미설정';
    }

    final adjustedStartDate = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    
    final daysDiff = targetDate.difference(adjustedStartDate).inDays;
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm.dart';
import 'package:numberpicker/numberpicker.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool? _isRegular;
  List<String> _pattern = [];
  int? _todayIndex;
  
  List<String> _baseShiftTypes = ['주간', '야간', '오전', '오후', '휴무'];
  List<String> _customShiftTypes = [];
  List<String> get _allShiftTypes => [..._baseShiftTypes, ..._customShiftTypes];
  Map<String, List<TimeOfDay>> _shiftAlarms = {};
  List<String> _selectedShifts = [];  // 불규칙용

  List<String> get _uniqueShifts {
    return _pattern.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: Text('교대근무 스케줄 생성'),
        ),
        leading: _step > 0
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _step--);
                },
              )
            : SizedBox(width: 56.w),
      ),
      body: SafeArea(
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildSelectType();
      case 1:
        return _isRegular == true ? _buildShiftTypeCreation() : _buildShiftTypesInput();
      case 2:
        return _isRegular == true ? _buildPatternInput() : _buildSelectShiftsForAlarm();
      case 3:
        return _isRegular == true ? _buildTodayIndexInput() : _buildMainAlarmSetup();
      case 4:
        return _isRegular == true ? _buildMainAlarmSetup() : _buildComplete();
      case 5:
        return _buildComplete();
      default:
        return Container();
    }
  }

  Widget _buildSelectType() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '고정적으로 순환하는\n교대 근무인가요?',
            style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 48.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isRegular = true;
                  _step = 1;
                  _shiftAlarms.clear();  // ⭐ 초기화
                  _selectedShifts.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16.h),
              ),
              child: Text('예 - 규칙적', style: TextStyle(fontSize: 18.sp)),
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isRegular = false;
                  _step = 1;
                  _shiftAlarms.clear();  // ⭐ 초기화
                  _selectedShifts.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16.h),
              ),
              child: Text('아니요 - 불규칙', style: TextStyle(fontSize: 18.sp)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftTypeCreation() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 형태를 확인하세요\n없다면 추가 가능합니다',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                ..._allShiftTypes.map((name) {
                  final isCustom = _customShiftTypes.contains(name);
                  if (isCustom) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ElevatedButton(
                          onPressed: () {},
                          child: Text(name),
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: GestureDetector(
                            onTap: () => _deleteCustomShiftType(name),
                            child: Container(
                              width: 20.w,
                              height: 20.h,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 14.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return ElevatedButton(
                      onPressed: () {},
                      child: Text(name),
                    );
                  }
                }),
                
                OutlinedButton.icon(
                  onPressed: _customShiftTypes.length < 4 ? _showAddCustomDialog : null,
                  icon: Icon(Icons.add),
                  label: Text('추가'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 48.h),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _step = 2);
                },
                child: Text('다음'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftTypesInput() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 형태를 확인하세요\n없다면 추가 가능합니다',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                ..._allShiftTypes.map((name) {
                  final isCustom = _customShiftTypes.contains(name);
                  if (isCustom) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ElevatedButton(
                          onPressed: () {},
                          child: Text(name),
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: GestureDetector(
                            onTap: () => _deleteCustomShiftType(name),
                            child: Container(
                              width: 20.w,
                              height: 20.h,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 14.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return ElevatedButton(
                      onPressed: () {},
                      child: Text(name),
                    );
                  }
                }),
                
                OutlinedButton.icon(
                  onPressed: _customShiftTypes.length < 4 ? _showAddCustomDialog : null,
                  icon: Icon(Icons.add),
                  label: Text('추가'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 48.h),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _step = 2);
                },
                child: Text('다음'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ 불규칙: 실제 사용할 근무 선택
  Widget _buildSelectShiftsForAlarm() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '실제 근무 패턴에 해당하는\n근무를 모두 선택해주세요',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: _allShiftTypes.map((name) {
              final isSelected = _selectedShifts.contains(name);
              
              return ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (isSelected) {
                      _selectedShifts.remove(name);
                    } else {
                      _selectedShifts.add(name);
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.blue.shade700 : null,
                  foregroundColor: isSelected ? Colors.white : null,
                  elevation: isSelected ? 2 : null,
                ),
                child: Text(name),
              );
            }).toList(),
          ),
          
          Spacer(),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedShifts.isEmpty ? null : () {
                setState(() => _step = 3);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternInput() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '버튼을 탭해서 패턴을 완성해주세요',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: _allShiftTypes.map((name) => ElevatedButton(
              onPressed: _pattern.length < 30 ? () => _addToPattern(name) : null,
              child: Text(name),
            )).toList(),
          ),
          
          SizedBox(height: 24.h),
          
          Text(
            '전체 교대 패턴 순서대로 입력 - 최대 30일 \n ex) 주주휴휴야야휴휴',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12.h),
          
          Expanded(
            child: _buildPatternGrid(isSelectable: false),
          ),
          
          SizedBox(height: 16.h),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _pattern.isEmpty ? null : () {
                setState(() => _step = 3);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternGrid({required bool isSelectable}) {
    if (_pattern.isEmpty) {
      return Center(
        child: Text(
          '패턴 없음',
          style: TextStyle(fontSize: 16.sp, color: Colors.grey),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8.w,
        mainAxisSpacing: 8.h,
        childAspectRatio: 0.85,
      ),
      itemCount: _pattern.length,
      itemBuilder: (context, index) {
        final isSelected = isSelectable && _todayIndex == index;
        
        return InkWell(
          onTap: isSelectable
              ? () {
                  setState(() => _todayIndex = index);
                }
              : () {
                  _removeFromPattern(index);
                },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 4.w, top: 2.h),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: isSelected ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                
                Expanded(
                  child: Center(
                    child: Text(
                      _pattern[index],
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteCustomShiftType(String name) {
    setState(() {
      _customShiftTypes.remove(name);
      _pattern.removeWhere((shift) => shift == name);
    });
  }

  void _showAddCustomDialog() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('근무명 추가'),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLength: 4,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '근무명 (최대 4글자)',
              counterText: '',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('근무명을 입력해주세요')),
                );
                return;
              }
              if (text.length > 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('4글자 이하로 입력해주세요')),
                );
                return;
              }
              if (_allShiftTypes.contains(text)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('이미 존재하는 근무명입니다')),
                );
                return;
              }
              
              setState(() {
                _customShiftTypes.add(text);
              });
              Navigator.pop(context);
            },
            child: Text('추가'),
          ),
        ],
      ),
    );
  }

  void _addToPattern(String shift) {
    if (_pattern.length < 30) {
      setState(() => _pattern.add(shift));
    }
  }

  void _removeFromPattern(int index) {
    setState(() {
      _pattern.removeAt(index);
    });
  }

  Widget _buildMainAlarmSetup() {
    // ⭐ 규칙적이면 _uniqueShifts, 불규칙이면 _selectedShifts
    final shiftsToSetup = _isRegular == true ? _uniqueShifts : _selectedShifts;
    
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '근무별 고정 알람을 설정하세요',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          Text(
            '각 근무당 최대 3개까지 설정 가능',
            style: TextStyle(fontSize: 14.sp, color: Colors.black),
          ),
          Text(
            '설정 탭에서도 설정 / 수정이 가능합니다',
            style: TextStyle(fontSize: 14.sp, color: Colors.black),
          ),
          SizedBox(height: 24.h),
          
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12.w,
                mainAxisSpacing: 12.h,
                childAspectRatio: 0.70,
              ),
              itemCount: shiftsToSetup.length,
              itemBuilder: (context, index) {
                final shift = shiftsToSetup[index];
                final alarms = _shiftAlarms[shift] ?? [];
                
                return _buildShiftAlarmCard(shift, alarms);
              },
            ),
          ),
          
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _step = _isRegular == true ? 5 : 4);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftAlarmCard(String shift, List<TimeOfDay> alarms) {
    return InkWell(
      onTap: () => _showAlarmTimeDialog(shift),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alarms.isEmpty ? Colors.red.shade300 : Colors.black,
            width: 2,
          ),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          children: [
            Text(
              shift,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            SizedBox(height: 12.h),
            
            Expanded(
              child: Center(
                child: alarms.isEmpty
                    ? Text(
                        '탭하여 설정',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.grey,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: alarms.map((time) => Padding(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          child: Text(
                            _formatTime(time),
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )).toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showAlarmTimeDialog(String shift) {
    showDialog(
      context: context,
      builder: (context) => _AlarmTimeDialog(
        shift: shift,
        initialAlarms: _shiftAlarms[shift] ?? [],
        onSave: (alarms) {
          setState(() {
            _shiftAlarms[shift] = alarms;
          });
        },
      ),
    );
  }

  Widget _buildTodayIndexInput() {
    final today = DateTime.now();
    final dateText = '${today.month}/${today.day}';
    
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘($dateText)은 어떤 근무인가요?',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          
          Expanded(
            child: _buildPatternGrid(isSelectable: true),
          ),
          
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _todayIndex == null ? null : () {
                setState(() => _step = 4);
              },
              child: Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplete() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 100.sp, color: Colors.green),
          SizedBox(height: 24.h),
          Text(
            '설정 완료!',
            style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 48.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveAndFinish,
              child: Text('시작하기'),
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 색상 생성 함수
  Map<String, int> _generateShiftColors() {
    final Map<String, int> colors = {};
    
    // 휴무 계열은 빨강 고정
    for (var shift in _allShiftTypes) {
      if (shift.contains('휴')) {
        colors[shift] = 0;  // 빨강 = 0도
      }
    }
    
    // 나머지는 순서대로 할당 (30~330도, 빨강 제외)
    final nonRestShifts = _allShiftTypes.where((s) => !s.contains('휴')).toList();
    for (var i = 0; i < nonRestShifts.length; i++) {
      final hue = 30 + (i * 300 / nonRestShifts.length);
      colors[nonRestShifts[i]] = hue.toInt();
    }
    
    return colors;
  }

  Future<void> _saveAndFinish() async {
    // ⭐ 색상 생성
    final shiftColors = _generateShiftColors();
    
    final schedule = ShiftSchedule(
      isRegular: _isRegular!,
      pattern: _isRegular! ? _pattern : null,
      todayIndex: _todayIndex,
      shiftTypes: _allShiftTypes,
      startDate: DateTime.now(),
      shiftColors: shiftColors,  // ⭐ 추가
    );

    await DatabaseService.instance.saveShiftSchedule(schedule);

    if (_isRegular!) {
      // 규칙적: 30일치 알람 생성
      await _generate30DaysAlarms(schedule);
    } else {
      // ⭐ 불규칙: 템플릿만 저장
      await _saveAlarmTemplates();
    }

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  // ⭐ 불규칙: 템플릿 저장
  Future<void> _saveAlarmTemplates() async {
    for (var entry in _shiftAlarms.entries) {
      final shift = entry.key;
      final times = entry.value;
      
      for (var time in times) {
        await DatabaseService.instance.insertAlarmTemplate(
          shiftType: shift,
          time: _formatTime(time),
          alarmTypeId: 1,
        );
      }
    }
    
    print('✅ 알람 템플릿 저장 완료');
  }

  Future<void> _generate30DaysAlarms(ShiftSchedule schedule) async {
    print('🔄 30일치 알람 생성 시작...');
    
    final List<Alarm> alarms = [];
    final today = DateTime.now();
    
    for (var i = 0; i < 30; i++) {
      final date = today.add(Duration(days: i));
      final shiftType = schedule.getShiftForDate(date);
      
      // ⭐ '미설정'만 스킵 (휴무도 알람 가능)
      if (shiftType == '미설정') continue;
      
      final times = _shiftAlarms[shiftType] ?? [];
      
      for (var time in times) {
        final alarmTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        
        if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) continue;
        
        final alarm = Alarm(
          time: _formatTime(time),
          date: alarmTime,
          type: 'fixed',
          alarmTypeId: 1,
          shiftType: shiftType,
        );
        
        alarms.add(alarm);
      }
    }
    
    if (alarms.isNotEmpty) {
      await DatabaseService.instance.insertAlarmsInBatch(alarms);
      
      for (var alarm in alarms) {
        final id = alarm.date!.millisecondsSinceEpoch ~/ 1000;
        
        await AlarmService().scheduleAlarm(
          id: id,
          dateTime: alarm.date!,
          label: alarm.shiftType ?? '알람',
          soundType: 'loud',
        );
      }
    }
    
    print('✅ ${alarms.length}개 알람 생성 완료');
  }
}

// 알람 시간 설정 다이얼로그
class _AlarmTimeDialog extends StatefulWidget {
  final String shift;
  final List<TimeOfDay> initialAlarms;
  final Function(List<TimeOfDay>) onSave;

  const _AlarmTimeDialog({
    required this.shift,
    required this.initialAlarms,
    required this.onSave,
  });

  @override
  State<_AlarmTimeDialog> createState() => _AlarmTimeDialogState();
}

class _AlarmTimeDialogState extends State<_AlarmTimeDialog> {
  late List<TimeOfDay> _alarms;

  @override
  void initState() {
    super.initState();
    _alarms = List.from(widget.initialAlarms);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.shift} 고정 알람'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무일별 고정 알람을 3개까지 등록 가능합니다',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey),
            ),
            SizedBox(height: 16.h),
            
            ..._alarms.asMap().entries.map((entry) {
              return ListTile(
                leading: Icon(Icons.alarm),
                title: Text(
                  '${entry.value.hour.toString().padLeft(2, '0')}:${entry.value.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _alarms.removeAt(entry.key);
                    });
                  },
                ),
              );
            }),
            
            SizedBox(height: 8.h),
            
            if (_alarms.length < 3)
              OutlinedButton.icon(
                onPressed: _addAlarm,
                icon: Icon(Icons.add),
                label: Text('알람 추가'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48.h),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('취소'),
        ),
        TextButton(
          onPressed: _alarms.isEmpty
              ? null
              : () {
                  _alarms.sort((a, b) {
                    final aMinutes = a.hour * 60 + a.minute;
                    final bMinutes = b.hour * 60 + b.minute;
                    return aMinutes.compareTo(bMinutes);
                  });
                  
                  widget.onSave(_alarms);
                  Navigator.pop(context);
                },
          child: Text('저장'),
        ),
      ],
    );
  }

  Future<void> _addAlarm() async {
    await showDialog(
      context: context,
      builder: (context) => _SamsungStyleTimePicker(
        onTimeSelected: (time) {
          setState(() {
            _alarms.add(time);
          });
        },
      ),
    );
  }
}

class _SamsungStyleTimePicker extends StatefulWidget {
  final Function(TimeOfDay) onTimeSelected;

  const _SamsungStyleTimePicker({required this.onTimeSelected});

  @override
  State<_SamsungStyleTimePicker> createState() => _SamsungStyleTimePickerState();
}

class _SamsungStyleTimePickerState extends State<_SamsungStyleTimePicker> {
  bool _isAM = true;
  int _hour = 9;
  int _minute = 0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '시간 선택',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = true;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isAM ? Colors.blue : Colors.grey.shade300,
                            width: _isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            '오전',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 8.h),
                    
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAM = false;
                        });
                      },
                      child: Container(
                        width: 50.w,
                        height: 50.h,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: !_isAM ? Colors.blue : Colors.grey.shade300,
                            width: !_isAM ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            '오후',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(width: 16.w),
                
                NumberPicker(
                  value: _hour,
                  minValue: 1,
                  maxValue: 12,
                  infiniteLoop: true,
                  haptics: true,
                  itemHeight: 50.h,
                  itemWidth: 60.w,
                  axis: Axis.vertical,
                  textStyle: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      if (_hour == 11 && value == 12) {
                        _isAM = !_isAM;
                      } else if (_hour == 12 && value == 11) {
                        _isAM = !_isAM;
                      }
                      _hour = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                
                Text(':', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold)),
                
                NumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  haptics: true,
                  itemHeight: 50.h,
                  itemWidth: 60.w,
                  axis: Axis.vertical,
                  textStyle: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  selectedTextStyle: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  onChanged: (value) {
                    setState(() {
                      _minute = value;
                    });
                  },
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 24.h),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('취소'),
                ),
                SizedBox(width: 8.w),
                ElevatedButton(
                  onPressed: () {
                    int hour24;
                    if (_isAM) {
                      hour24 = _hour == 12 ? 0 : _hour;
                    } else {
                      hour24 = _hour == 12 ? 12 : _hour + 12;
                    }
                    
                    widget.onTimeSelected(TimeOfDay(hour: hour24, minute: _minute));
                    Navigator.pop(context);
                  },
                  child: Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

settings_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/database_service.dart';
import '../models/shift_schedule.dart';
import 'onboarding_screen.dart';
import '../services/alarm_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  ShiftSchedule? _schedule;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final schedule = await DatabaseService.instance.getShiftSchedule();
    setState(() => _schedule = schedule);
  }

  // _resetSchedule() 함수 수정

Future<void> _resetSchedule() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('완전 초기화'),
      content: Text('스케줄, 알람, 템플릿을 모두 삭제할까요?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('삭제', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm == true) {
    final db = await DatabaseService.instance.database;
    await db.delete('shift_schedule');
    await db.delete('alarms');
    await db.delete('shift_alarm_templates');  // ⭐ 추가
    
    // Native 알람 취소
    final alarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in alarms) {
      if (alarm.date != null) {
        final id = alarm.date!.millisecondsSinceEpoch ~/ 1000;
        await AlarmService().cancelAlarm(id);
      }
    }
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('⚙️ 설정'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // 현재 스케줄 정보
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📅 교대 스케줄',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12.h),
                  if (_schedule == null)
                    Text('설정 안 됨', style: TextStyle(color: Colors.grey))
                  else ...[
                    Text('근무 형태: ${_schedule!.isRegular ? "규칙적" : "불규칙"}'),
                    if (_schedule!.isRegular && _schedule!.pattern != null) ...[
                      SizedBox(height: 8.h),
                      Text('패턴: ${_schedule!.pattern!.join(", ")}'),
                      Text('오늘 인덱스: ${_schedule!.todayIndex ?? "?"}'),
                    ],
                    SizedBox(height: 8.h),
                    Text('근무 종류: ${_schedule!.shiftTypes.join(", ")}'),
                  ],
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 스케줄 초기화 버튼
          ListTile(
            leading: Icon(Icons.refresh, color: Colors.orange),
            title: Text('교대 스케줄 초기화'),
            subtitle: Text('온보딩으로 다시 설정'),
            onTap: _resetSchedule,
          ),

          Divider(),

          // 테스트용 DB 확인
          ListTile(
            leading: Icon(Icons.storage, color: Colors.blue),
            title: Text('DB 상태'),
            subtitle: Text(_schedule == null ? 'DB 비어있음' : 'DB 정상'),
          ),
          ListTile(
  leading: Icon(Icons.bug_report, color: Colors.red),
  title: Text('DB 알람 개수 확인'),
  onTap: () async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    print('📊 총 알람: ${alarms.length}개');
    
    for (var alarm in alarms) {
      print('  - ${alarm.date}: ${alarm.time} (${alarm.shiftType})');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('총 ${alarms.length}개 알람 (콘솔 확인)')),
    );
  },
),
ListTile(
  leading: Icon(Icons.delete_sweep, color: Colors.red),
  title: Text('모든 알람 삭제'),
  subtitle: Text('DB + Native 알람 전부 삭제'),
  onTap: () async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('모든 알람 삭제'),
        content: Text('정말로 모든 알람을 삭제할까요?\n(스케줄은 유지됩니다)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // DB에서 모든 알람 가져오기
      final alarms = await DatabaseService.instance.getAllAlarms();
      
      // Native 알람 취소
      for (var alarm in alarms) {
        if (alarm.date != null) {
          final id = alarm.date!.millisecondsSinceEpoch ~/ 1000;
          await AlarmService().cancelAlarm(id);
        }
      }
      
      // DB 알람 삭제
      await DatabaseService.instance.deleteAllAlarms();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${alarms.length}개 알람 삭제 완료')),
        );
      }
    }
  },
),
        ],
      ),
    );
    
  }
  
}


alarm_template.dart
class AlarmTemplate {
  final int? id;
  final String shiftType;
  final String time;
  final int alarmTypeId;

  AlarmTemplate({
    this.id,
    required this.shiftType,
    required this.time,
    required this.alarmTypeId,
  });

  factory AlarmTemplate.fromMap(Map<String, dynamic> map) {
    return AlarmTemplate(
      id: map['id'],
      shiftType: map['shift_type'],
      time: map['time'],
      alarmTypeId: map['alarm_type_id'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shift_type': shiftType,
      'time': time,
      'alarm_type_id': alarmTypeId,
    };
  }
}
