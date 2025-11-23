
AlarmActivity.kt

// android/app/src/main/kotlin/com/example/shiftbell/AlarmActivity.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.GestureDetectorCompat
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs

class AlarmActivity : AppCompatActivity() {
    private var alarmId: Int = 0
    private var alarmDuration: Int = 10
    private lateinit var gestureDetector: GestureDetectorCompat
    private var timeoutHandler: Handler? = null
    private var timeoutRunnable: Runnable? = null
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        alarmId = intent.getIntExtra("alarmId", 0)
        alarmDuration = intent.getIntExtra("alarmDuration", 10)
        
        setupWindowFlags()
        
        setContentView(R.layout.activity_alarm)
        setupUI()
        
        gestureDetector = GestureDetectorCompat(this, SwipeGestureListener())
        
        findViewById<ConstraintLayout>(R.id.rootLayout).setOnTouchListener { _, event ->
            gestureDetector.onTouchEvent(event)
            true
        }
        startTimeoutTimer()
    }
    
    private fun startTimeoutTimer() {
        timeoutHandler = Handler(Looper.getMainLooper())
        timeoutRunnable = Runnable {
            Log.d("AlarmActivity", "⏰ 타임아웃: ${alarmDuration}분 경과")
            timeoutAlarm()
        }
        
        timeoutHandler?.postDelayed(timeoutRunnable!!, (alarmDuration * 60 * 1000).toLong())
        
        Log.d("AlarmActivity", "⏱️ 타임아웃 타이머 시작: ${alarmDuration}분")
    }
    
    // AlarmActivity.kt - timeoutAlarm() 수정

private fun timeoutAlarm() {
    Log.d("AlarmActivity", "⏰ 알람 타임아웃 - 자동 종료")
    
    // 알람 소리 중지
    AlarmPlayer.getInstance(applicationContext).stopAlarm()
    
    // ⭐ DB에서 알람 삭제 (버그 수정!)
    try {
        val dbHelper = DatabaseHelper.getInstance(applicationContext)
        val db = dbHelper.writableDatabase
        val deleted = db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        db.close()
        
        Log.d("AlarmActivity", if (deleted > 0) {
            "✅ DB 알람 삭제: ID=$alarmId"
        } else {
            "⚠️ DB 알람 없음: ID=$alarmId"
        })
    } catch (e: Exception) {
        Log.e("AlarmActivity", "❌ DB 삭제 실패", e)
    }
    
    // 이력 업데이트
    updateAlarmHistory(alarmId, "timeout")
    
    // 알림 제거
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)
    
    // ⭐ 신규: 갱신 체크
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)
    
    // 홈 화면으로 이동
    goToHomeScreen()
    
    // Activity 종료
    finish()
}
    
    private fun setupWindowFlags() {
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
        
        findViewById<Button>(R.id.dismissButton).setOnClickListener {
            dismissAlarm()
        }
        
        findViewById<Button>(R.id.snoozeButton).setOnClickListener {
            snoozeAlarm()
        }
    }
    
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
            
            if ((abs(diffX) > SWIPE_THRESHOLD || abs(diffY) > SWIPE_THRESHOLD) &&
                (abs(velocityX) > SWIPE_VELOCITY_THRESHOLD || abs(velocityY) > SWIPE_VELOCITY_THRESHOLD)) {
                Log.d("AlarmActivity", "스와이프 감지: 알람 끄기")
                dismissAlarm()
                return true
            }
            
            return false
        }
    }
    
    // AlarmActivity.kt - dismissAlarm() 수정

private fun dismissAlarm() {
    cancelTimeoutTimer()
    
    AlarmPlayer.getInstance(applicationContext).stopAlarm()
    
    // DB에서 알람 삭제
    try {
        val dbHelper = DatabaseHelper.getInstance(applicationContext)
        val db = dbHelper.writableDatabase
        val deleted = db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        db.close()
        
        Log.d("AlarmActivity", if (deleted > 0) {
            "✅ DB 알람 삭제: ID=$alarmId"
        } else {
            "⚠️ DB 알람 없음: ID=$alarmId"
        })
    } catch (e: Exception) {
        Log.e("AlarmActivity", "❌ DB 삭제 실패", e)
    }
    
    updateAlarmHistory(alarmId, "swiped")
    
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)
    
    // ⭐ 신규: 갱신 체크 (Native에서 직접!)
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)
    
    goToHomeScreen()
    finish()
}
    
    private fun snoozeAlarm() {
        cancelTimeoutTimer()
        
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        
        try {
        val dbHelper = DatabaseHelper.getInstance(applicationContext)
        val db = dbHelper.readableDatabase
        
        val cursor = db.query(
            "alarms",
            null,
            "id = ?",
            arrayOf(alarmId.toString()),
            null, null, null
        )
        
        if (cursor.moveToFirst()) {
            val alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id"))
            val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type"))
            cursor.close()
            
            // ... (중간 생략: 5분 후 시간 계산 및 DB 업데이트)
            
            // ⭐ 수정: AlarmRefreshWorker → AlarmRefreshUtil (284번째 줄 근처)
            AlarmRefreshUtil.checkAndTriggerRefresh(this)
            
            val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
            sendBroadcast(guardIntent)
            
        } else {
            cursor.close()
            Log.e("AlarmActivity", "❌ 알람 정보 없음: ID=$alarmId")
        }
        
        db.close()
    } catch (e: Exception) {
        Log.e("AlarmActivity", "❌ 5분 후 재등록 실패", e)
    }
    
    updateAlarmHistory(alarmId, "snoozed", incrementSnooze = true)
    
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)
    
    goToHomeScreen()
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

    override fun onDestroy() {
        super.onDestroy()
        cancelTimeoutTimer()
    }

    private fun updateAlarmHistory(alarmId: Int, dismissType: String, incrementSnooze: Boolean = false) {
        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            val db = dbHelper.writableDatabase
            
            if (incrementSnooze) {
                db.execSQL(
                    "UPDATE alarm_history SET dismiss_type = ?, snooze_count = snooze_count + 1 WHERE alarm_id = ? AND dismiss_type = 'ringing'",
                    arrayOf(dismissType, alarmId)
                )
            } else {
                val values = ContentValues().apply {
                    put("dismiss_type", dismissType)
                }
                db.update(
                    "alarm_history",
                    values,
                    "alarm_id = ? AND dismiss_type = 'ringing'",
                    arrayOf(alarmId.toString())
                )
            }
            
            db.close()
            Log.d("AlarmActivity", "✅ 알람 이력 업데이트: ID=$alarmId, type=$dismissType")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "❌ 이력 업데이트 실패", e)
        }
    }

    private fun cancelTimeoutTimer() {
        timeoutRunnable?.let {
            timeoutHandler?.removeCallbacks(it)
        }
        Log.d("AlarmActivity", "⏱️ 타임아웃 타이머 취소")
    }
    
    // ⭐ 신규: Notification 업데이트 함수
    private fun updateNotification(alarmId: Int, newTime: String, label: String) {
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
        
        val timeParts = newTime.split(":")
        val now = Calendar.getInstance()
        val newTimestamp = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, timeParts[0].toInt())
            set(Calendar.MINUTE, timeParts[1].toInt())
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            
            if (timeInMillis < now.timeInMillis) {
                add(Calendar.DAY_OF_MONTH, 1)
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
        
        Log.d("AlarmActivity", "📢 Notification 업데이트: $newTime")
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
        
        var durationValue = 10  // 기본값
        if (typeCursor.moveToFirst()) {
            durationValue = typeCursor.getInt(0)
        }
        typeCursor.close()
        db.close()
        
        durationValue
    } catch (e: Exception) {
        Log.e("CustomAlarmReceiver", "duration 조회 실패", e)
        10  // 에러 시 기본값
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













MainActivity.kt

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

<!-- android/app/src/main/AndroidManifest.xml -->

<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    
    <!-- 기존 권한들... -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.RECEIVE_LOCKED_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.DISABLE_KEYGUARD"/>
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>

    <application
        android:label="교대시계"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        tools:replace="android:label">
        
        <!-- MainActivity -->
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:taskAffinity="com.example.shiftbell.main"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize"
            android:directBootAware="true">
            
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- AlarmActivity -->
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
            android:finishOnTaskLaunch="true"
            android:directBootAware="true"/>
        
        <!-- AlarmOverlayService -->
        <service
            android:name=".AlarmOverlayService"
            android:enabled="true"
            android:exported="false"
            android:directBootAware="true"/>
        
        

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />

        <!-- CustomAlarmReceiver -->
        <receiver 
            android:name=".CustomAlarmReceiver"
            android:enabled="true"
            android:exported="false"
            android:directBootAware="true"/>
        
        <!-- DirectBootReceiver -->
        <receiver
            android:name=".DirectBootReceiver"
            android:enabled="true"
            android:exported="true"
            android:directBootAware="true"
            android:permission="android.permission.RECEIVE_BOOT_COMPLETED">
            <intent-filter>
                <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED"/>
                <category android:name="android.intent.category.DEFAULT"/>
            </intent-filter>
        </receiver>
        <!-- ⭐ 신규: AlarmRefreshReceiver 추가 -->
    <receiver
        android:name=".AlarmRefreshReceiver"
        android:enabled="true"
        android:exported="false"
        android:directBootAware="true">
        <intent-filter>
            <action android:name="com.example.shiftbell.REFRESH_ALARMS"/>
        </intent-filter>
    </receiver>
        
        <!-- ⭐ AlarmGuardReceiver 신규 -->
        <receiver
            android:name=".AlarmGuardReceiver"
            android:enabled="true"
            android:exported="false"
            android:directBootAware="true"/>
        
        <!-- ⭐ AlarmActionReceiver 신규 -->
        <receiver
            android:name=".AlarmActionReceiver"
            android:enabled="true"
            android:exported="false"
            android:directBootAware="true"/>

    </application>

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












alarm_service.dart
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
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/alarm_service.dart';
import 'services/permission_service.dart';
import 'services/database_service.dart';
import 'services/alarm_refresh_service.dart';
import 'screens/next_alarm_tab.dart';
import 'screens/calendar_tab.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import 'providers/alarm_provider.dart';  // ⭐ 추가!

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  await DatabaseService.instance.database;
  await AlarmService().initialize();
  
  ShiftSchedule? schedule;
  try {
    schedule = await DatabaseService.instance.getShiftSchedule();
  } catch (e) {
    print('⚠️ 스케줄 로드 실패 (첫 실행): $e');
    schedule = null;
  }
  
  runApp(
    ProviderScope(
      child: MyApp(showOnboarding: schedule == null),
    ),
  );
}

class MyApp extends StatefulWidget {
  final bool showOnboarding;
  
  const MyApp({super.key, required this.showOnboarding});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.shiftbell/alarm');
  
  @override
  void initState() {
    super.initState();
    
    // ⭐ 앱 라이프사이클 감지
    WidgetsBinding.instance.addObserver(this);
    
    // Native에서 갱신 요청 수신
    platform.setMethodCallHandler((call) async {
      if (call.method == 'refreshAlarms') {
        print('📢 Native로부터 갱신 요청 수신');
        await AlarmRefreshService.instance.refreshIfNeeded();
      }
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  // ⭐ 앱이 포그라운드로 돌아올 때마다 체크
  // main.dart - _MyAppState
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  
  if (state == AppLifecycleState.resumed) {
    print('📱 앱 포그라운드 진입 - 갱신 체크');
    AlarmRefreshService.instance.refreshIfNeeded();
    
    // ⭐ 추가: AlarmNotifier도 강제 갱신
    if (mounted) {
      try {
        final container = ProviderScope.containerOf(context);
        container.read(alarmNotifierProvider.notifier).refresh();
        print('✅ AlarmNotifier 강제 갱신 완료');
      } catch (e) {
        print('❌ AlarmNotifier 갱신 실패: $e');
      }
    }
  }
}

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
          home: widget.showOnboarding ? OnboardingScreen() : MainScreen(),
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
  static const platform = MethodChannel('com.example.shiftbell/alarm');
  
  final _tabs = [
    NextAlarmTab(),
    CalendarTab(),
    SettingsTab(),
  ];
  
  // main.dart - _MainScreenState
@override
void initState() {
  super.initState();
  
  _checkRefreshOnStart();
  _scheduleGuardWakeup();
  
  // ⭐ Method Call Handler 등록
  platform.setMethodCallHandler(_handleMethod);
  
  // ⭐ 추가: 화면 진입 시 AlarmNotifier 갱신
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      try {
        final container = ProviderScope.containerOf(context);
        container.read(alarmNotifierProvider.notifier).refresh();
        print('✅ MainScreen 진입 - AlarmNotifier 갱신');
      } catch (e) {
        print('❌ AlarmNotifier 갱신 실패: $e');
      }
    }
  });
}

  Future<void> _checkRefreshOnStart() async {
    print('🚀 앱 시작 - 갱신 체크');
    await AlarmRefreshService.instance.refreshIfNeeded();
  }

  Future<void> _scheduleGuardWakeup() async {
    try {
      // ⭐ 1. 즉시 실행 (20분 이내 알람 체크)
      print('🔍 AlarmGuardReceiver 즉시 실행 시작');
      await platform.invokeMethod('triggerGuardCheck');
      print('✅ AlarmGuardReceiver 즉시 실행 완료');
      
      // ⭐ 2. 자정 예약
      await platform.invokeMethod('scheduleGuardWakeup');
      print('🛡️ 알람 감시 예약 완료');
    } catch (e) {
      print('❌ 감시 예약 실패: $e');
    }
  }
  
  // ⭐ Native에서 호출하는 메서드 처리
  // main.dart - _MainScreenState
Future<void> _handleMethod(MethodCall call) async {
  print('📞 Method Call 수신: ${call.method}');
  
  if (call.method == 'refreshAlarms') {
  print('🔄 알람 갱신 요청 - Provider 강제 새로고침');
  if (mounted) {
    try {
      final container = ProviderScope.containerOf(context);
      
      // ⭐ 1. AlarmNotifier 강제 갱신
      final notifier = container.read(alarmNotifierProvider.notifier);
      await notifier.refresh();
      print('✅ AlarmNotifier 새로고침 완료');
      
      // ⭐ 2. 상태를 강제로 다시 로드
      await Future.delayed(Duration(milliseconds: 100));
      await notifier.refresh();
      print('✅ AlarmNotifier 2차 새로고침 완료');
      
    } catch (e) {
      print('❌ Provider 새로고침 실패: $e');
    }
  }
} else if (call.method == 'openTab') {
    final tabIndex = call.arguments as int;
    print('📱 탭 이동 요청: $tabIndex');
    if (mounted) {
      setState(() {
        _currentIndex = tabIndex;
      });
    }
  }
}
  
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

// ... (AlarmTestScreen은 그대로 유지)

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

            OutlinedButton.icon(
              onPressed: _scheduleTestAlarm,
              icon: const Icon(Icons.science),
              label: const Text('5초 후 테스트'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.all(16.h),
              ),
            ),

            SizedBox(height: 12.h),

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

// lib/services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import '../models/alarm_type.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import '../models/alarm_template.dart';
import 'dart:convert';
import '../models/alarm_history.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();
  
  static Database? _database;
  static const platform = MethodChannel('com.example.shiftbell/alarm');
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    // ⭐ Device Protected 경로 사용
    String path;
    try {
      final deviceProtectedPath = await platform.invokeMethod('getDeviceProtectedStoragePath');
      path = deviceProtectedPath as String;
      print('✅ Device Protected DB 경로: $path');
    } catch (e) {
      // Fallback: 일반 경로
      path = join(await getDatabasesPath(), 'shiftbell.db');
      print('⚠️ 일반 DB 경로 사용: $path');
    }
    
    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        var result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='shift_schedule'"
        );
        
        if (result.isEmpty) {
          print('⚠️ 테이블 없음 - 재생성 중...');
          await _onCreate(db, 4);
          print('✅ 테이블 생성 완료');
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE alarm_types(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sound_file TEXT NOT NULL,
        volume REAL NOT NULL,
        is_preset INTEGER NOT NULL,
        duration INTEGER DEFAULT 10
      )
    ''');
    
    await db.execute('''
      CREATE TABLE shift_schedule(
        id INTEGER PRIMARY KEY,
        is_regular INTEGER NOT NULL,
        pattern TEXT,
        today_index INTEGER,
        shift_types TEXT NOT NULL,
        active_shift_types TEXT,
        start_date TEXT,
        shift_colors TEXT,
        assigned_dates TEXT
      )
    ''');

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
    
    await db.execute('''
      CREATE TABLE shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');

    // ⭐ 신규: 알람 이력 테이블
  await db.execute('''
    CREATE TABLE alarm_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      alarm_id INTEGER NOT NULL,
      scheduled_time TEXT NOT NULL,
      scheduled_date TEXT NOT NULL,
      actual_ring_time TEXT NOT NULL,
      dismiss_type TEXT NOT NULL,
      snooze_count INTEGER DEFAULT 0,
      shift_type TEXT,
      created_at TEXT NOT NULL
    )
  ''');
    
    for (var type in AlarmType.presets) {
      await db.insert('alarm_types', type.toMap());
    }
    
    print('✅ 데이터베이스 초기화 완료');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE shift_schedule ADD COLUMN shift_colors TEXT');
    
    await db.execute('''
      CREATE TABLE shift_alarm_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_type TEXT NOT NULL,
        time TEXT NOT NULL,
        alarm_type_id INTEGER NOT NULL
      )
    ''');
    
    print('✅ DB 업그레이드 완료 (v$oldVersion → v2)');
  }
  
  if (oldVersion < 3) {
    await db.execute('ALTER TABLE shift_schedule ADD COLUMN assigned_dates TEXT');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v3)');
  }
  
  if (oldVersion < 4) {
    await db.execute('ALTER TABLE shift_schedule ADD COLUMN active_shift_types TEXT');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v4)');
  }

  if (oldVersion < 5) {
    await db.execute('''
      CREATE TABLE alarm_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alarm_id INTEGER NOT NULL,
        scheduled_time TEXT NOT NULL,
        scheduled_date TEXT NOT NULL,
        actual_ring_time TEXT NOT NULL,
        dismiss_type TEXT NOT NULL,
        snooze_count INTEGER DEFAULT 0,
        shift_type TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v5)');
  }
  
  if (oldVersion < 6) {
    await db.execute('ALTER TABLE alarm_types ADD COLUMN duration INTEGER DEFAULT 10');
    print('✅ DB 업그레이드 완료 (v$oldVersion → v6)');
  }
} 
  
  // === 기존 메서드들 유지 ===
  
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

  // ⭐ 신규: 알람 이력 조회
Future<List<AlarmHistory>> getAlarmHistory({int limit = 50}) async {
  final db = await database;
  final maps = await db.query(
    'alarm_history',
    orderBy: 'created_at DESC',
    limit: limit,
  );
  return maps.map((map) => AlarmHistory.fromMap(map)).toList();
}

// ⭐ 신규: 특정 날짜 이력 조회
Future<List<AlarmHistory>> getAlarmHistoryByDate(DateTime date) async {
  final db = await database;
  final dateStr = date.toIso8601String().split('T')[0];
  final maps = await db.query(
    'alarm_history',
    where: 'scheduled_date LIKE ?',
    whereArgs: ['$dateStr%'],
    orderBy: 'actual_ring_time DESC',
  );
  return maps.map((map) => AlarmHistory.fromMap(map)).toList();
}

// ⭐ 신규: 이력 통계
Future<Map<String, dynamic>> getAlarmStatistics() async {
  final db = await database;
  
  final total = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM alarm_history')
  ) ?? 0;
  
  final swiped = Sqflite.firstIntValue(
    await db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE dismiss_type = 'swiped'")
  ) ?? 0;
  
  final snoozed = Sqflite.firstIntValue(
    await db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE dismiss_type = 'snoozed'")
  ) ?? 0;
  
  final timeout = Sqflite.firstIntValue(
    await db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE dismiss_type = 'timeout'")
  ) ?? 0;
  
  final avgSnooze = Sqflite.firstIntValue(
    await db.rawQuery('SELECT AVG(snooze_count) FROM alarm_history WHERE snooze_count > 0')
  ) ?? 0;
  
  return {
    'total': total,
    'swiped': swiped,
    'snoozed': snoozed,
    'timeout': timeout,
    'avgSnooze': avgSnooze,
  };
}

}












next_alarm_tab.dart

// lib/screens/next_alarm_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../models/alarm.dart';
import '../models/alarm_type.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alarm_provider.dart';


class NextAlarmTab extends ConsumerStatefulWidget {
  const NextAlarmTab({super.key});

  @override
  ConsumerState<NextAlarmTab> createState() => _NextAlarmTabState();
}

class _NextAlarmTabState extends ConsumerState<NextAlarmTab> {
  Timer? _countdownTimer;
  static const platform = MethodChannel('com.example.shiftbell/alarm');
  
  @override
  void initState() {
    super.initState();
    
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
  
  String _getTimeUntil(DateTime alarmTime) {
  final now = DateTime.now();
  final diff = alarmTime.difference(now);
  
  // ⭐ 과거 알람 방어
  if (diff.isNegative) {
    return '곧';
  }
  
  // ⭐ 핵심: 초 단위 올림 처리
  // 21:00:01 ~ 21:00:59 → 1분으로 올림
  final totalSeconds = diff.inSeconds;
  final totalMinutes = (totalSeconds / 60).ceil();  // ⭐ ceil()로 올림!
  
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  
  if (hours > 0) {
    // 1시간 이상
    if (minutes > 0) {
      return '${hours}시간 ${minutes}분 후에';
    } else {
      return '${hours}시간 후에';
    }
  } else if (minutes > 0) {
    // 1시간 미만
    return '${minutes}분 후에';
  } else {
    return '곧';
  }
}
  
  String _getDateText(DateTime alarmDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final alarmDay = DateTime(alarmDate.year, alarmDate.month, alarmDate.day);
    
    if (alarmDay == today) {
      return '오늘 (${alarmDate.month}/${alarmDate.day})';
    } else if (alarmDay == tomorrow) {
      return '내일 (${alarmDate.month}/${alarmDate.day})';
    } else {
      return '${alarmDate.month}/${alarmDate.day}';
    }
  }
  
  Future<void> _dismissAlarm(int id, DateTime? date) async {
    await ref.read(alarmNotifierProvider.notifier).deleteAlarm(id, date);
    // ⭐ 신규 추가
  try {
    await platform.invokeMethod('cancelNotification');
    print('✅ Notification 삭제 완료');
  } catch (e) {
    print('⚠️ Notification 삭제 실패: $e');
  }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 알람이 취소되었습니다'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  Future<void> _snoozeAlarm(int id, DateTime originalDate) async {
    try {
      final newDate = originalDate.add(Duration(minutes: 5));
      
      final alarms = await DatabaseService.instance.getAllAlarms();
      final alarm = alarms.firstWhere((a) => a.id == id);
      
      final updatedAlarm = Alarm(
        id: alarm.id,
        time: '${newDate.hour.toString().padLeft(2, '0')}:${newDate.minute.toString().padLeft(2, '0')}',
        date: newDate,
        type: alarm.type,
        alarmTypeId: alarm.alarmTypeId,
        shiftType: alarm.shiftType,
      );
      
      await DatabaseService.instance.updateAlarm(updatedAlarm);
      
      await AlarmService().cancelAlarm(id);
      await AlarmService().scheduleAlarm(
        id: id,
        dateTime: newDate,
        label: alarm.shiftType ?? '알람',
        soundType: 'loud',
      );
      
      await ref.read(alarmNotifierProvider.notifier).refresh();
      
      // ⭐ Notification 업데이트
      try {
        await platform.invokeMethod('updateNotification', {
          'alarmId': id,
          'newTime': updatedAlarm.time,
          'label': alarm.shiftType ?? '알람',
        });
        print('✅ Notification 업데이트 완료: ${updatedAlarm.time}');
      } catch (e) {
        print('⚠️ Notification 업데이트 실패: $e');
      }
      
      try {
        await platform.invokeMethod('triggerGuardCheck');
        print('✅ AlarmGuardReceiver 트리거 완료');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 알람이 5분 연장되었습니다 (${updatedAlarm.time})'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ 5분 후 처리 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 오류 발생: $e'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final nextAlarmAsync = ref.watch(nextAlarmProvider);
    
    return nextAlarmAsync.when(
      loading: () => Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            '에러 발생',
            style: TextStyle(color: Colors.white, fontSize: 20.sp),
          ),
        ),
      ),
      data: (nextAlarm) {
        return FutureBuilder<int>(
          future: DatabaseService.instance.getAllAlarms().then((list) => list.length),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data == 0) {
              return _buildNoAlarmScreen();
            }
            
            if (nextAlarm == null) {
              return _buildNoAlarmScreen();
            }
            
            return _AlarmScreenWidget(
              alarmId: nextAlarm.id!,
              onDismiss: () => _dismissAlarm(nextAlarm.id!, nextAlarm.date),
              onSnooze: () => _snoozeAlarm(nextAlarm.id!, nextAlarm.date!),
            );
          },
        );
      },
    );
  }
  
  Widget _buildNoAlarmScreen() {
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
}

class _AlarmScreenWidget extends ConsumerStatefulWidget {
  final int alarmId;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;
  
  const _AlarmScreenWidget({
    required this.alarmId,
    required this.onDismiss,
    required this.onSnooze,
  });

  @override
  ConsumerState<_AlarmScreenWidget> createState() => _AlarmScreenWidgetState();
}

class _AlarmScreenWidgetState extends ConsumerState<_AlarmScreenWidget> {
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
  
  String _getDateText(DateTime alarmDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final alarmDay = DateTime(alarmDate.year, alarmDate.month, alarmDate.day);
    
    if (alarmDay == today) {
      return '오늘 (${alarmDate.month}/${alarmDate.day})';
    } else if (alarmDay == tomorrow) {
      return '내일 (${alarmDate.month}/${alarmDate.day})';
    } else {
      return '${alarmDate.month}/${alarmDate.day}';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final alarmsAsync = ref.watch(alarmNotifierProvider);
    
    return alarmsAsync.when(
      loading: () => Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            '에러 발생',
            style: TextStyle(color: Colors.white, fontSize: 20.sp),
          ),
        ),
      ),
      data: (alarms) {
        return FutureBuilder<Alarm?>(
          key: ValueKey('alarm_${widget.alarmId}_${alarms.length}_${DateTime.now().millisecondsSinceEpoch}'),
          future: _loadAlarmFromDB(widget.alarmId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: CircularProgressIndicator(color: Colors.white)),
              );
            }
            
            final alarm = snapshot.data!;
            final actualTime = alarm.date != null
                ? '${alarm.date!.hour.toString().padLeft(2, '0')}:${alarm.date!.minute.toString().padLeft(2, '0')}'
                : alarm.time;
            return FutureBuilder<AlarmType?>(
              future: DatabaseService.instance.getAlarmType(alarm.alarmTypeId),
              builder: (context, alarmTypeSnapshot) {
                if (!alarmTypeSnapshot.hasData) {
                  return Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(child: CircularProgressIndicator(color: Colors.white)),
                  );
                }
                
                final alarmType = alarmTypeSnapshot.data!;
                final timeUntil = _getTimeUntil(alarm.date!);
                final dateText = _getDateText(alarm.date!);
                
                return Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dateText,
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w400,
                              color: Colors.white70,
                            ),
                          ),
                          
                          SizedBox(height: 8.h),
                          
                          Text(
                            actualTime,
                            style: TextStyle(
                              fontSize: 72.sp,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                            ),
                          ),
                          
                          SizedBox(height: 16.h),
                          
                          if (alarm.shiftType != null)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                              child: Text(
                                alarm.shiftType!,
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          
                          SizedBox(height: 24.h),
                          
                          Text(
                            '$timeUntil 알람이 울립니다',
                            style: TextStyle(fontSize: 18.sp, color: Colors.white70),
                          ),
                          
                          SizedBox(height: 32.h),
                          
                          Container(
                            padding: EdgeInsets.all(24.w),
                            margin: EdgeInsets.symmetric(horizontal: 32.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  alarmType.emoji,
                                  style: TextStyle(fontSize: 48.sp),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  '소리: ${alarmType.volume > 0 ? "켜짐" : "꺼짐"}',
                                  style: TextStyle(fontSize: 14.sp, color: Colors.white70),
                                ),
                                Text(
                                  '진동: ${alarmType.soundFile == "vibrate" ? "켜짐" : "꺼짐"}',
                                  style: TextStyle(fontSize: 14.sp, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          
                          SizedBox(height: 32.h),
                          
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32.w),
                            child: ElevatedButton(
                              onPressed: widget.onDismiss,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                minimumSize: Size(double.infinity, 50.h),
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
                          
                          SizedBox(height: 12.h),
                          
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32.w),
                            child: OutlinedButton(
                              onPressed: widget.onSnooze,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                minimumSize: Size(double.infinity, 50.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                side: BorderSide(color: Colors.blue, width: 2),
                              ),
                              child: Text(
                                '5분 후',
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  
  Future<Alarm?> _loadAlarmFromDB(int alarmId) async {
    try {
      print('🔍 DB에서 알람 읽기: ID=$alarmId');
      final allAlarms = await DatabaseService.instance.getAllAlarms();
      
      final alarm = allAlarms.firstWhere(
        (a) => a.id == alarmId,
        orElse: () => throw Exception('알람을 찾을 수 없습니다'),
      );
      
      print('✅ DB 알람 로드: ${alarm.time} (${alarm.date})');
      return alarm;
    } catch (e) {
      print('❌ DB 알람 로드 실패: $e');
      rethrow;
    }
  }
}




calendar_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/shift_schedule.dart';
import '../models/alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import 'package:flutter/services.dart';

// StatefulWidget → ConsumerStatefulWidget으로 변경
class CalendarTab extends ConsumerStatefulWidget {  // ⭐ 변경
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();  // ⭐ 변경
}

class _CalendarTabState extends ConsumerState<CalendarTab> {  // ⭐ 변경
  static const platform = MethodChannel('com.example.shiftbell/alarm');  // ⭐ 추가

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // ShiftSchedule? _schedule;  ⭐ 삭제 (Provider에서 가져올 것)
  
  bool _isMultiSelectMode = false;
  Set<DateTime> _selectedDates = {};

  // _loadSchedule() 메서드 삭제 (Provider가 자동으로 관리)
  
  // 색상 메서드는 그대로 유지
  // calendar_tab.dart의 _getShiftBackgroundColor() 함수 수정

Color _getShiftBackgroundColor(String shift, ShiftSchedule? schedule) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  final colorValue = schedule?.shiftColors?[shift];
  
  if (colorValue != null) {
    // ⭐ 휴무는 더 진한 빨강
    if (shift.contains('휴')) {
      return Color(colorValue);  // 0xFFEF5350 그대로 사용
    }
    
    // ⭐ 나머지는 팔레트 색상 그대로
    return Color(colorValue);
  }
  
  return Colors.grey.shade100;
}

  // calendar_tab.dart의 _getShiftTextColor() 함수 수정

Color _getShiftTextColor(String shift, ShiftSchedule? schedule) {
  if (shift == '미설정' || shift.isEmpty) return Colors.transparent;
  
  final colorValue = schedule?.shiftColors?[shift];
  
  if (colorValue != null) {
    final bgColor = Color(colorValue);
    
    // ⭐ 신규: 자동 계산
    return ShiftSchedule.getTextColor(bgColor);
  }
  
  return Colors.grey.shade700;
}

  @override
  void initState() {
    super.initState();
    // _loadSchedule() 호출 삭제
  }
  
  @override
Widget build(BuildContext context) {
  final scheduleAsync = ref.watch(scheduleProvider);
  
  return scheduleAsync.when(
    loading: () => Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    error: (error, stack) => Scaffold(
      body: Center(child: Text('에러 발생: $error')),
    ),
    data: (schedule) {
      if (schedule == null) {
        return Scaffold(
          body: Center(child: Text('스케줄이 없습니다')),
        );
      }
      
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                child: Column(
                  children: [
                    // ⭐ 헤더 영역 - 고정 높이
                    SizedBox(
                      height: 60.h,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _isMultiSelectMode
                                ? Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.close),
                                        onPressed: _exitMultiSelectMode,
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(),
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        '${_selectedDates.length}개 선택',
                                        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  )
                                : Text(
                                    '${_focusedDay.year}년 ${_focusedDay.month}월',
                                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                                  ),
                            if (!_isMultiSelectMode)
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
                    ),
                    
                    // 달력
                    Expanded(
                      child: TableCalendar(
                        firstDay: DateTime.utc(2024, 1, 1),
                        lastDay: DateTime.utc(2026, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) {
                          if (_isMultiSelectMode) {
                            return _selectedDates.any((d) => isSameDay(d, day));
                          }
                          return isSameDay(_selectedDay, day);
                        },
                        locale: 'ko_KR',
                        
                        headerVisible: false,
                        rowHeight: (70.h).clamp(60.0, 85.0),
                        
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
                            color: Colors.blueAccent.withOpacity(_isMultiSelectMode ? 0.3 : 1.0),
                            shape: BoxShape.circle,
                          ),
                          selectedTextStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        
                        calendarBuilders: CalendarBuilders(
                          defaultBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, false, false, schedule);
                          },
                          outsideBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, false, true, schedule);
                          },
                          todayBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, true, false, schedule);
                          },
                          selectedBuilder: (context, day, focusedDay) {
                            return _buildDateCell(day, isSameDay(day, DateTime.now()), false, schedule, isSelected: true);
                          },
                        ),
                        
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _focusedDay = focusedDay;
                          });
                          
                          if (_isMultiSelectMode) {
                            _toggleDateSelection(selectedDay);
                          } else {
                            _showDayDetailPopup(selectedDay, schedule);
                          }
                        },
                        
                        onDayLongPressed: (selectedDay, focusedDay) {
                          if (!_isMultiSelectMode) {
                            _enterMultiSelectMode(selectedDay);
                          }
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
              
              // 플로팅 버튼
              if (_isMultiSelectMode && _selectedDates.isNotEmpty)
                Positioned(
                  bottom: 24.h,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton.extended(
                      onPressed: () => _showBulkAssignSheet(schedule),
                      icon: Icon(Icons.edit_calendar),
                      label: Text('근무 일괄 할당'),
                      backgroundColor: Colors.grey.shade200,  // ⭐ 진한 회색
        foregroundColor: Colors.black,  // ⭐ 흰색 글씨
        elevation : 3,
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
  
  Widget _buildDateCell(DateTime day, bool isToday, bool isOutside, ShiftSchedule schedule, {bool isSelected = false}) {
    final shiftText = schedule.getShiftForDate(day);
    final isSunday = day.weekday == DateTime.sunday;
    
    Color dateColor;
    if (isSunday) {
      dateColor = isOutside ? Colors.red.withOpacity(0.3) : Colors.red;
    } else {
      dateColor = isOutside ? Colors.grey : Colors.black;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: isSelected && _isMultiSelectMode 
            ? Colors.blue.withOpacity(0.2) 
            : Colors.transparent,
      ),
      padding: EdgeInsets.all(4.w),
      child: Column(
        children: [
          if (shiftText.isNotEmpty && shiftText != '미설정')
            Container(
              width: double.infinity,
              height: 18.h,
              decoration: BoxDecoration(
                color: _getShiftBackgroundColor(shiftText, schedule),
                borderRadius: BorderRadius.circular(2.r),
              ),
              child: Center(
                child: Text(
                  shiftText,
                  style: TextStyle(
                    fontSize: 9.sp,
                    color: _getShiftTextColor(shiftText, schedule),
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
                      constraints: BoxConstraints(
                        minWidth: 26.w,
                        minHeight: 26.w,
                        maxWidth: 32.w,
                        maxHeight: 32.w,
                      ),
                      padding: EdgeInsets.all(2.w),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
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
  
  void _showDayDetailPopup(DateTime day, ShiftSchedule schedule) {
    final currentShift = schedule.getShiftForDate(day);
    final displayShifts = schedule.activeShiftTypes ?? schedule.shiftTypes;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = (screenHeight * 0.65).clamp(400.0, 600.0);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: popupHeight,
        padding: EdgeInsets.all(24.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${day.month}월 ${day.day}일 (${_getWeekday(day)})',
                      style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16.h),
                    
                    Row(
                      children: [
                        Text('현재:', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
                        SizedBox(width: 8.w),
                        Flexible(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                            decoration: BoxDecoration(
                              color: _getShiftBackgroundColor(currentShift, schedule),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: _getShiftTextColor(currentShift, schedule),
                                width: 2,
                              ),
                            ),
                            child: Text(
                              currentShift,
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: _getShiftTextColor(currentShift, schedule),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: 16.h),
                    
                    Text('고정 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    SizedBox(height: 8.h),
                    FutureBuilder<List<Alarm>>(
                      future: DatabaseService.instance.getAlarmsByDate(day),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return SizedBox(
                            height: 20.h,
                            width: 20.w,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        
                        final fixedAlarms = snapshot.data!.where((a) => a.type == 'fixed').toList();
                        
                        if (fixedAlarms.isEmpty) {
                          return Text('없음', style: TextStyle(fontSize: 14.sp, color: Colors.grey));
                        }
                        
                        return Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: fixedAlarms.map((alarm) {
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🔊', style: TextStyle(fontSize: 14.sp)),
                                  SizedBox(width: 4.w),
                                  Text(
                                    alarm.time,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    
                    SizedBox(height: 16.h),
                    
                    Text('커스텀 알람:', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                    SizedBox(height: 8.h),
                    FutureBuilder<List<Alarm>>(
                      future: DatabaseService.instance.getAlarmsByDate(day),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return SizedBox.shrink();
                        
                        final customAlarms = snapshot.data!.where((a) => a.type == 'custom').toList();
                        
                        if (customAlarms.isEmpty) {
                          return Text('없음', style: TextStyle(fontSize: 14.sp, color: Colors.grey));
                        }
                        
                        return Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: customAlarms.map((alarm) {
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('📳', style: TextStyle(fontSize: 14.sp)),
                                  SizedBox(width: 4.w),
                                  Text(
                                    alarm.time,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            Divider(height: 24.h),
            
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '근무일 변경',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12.h),
                  
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8.w,
                        mainAxisSpacing: 8.h,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: displayShifts.length,
                      itemBuilder: (context, index) {
                        final shiftType = displayShifts[index];
                        final isSelected = currentShift == shiftType;
                        
                        return ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            
                            // ⭐ scheduleProvider 사용
                            await ref.read(scheduleProvider.notifier).changeShiftWithAlarms(day, shiftType);
                            
                            // ⭐ alarmNotifier 강제 갱신
                            await ref.read(alarmNotifierProvider.notifier).refresh();
                            
                            // ⭐ AlarmGuardReceiver 트리거 (Notification 표시)
                            try {
                              await platform.invokeMethod('triggerGuardCheck');
                              print('✅ AlarmGuardReceiver 트리거 완료');
                            } catch (e) {
                              print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
                            }
                            
                            if (mounted) {
                              setState(() {});
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected 
                                ? Colors.blue.shade700 
                                : _getShiftBackgroundColor(shiftType, schedule),
                            foregroundColor: isSelected 
                                ? Colors.white 
                                : _getShiftTextColor(shiftType, schedule),
                            elevation: isSelected ? 4 : 1,
                            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              shiftType,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }
  
  void _enterMultiSelectMode(DateTime firstDate) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedDates.clear();
      _selectedDates.add(firstDate);
    });
  }
  
  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedDates.clear();
    });
  }
  
  void _toggleDateSelection(DateTime date) {
    setState(() {
      if (_selectedDates.any((d) => isSameDay(d, date))) {
        _selectedDates.removeWhere((d) => isSameDay(d, date));
      } else {
        _selectedDates.add(date);
      }
    });
  }
  
  void _showBulkAssignSheet(ShiftSchedule schedule) {
  final displayShifts = schedule.activeShiftTypes ?? schedule.shiftTypes;
  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Container(
      height: screenHeight * 0.4,
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ⭐ 제목 텍스트 - 센터 정렬
          Center(
            child: Text(
              '${_selectedDates.length}개 날짜에 할당할 근무',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 24.h),
          
          // ⭐ 버튼들 - 세로 센터 정렬
          Expanded(
            child: Center(  // ⭐ Center 추가
              child: GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12.w,
                  mainAxisSpacing: 12.h,
                  childAspectRatio: 1.8,
                ),
                itemCount: displayShifts.length,
                itemBuilder: (context, index) {
                  final shiftType = displayShifts[index];
                  
                  return ElevatedButton(
                    onPressed: () {
                      _bulkAssignShift(shiftType, schedule);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getShiftBackgroundColor(shiftType, schedule),
                      foregroundColor: _getShiftTextColor(shiftType, schedule),
                      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        shiftType,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
  
  // ⭐ Provider 사용으로 변경
  Future<void> _bulkAssignShift(String shiftType, ShiftSchedule schedule) async {
    if (_selectedDates.isEmpty) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );
    
    // ⭐ Provider의 bulkAssignShift 사용
    await ref.read(scheduleProvider.notifier).bulkAssignShift(
      _selectedDates.toList(),
      shiftType,
    );
    
    // ⭐ 각 날짜의 고정 알람 재생성
    for (var date in _selectedDates) {
      await ref.read(alarmNotifierProvider.notifier).regenerateFixedAlarms(
        date,
        shiftType,
      );
    }
    
    Navigator.pop(context);
    _exitMultiSelectMode();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 근무가 할당되었습니다')),
      );
    }
  }
  
  Future<void> _changeShift(DateTime date, String newShiftType, ShiftSchedule schedule) async {
  await ref.read(scheduleProvider.notifier).changeShiftWithAlarms(date, newShiftType);
  
  // ⭐ 알람 Provider도 수동 갱신
  await ref.read(alarmNotifierProvider.notifier).refresh();

  try {
    await platform.invokeMethod('cancelNotification');
    print('✅ Notification 삭제 완료 (근무일 변경)');
  } catch (e) {
    print('⚠️ Notification 삭제 실패: $e');
  }

}
}










shift_schedule.dart

// models/shift_schedule.dart

import 'dart:convert';
import 'package:flutter/material.dart';

// models/shift_schedule.dart

class ShiftSchedule {

  // ⭐ 신규: 고정 팔레트 8색
  static final List<Color> shiftPalette = [
    Color(0xFF42A5F5), // Blue (밝음)
    Color(0xFF66BB6A), // Green (중간)
    Color(0xFF26C6DA), // Teal (밝음)
    Color(0xFF5C6BC0), // Indigo (어두움)
    Color(0xFF00BCD4), // Cyan (밝음)
    Color(0xFF7E57C2), // Deep Purple (중간)
    Color(0xFF9CCC65), // Lime (밝음)
    Color(0xFF8D6E63), // Brown (어두움)
  ];
  
  // ⭐ 신규: 휴무 고정 색상
  static final Color offColor = Color(0xFFEF5350); // Red 400
  
  // ⭐ 신규: 배경색 밝기 판단
  static bool isBright(Color c) {
    final luminance = (c.red * 0.299 + c.green * 0.587 + c.blue * 0.114);
    return luminance > 160;
  }
  
  // ⭐ 신규: 자동 텍스트 색상 (배경에 따라)
  static Color getTextColor(Color bg) {
    return isBright(bg) ? Colors.black : Colors.white;
  }

  final int? id;
  final bool isRegular;
  List<String>? pattern;
  final int? todayIndex;
  final List<String> shiftTypes;  // 전체 근무 종류 (기본 5개 + 커스텀 4개)
  List<String>? activeShiftTypes;  // ⭐ 실제 사용 중인 근무 종류
  final DateTime? startDate;
  final Map<String, int>? shiftColors;
  Map<String, String>? assignedDates;

  ShiftSchedule({
    this.id,
    required this.isRegular,
    this.pattern,
    this.todayIndex,
    required this.shiftTypes,
    this.activeShiftTypes,  // ⭐ 추가
    this.startDate,
    this.shiftColors,
    this.assignedDates,
  });

  factory ShiftSchedule.fromMap(Map<String, dynamic> map) {
    return ShiftSchedule(
      id: map['id'],
      isRegular: map['is_regular'] == 1,
      pattern: map['pattern'] != null ? (map['pattern'] as String).split(',').toList() : null,
      todayIndex: map['today_index'],
      shiftTypes: (map['shift_types'] as String).split(','),
      activeShiftTypes: map['active_shift_types'] != null  // ⭐ 추가
          ? (map['active_shift_types'] as String).split(',')
          : null,
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date']) : null,
      shiftColors: map['shift_colors'] != null
          ? Map<String, int>.from(jsonDecode(map['shift_colors']))
          : null,
      assignedDates: map['assigned_dates'] != null
          ? Map<String, String>.from(jsonDecode(map['assigned_dates']))
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
      'active_shift_types': activeShiftTypes?.join(','),  // ⭐ 추가
      'start_date': startDate?.toIso8601String(),
      'shift_colors': shiftColors != null ? jsonEncode(shiftColors) : null,
      'assigned_dates': assignedDates != null ? jsonEncode(assignedDates) : null,
    };
  }

  String getShiftForDate(DateTime date) {
  final dateStr = date.toIso8601String().split('T')[0];
  
  // ⭐ 먼저 예외 확인 (우선순위)
  if (assignedDates != null && assignedDates!.containsKey(dateStr)) {
    return assignedDates![dateStr]!;
  }
  
  // 규칙적인 경우 패턴 계산
  if (isRegular) {
    if (pattern == null || todayIndex == null || startDate == null) {
      return '미설정';
    }

    final adjustedStartDate = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    
    final daysDiff = targetDate.difference(adjustedStartDate).inDays;
    final index = ((todayIndex! + daysDiff) % pattern!.length + pattern!.length) % pattern!.length;
    return pattern![index];
  } else {
    return '미설정';
  }
}
}







onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import '../services/alarm_refresh_helper.dart';

class OnboardingScreen extends ConsumerStatefulWidget {  // ⭐ 변경
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();  // ⭐ 변경
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {  // ⭐ 변경
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
      crossAxisCount: 6,  // ⭐ 6열 고정
      crossAxisSpacing: 6.w,  // ⭐ 간격 살짝 줄임 (8.w → 6.w)
      mainAxisSpacing: 6.h,   // ⭐ 간격 살짝 줄임 (8.h → 6.h)
      childAspectRatio: 1.0, // ⭐ 거의 정사각형 (0.85 → 0.95)
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
                      fontSize: 9.sp,  // ⭐ 번호도 살짝 축소 (10.sp → 9.sp)
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
                      fontSize: 11.sp,  // ⭐ 근무명 축소 (14.sp → 12.sp)
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,  // ⭐ 1줄 강제
                    overflow: TextOverflow.ellipsis,  // ⭐ 넘치면 ... 처리
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
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(  // ⭐ 변경
              maxCrossAxisExtent: 120.w,  // ⭐ 변경
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

  // onboarding_screen.dart의 _generateShiftColors() 함수 수정
// onboarding_screen.dart의 _generateShiftColors() 함수 전체 교체

Map<String, int> _generateShiftColors() {
  final Map<String, int> colors = {};
  
  // 1. 휴무 계열 → 고정 빨강
  for (var shift in _allShiftTypes) {
    if (shift.contains('휴')) {
      colors[shift] = 0xFFEF5350;  // ⭐ 고정 Red
    }
  }
  
  // 2. 나머지 근무 → 팔레트에서 순서대로 할당
  final nonRestShifts = _allShiftTypes.where((s) => !s.contains('휴')).toList();
  
  for (int i = 0; i < nonRestShifts.length && i < 8; i++) {
    final shift = nonRestShifts[i];
    final color = ShiftSchedule.shiftPalette[i % 8];  // ⭐ 팔레트 순환
    colors[shift] = color.value;  // Color → int 변환
  }
  
  return colors;
}

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

 // onboarding_screen.dart의 _saveAndFinish() 수정

// onboarding_screen.dart - _saveAndFinish()
Future<void> _saveAndFinish() async {
  final shiftColors = _generateShiftColors();
  
  List<String> activeShifts;
  if (_isRegular!) {
    activeShifts = _pattern.toSet().toList();
  } else {
    activeShifts = _selectedShifts;
  }
  
  final schedule = ShiftSchedule(
    isRegular: _isRegular!,
    pattern: _isRegular! ? _pattern : null,
    todayIndex: _todayIndex,
    shiftTypes: _allShiftTypes,
    activeShiftTypes: activeShifts,
    startDate: DateTime.now(),
    shiftColors: shiftColors,
  );

  await ref.read(scheduleProvider.notifier).saveSchedule(schedule);
  await _saveAlarmTemplates();

  if (_isRegular!) {
    await _generate10DaysAlarms(schedule);
  }
await AlarmRefreshHelper.instance.markRefreshed();
try {
  final allAlarms = await DatabaseService.instance.getAllAlarms();
  for (final alarm in allAlarms) {
    if (alarm.id != null) {
      await AlarmService().cancelAlarm(alarm.id!);
    }
  }
  await DatabaseService.instance.deleteAllAlarms();
  print('🗑️ 온보딩: 기존 알람 전체 삭제 완료');
} catch (e) {
  print('⚠️ 기존 알람 삭제 실패: $e');
}

if (_isRegular!) {
  await _generate10DaysAlarms(schedule);
}
  // ⭐ 온보딩 완료 후 갱신 완료 표시!
  await AlarmRefreshHelper.instance.markRefreshed();
  print('✅ 온보딩 완료 - 갱신 완료 표시');

  // AlarmNotifier 갱신
  if (mounted) {
    try {
      await ref.read(alarmNotifierProvider.notifier).refresh();
      print('✅ 온보딩 완료 - AlarmNotifier 갱신 완료');
    } catch (e) {
      print('❌ AlarmNotifier 갱신 실패: $e');
    }
  }

  if (mounted) {
    Navigator.of(context).pushReplacementNamed('/home');
  }
}

  // onboarding_screen.dart에서 수정

Future<void> _generate10DaysAlarms(ShiftSchedule schedule) async {
  print('🔄 10일치 알람 생성 시작...');
  
  final List<Alarm> alarms = [];
  final today = DateTime.now();
  
  for (var i = 0; i < 10; i++) {
    final date = today.add(Duration(days: i));
    final shiftType = schedule.getShiftForDate(date);
    
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
    // DB 저장
    await DatabaseService.instance.insertAlarmsInBatch(alarms);
    
    // ⭐ 변경: 저장된 알람 다시 읽어서 DB ID로 Native 등록
    final savedAlarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in savedAlarms) {
      if (alarm.date != null && alarm.date!.isAfter(DateTime.now())) {
        await AlarmService().scheduleAlarm(
          id: alarm.id!,  // ⭐ DB ID 사용
          dateTime: alarm.date!,
          label: alarm.shiftType ?? '알람',
          soundType: 'loud',
        );
      }
    }
    
    // ⭐ 삭제: refresh() 불필요
    // if (mounted) {
    //   ref.read(alarmNotifierProvider.notifier).refresh();
    // }
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
                
                // ⭐ 시간 NumberPicker 수정
                NumberPicker(
                  value: _hour,
                  minValue: 1,
                  maxValue: 12,
                  infiniteLoop: true,
                  haptics: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),  // ⭐ 변경
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
                
                // ⭐ 분 NumberPicker 수정
                NumberPicker(
                  value: _minute,
                  minValue: 0,
                  maxValue: 59,
                  zeroPad: true,
                  infiniteLoop: true,
                  haptics: true,
                  itemHeight: 50.h,
                  itemWidth: (60.w).clamp(50.0, 80.0),  // ⭐ 변경
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedule_provider.dart';
import '../providers/alarm_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';  // ⭐ 추가
import '../services/alarm_refresh_service.dart';  // ⭐ 추가
import 'package:flutter/services.dart';  // ⭐ 추가
import 'package:shared_preferences/shared_preferences.dart';

class SettingsTab extends ConsumerStatefulWidget {  // ⭐ 변경
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();  // ⭐ 변경
}

class _SettingsTabState extends ConsumerState<SettingsTab> {  // ⭐ 변경
  // ShiftSchedule? _schedule;  ⭐ 삭제 (Provider에서 가져올 것)

  @override
  void initState() {
    super.initState();
    // _loadSchedule() 호출 삭제
  }

  // _loadSchedule() 메서드 삭제

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
    // Native 알람 취소
    final alarms = await DatabaseService.instance.getAllAlarms();
    for (var alarm in alarms) {
      if (alarm.id != null) {
        await AlarmService().cancelAlarm(alarm.id!);
      }
    }
    
    // DB 삭제
    await ref.read(scheduleProvider.notifier).resetSchedule();
    
    // ⭐ 알람 Provider도 초기화
    // await ref.read(alarmNotifierProvider.notifier).refresh();
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    }
  }
}
// _SettingsTabState 클래스 안에 추가

Future<void> _showAlarmListDialog() async {
  final alarms = await DatabaseService.instance.getAllAlarms();
  
  // 날짜순 정렬
  alarms.sort((a, b) => a.date!.compareTo(b.date!));
  
  final now = DateTime.now();
  final futureAlarms = alarms.where((a) => 
    a.date != null && a.date!.isAfter(now)
  ).toList();
  final pastAlarms = alarms.where((a) => 
    a.date != null && a.date!.isBefore(now)
  ).toList();
  
  if (!mounted) return;
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.alarm, color: Colors.blue),
          SizedBox(width: 8.w),
          Text('등록된 알람 목록'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxHeight: 500.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 요약 정보
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${futureAlarms.length}',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          Text('미래', style: TextStyle(fontSize: 12.sp)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${pastAlarms.length}',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          Text('과거', style: TextStyle(fontSize: 12.sp)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${alarms.length}',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Text('전체', style: TextStyle(fontSize: 12.sp)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16.h),
            
            // 알람 리스트
            if (alarms.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32.h),
                  child: Text(
                    '등록된 알람이 없습니다',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alarms.length,
                  separatorBuilder: (context, index) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final alarm = alarms[index];
                    final isPast = alarm.date!.isBefore(now);
                    final isToday = alarm.date!.year == now.year &&
                                   alarm.date!.month == now.month &&
                                   alarm.date!.day == now.day;
                    
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 4.h,
                      ),
                      leading: Icon(
                        isPast ? Icons.check_circle : Icons.alarm,
                        color: isPast 
                          ? Colors.grey 
                          : (isToday ? Colors.orange : Colors.blue),
                        size: 20.sp,
                      ),
                      title: Text(
                        _formatAlarmDate(alarm.date!),
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isPast ? Colors.grey : Colors.black,
                          decoration: isPast ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        alarm.shiftType ?? '알람',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isPast ? Colors.grey : Colors.black87,
                        ),
                      ),
                      trailing: isToday 
                        ? Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              '오늘',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('닫기'),
        ),
      ],
    ),
  );
}

// 날짜 포맷 함수
String _formatAlarmDate(DateTime date) {
  final year = date.year;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  
  return '$year/$month/$day $hour:$minute';
}
  @override
Widget build(BuildContext context) {
  final scheduleAsync = ref.watch(scheduleProvider);
  
  return Scaffold(
    appBar: AppBar(
      title: Text('⚙️ 설정'),
    ),
    body: scheduleAsync.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('에러 발생: $error')),
      data: (schedule) {
        return ListView(
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
                    if (schedule == null)
                      Text('설정 안 됨', style: TextStyle(color: Colors.grey))
                    else ...[
                      Text('근무 형태: ${schedule.isRegular ? "규칙적" : "불규칙"}'),
                      if (schedule.isRegular && schedule.pattern != null) ...[
                        SizedBox(height: 8.h),
                        Text('패턴: ${schedule.pattern!.join(", ")}'),
                        Text('오늘 인덱스: ${schedule.todayIndex ?? "?"}'),
                      ],
                      SizedBox(height: 8.h),
                      // ⭐ 변경: shiftTypes 대신 activeShiftTypes 사용
                      Text('근무 종류: ${(schedule.activeShiftTypes ?? schedule.shiftTypes).join(", ")}'),
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
              subtitle: Text(schedule == null ? 'DB 비어있음' : 'DB 정상'),
            ),
            
            ListTile(
  leading: Icon(Icons.bug_report, color: Colors.red),
  title: Text('DB 알람 개수 확인'),
  onTap: () => _showAlarmListDialog(),  // ⭐ 함수 호출로 변경
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
                  await ref.read(alarmNotifierProvider.notifier).deleteAllAlarms();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ 모든 알람 삭제 완료')),
                    );
                  }
                }
              },
            ),
            ListTile(
  leading: Icon(Icons.list, color: Colors.purple),
  title: Text('DB 알람 전체 목록 (콘솔)'),
  onTap: () async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    print('📊 총 알람: ${alarms.length}개');
    
    final now = DateTime.now();
    final future = alarms.where((a) => a.date != null && a.date!.isAfter(now)).toList();
    final past = alarms.where((a) => a.date != null && a.date!.isBefore(now)).toList();
    
    print('미래: ${future.length}개, 과거: ${past.length}개');
    
    for (var alarm in alarms) {
      final isPast = alarm.date!.isBefore(now) ? '❌과거' : '✅미래';
      print('  $isPast ${alarm.date}: ${alarm.shiftType}');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('콘솔 확인!')),
    );
  },
),
Divider(),

Text('🧪 테스트 도구', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.orange)),

ListTile(
  leading: Icon(Icons.refresh, color: Colors.orange),
  title: Text('갱신 로직 테스트'),
  subtitle: Text('날짜 변경 시뮬레이션'),
  onTap: () async {
    print('\n========== 갱신 테스트 시작 ==========');
    
    final before = await DatabaseService.instance.getAllAlarms();
    print('📊 갱신 전 알람: ${before.length}개');
    
    final prefs = await SharedPreferences.getInstance();
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    await prefs.setInt('last_alarm_refresh', yesterday.millisecondsSinceEpoch);
    print('⏰ 마지막 갱신 시각: 어제로 변경');
    
    await AlarmRefreshService.instance.refreshIfNeeded();
    
    final after = await DatabaseService.instance.getAllAlarms();
    print('📊 갱신 후 알람: ${after.length}개');
    
    print('========== 갱신 테스트 완료 ==========\n');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 갱신: ${before.length}개 → ${after.length}개'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  },
),

ListTile(
  leading: Icon(Icons.repeat, color: Colors.orange),
  title: Text('중복 방지 테스트'),
  subtitle: Text('같은 날 재실행 시 스킵'),
  onTap: () async {
    print('\n========== 중복 방지 테스트 ==========');
    await AlarmRefreshService.instance.refreshIfNeeded();
    print('========== 중복 방지 테스트 완료 ==========\n');
  },
),
// settings_tab.dart의 ListTile들 사이에 추가

Divider(),

Padding(
  padding: EdgeInsets.only(left: 16.w, top: 8.h, bottom: 8.h),
  child: Text(
    '🌙 자정 체크 테스트',
    style: TextStyle(
      fontSize: 16.sp,
      fontWeight: FontWeight.bold,
      color: Colors.purple,
    ),
  ),
),

ListTile(
  leading: Icon(Icons.nightlight_round, color: Colors.purple),
  title: Text('자정 체크 강제 실행'),
  subtitle: Text('AlarmGuardReceiver 수동 트리거'),
  onTap: () async {
    try {
      // AlarmGuardReceiver 트리거
      await MethodChannel('com.example.shiftbell/alarm')
          .invokeMethod('triggerMidnightCheck');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 자정 체크 트리거 완료\n로그 확인: adb logcat | findstr AlarmGuard'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ 자정 체크 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 실패: $e')),
        );
      }
    }
  },
),

ListTile(
  leading: Icon(Icons.calendar_today, color: Colors.orange),
  title: Text('날짜 변경 시뮬레이션'),
  subtitle: Text('last_alarm_refresh를 어제로 변경'),
  onTap: () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final yesterday = DateTime.now().subtract(Duration(days: 1));
      await prefs.setInt('last_alarm_refresh', yesterday.millisecondsSinceEpoch);
      
      print('📅 마지막 갱신 시각: 어제로 변경');
      print('   어제: ${yesterday.year}-${yesterday.month}-${yesterday.day}');
      print('   오늘: ${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}');
      
      // AlarmGuardReceiver 트리거
      await MethodChannel('com.example.shiftbell/alarm')
          .invokeMethod('triggerMidnightCheck');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 날짜 어제로 변경 + 자정 체크 실행\n로그에서 "날짜 변경 감지" 확인'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ 날짜 시뮬레이션 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 실패: $e')),
        );
      }
    }
  },
),

ListTile(
  leading: Icon(Icons.info, color: Colors.blue),
  title: Text('현재 갱신 정보 확인'),
  onTap: () async {
    final prefs = await SharedPreferences.getInstance();
    final lastRefresh = prefs.getInt('last_alarm_refresh') ?? 0;
    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastRefresh);
    final today = DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('갱신 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('마지막 갱신:'),
            Text(
              '  ${lastDate.year}-${lastDate.month}-${lastDate.day}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            Text('현재 날짜:'),
            Text(
              '  ${today.year}-${today.month}-${today.day}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            Text('날짜 변경:'),
            Text(
              lastDate.day != today.day ? '  ✅ 다름 (갱신 필요)' : '  ❌ 같음',
              style: TextStyle(
                color: lastDate.day != today.day ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
          ),
        ],
      ),
    );
  },
),
          ],
        );
      },
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











alarm_provider.dart

// lib/providers/alarm_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import 'package:flutter/services.dart';


// ⭐ 알람 관리 Provider (StateNotifier)
class AlarmNotifier extends StateNotifier<AsyncValue<List<Alarm>>> {
  AlarmNotifier() : super(const AsyncValue.loading()) {
    _loadAlarms();
  }

  Future<void> _loadAlarms() async {
    state = const AsyncValue.loading();
    try {
      final alarms = await DatabaseService.instance.getAllAlarms();
      state = AsyncValue.data(alarms);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  // 알람 추가 메서드
  Future<void> addAlarm(Alarm alarm) async {
    try {
      final dbId = await DatabaseService.instance.insertAlarm(alarm);
      
      if (alarm.date != null) {
        await AlarmService().scheduleAlarm(
          id: dbId,
          dateTime: alarm.date!,
          label: alarm.shiftType ?? '알람',
          soundType: 'loud',
        );
      }
      
      try {
        await MethodChannel('com.example.shiftbell/alarm')
            .invokeMethod('triggerGuardCheck');
        print('✅ AlarmGuardReceiver 트리거 완료');
      } catch (e) {
        print('⚠️ AlarmGuardReceiver 트리거 실패: $e');
      }
      
      await _loadAlarms();
      print('✅ 알람 추가 완료 (ID: $dbId)');
    } catch (e) {
      print('❌ 알람 추가 실패: $e');
      rethrow;
    }
  }

  Future<void> deleteAlarm(int id, DateTime? date) async {
    try {
      await DatabaseService.instance.deleteAlarm(id);
      await AlarmService().cancelAlarm(id);
      
      await _loadAlarms();
      print('✅ 알람 삭제 완료 (ID: $id)');
    } catch (e) {
      print('❌ 알람 삭제 실패: $e');
      rethrow;
    }
  }

  // 고정 알람 재생성 메서드
  Future<void> regenerateFixedAlarms(DateTime date, String shiftType) async {
    try {
      final existingAlarms = await DatabaseService.instance.getAlarmsByDate(date);
      for (var alarm in existingAlarms) {
        if (alarm.type == 'fixed') {
          await DatabaseService.instance.deleteAlarm(alarm.id!);
          await AlarmService().cancelAlarm(alarm.id!);
        }
      }
      
      final templates = await DatabaseService.instance.getAlarmTemplates(shiftType);
      for (var template in templates) {
        final timeParts = template.time.split(':');
        final alarmTime = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        
        if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) {
          continue;
        }
        
        final alarm = Alarm(
          time: template.time,
          date: alarmTime,
          type: 'fixed',
          alarmTypeId: template.alarmTypeId,
          shiftType: shiftType,
        );
        
        final dbId = await DatabaseService.instance.insertAlarm(alarm);
        
        await AlarmService().scheduleAlarm(
          id: dbId,
          dateTime: alarmTime,
          label: shiftType,
          soundType: 'loud',
        );
      }
      
      await _loadAlarms();
      print('✅ 고정 알람 재생성 완료: $shiftType');
      try {
      await MethodChannel('com.example.shiftbell/alarm').invokeMethod('triggerGuardCheck');
      print('✅ AlarmProvider에서 AlarmGuardReceiver 트리거 완료');
    } catch (e) {
      print('⚠️ AlarmProvider에서 AlarmGuardReceiver 트리거 실패: $e');
    }
    } catch (e) {
      print('❌ 고정 알람 재생성 실패: $e');
      rethrow;
    }
  }

  Future<void> deleteAllAlarms() async {
    try {
      final alarms = await DatabaseService.instance.getAllAlarms();
      
      for (var alarm in alarms) {
        await AlarmService().cancelAlarm(alarm.id!);
        print('✅ Native 알람 취소: DB ID ${alarm.id}');
      }
      
      await DatabaseService.instance.deleteAllAlarms();
      
      await _loadAlarms();
      print('🗑️ 모든 알람 삭제 완료');
    } catch (e) {
      print('❌ 알람 삭제 실패: $e');
      rethrow;
    }
  }

  // 수동 새로고침
  Future<void> refresh() async {
    await _loadAlarms();
  }
}

// AlarmNotifier Provider
final alarmNotifierProvider = StateNotifierProvider<AlarmNotifier, AsyncValue<List<Alarm>>>((ref) {
  return AlarmNotifier();
});

// ⭐ 다음 알람 Provider (alarmNotifierProvider 변경 자동 감지)
final nextAlarmProvider = Provider<AsyncValue<Alarm?>>((ref) {
  final alarmsAsync = ref.watch(alarmNotifierProvider);
  
  return alarmsAsync.whenData((alarms) {
    if (alarms.isEmpty) return null;
    
    // 미래 시간 알람만 필터링
    final now = DateTime.now();
    final futureAlarms = alarms
        .where((a) => a.date != null && a.date!.isAfter(now))
        .toList();
    
    if (futureAlarms.isEmpty) return null;
    
    // 가장 빠른 알람 반환
    futureAlarms.sort((a, b) => a.date!.compareTo(b.date!));
    return futureAlarms.first;
  });
});

// 특정 날짜의 알람 목록 Provider
final alarmsForDateProvider = FutureProvider.family<List<Alarm>, DateTime>((ref, date) async {
  return await DatabaseService.instance.getAlarmsByDate(date);
});















schedule_provider.dart
// lib/providers/schedule_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shift_schedule.dart';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm_template.dart';
import '../models/alarm.dart';
import 'package:flutter/services.dart';


final scheduleProvider = StateNotifierProvider<ScheduleNotifier, AsyncValue<ShiftSchedule?>>((ref) {
  return ScheduleNotifier();
});

class ScheduleNotifier extends StateNotifier<AsyncValue<ShiftSchedule?>> {
  ScheduleNotifier() : super(const AsyncValue.loading()) {
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    state = const AsyncValue.loading();
    try {
      final schedule = await DatabaseService.instance.getShiftSchedule();
      state = AsyncValue.data(schedule);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> saveSchedule(ShiftSchedule schedule) async {
  try {
    final id = await DatabaseService.instance.saveShiftSchedule(schedule);
    
    // ⭐ ID를 포함한 새 스케줄 객체 생성
    final savedSchedule = ShiftSchedule(
      id: id,
      isRegular: schedule.isRegular,
      pattern: schedule.pattern,
      todayIndex: schedule.todayIndex,
      shiftTypes: schedule.shiftTypes,
      activeShiftTypes: schedule.activeShiftTypes,
      startDate: schedule.startDate,
      shiftColors: schedule.shiftColors,
      assignedDates: schedule.assignedDates,
    );
    
    state = AsyncValue.data(savedSchedule);
  } catch (e, stack) {
    state = AsyncValue.error(e, stack);
    rethrow;
  }
}

  Future<void> updateSchedule(ShiftSchedule schedule) async {
    try {
      await DatabaseService.instance.updateShiftSchedule(schedule);
      state = AsyncValue.data(schedule);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> changeShift(DateTime date, String newShiftType) async {
    final currentSchedule = state.value;
    if (currentSchedule == null) return;

    final dateStr = date.toIso8601String().split('T')[0];

    if (currentSchedule.isRegular) {
      if (currentSchedule.pattern == null || 
          currentSchedule.todayIndex == null || 
          currentSchedule.startDate == null) {
        return;
      }

      final adjustedStartDate = DateTime(
        currentSchedule.startDate!.year,
        currentSchedule.startDate!.month,
        currentSchedule.startDate!.day,
      );
      final targetDate = DateTime(date.year, date.month, date.day);
      final daysDiff = targetDate.difference(adjustedStartDate).inDays;
      final index = ((currentSchedule.todayIndex! + daysDiff) % 
                    currentSchedule.pattern!.length + 
                    currentSchedule.pattern!.length) % 
                    currentSchedule.pattern!.length;

      currentSchedule.pattern![index] = newShiftType;
    } else {
      currentSchedule.assignedDates ??= {};
      currentSchedule.assignedDates![dateStr] = newShiftType;
    }

    await updateSchedule(currentSchedule);
  }

  Future<void> bulkAssignShift(List<DateTime> dates, String shiftType) async {
    final currentSchedule = state.value;
    if (currentSchedule == null) return;

    for (var date in dates) {
      final dateStr = date.toIso8601String().split('T')[0];

      if (currentSchedule.isRegular) {
        if (currentSchedule.pattern == null || 
            currentSchedule.todayIndex == null || 
            currentSchedule.startDate == null) {
          continue;
        }

        final adjustedStartDate = DateTime(
          currentSchedule.startDate!.year,
          currentSchedule.startDate!.month,
          currentSchedule.startDate!.day,
        );
        final targetDate = DateTime(date.year, date.month, date.day);
        final daysDiff = targetDate.difference(adjustedStartDate).inDays;
        final index = ((currentSchedule.todayIndex! + daysDiff) % 
                      currentSchedule.pattern!.length + 
                      currentSchedule.pattern!.length) % 
                      currentSchedule.pattern!.length;

        currentSchedule.pattern![index] = shiftType;
      } else {
        currentSchedule.assignedDates ??= {};
        currentSchedule.assignedDates![dateStr] = shiftType;
      }
    }

    await updateSchedule(currentSchedule);
  }

  Future<void> resetSchedule() async {
    final db = await DatabaseService.instance.database;
    await db.delete('shift_schedule');
    await db.delete('alarms');
    await db.delete('shift_alarm_templates');
    
    state = const AsyncValue.data(null);
  }

  Future<void> refresh() async {
    await _loadSchedule();
  }

  Future<void> changeShiftWithAlarms(DateTime date, String newShiftType) async {
  final currentSchedule = state.value;
  if (currentSchedule == null || currentSchedule.id == null) {
    print('❌ 스케줄 없음 또는 ID 없음');
    return;
  }

  final db = await DatabaseService.instance.database;
  
  List<int> cancelIds = [];
  List<Map<String, dynamic>> scheduleData = [];
  
  await db.transaction((txn) async {
    final dateStr = date.toIso8601String().split('T')[0];
    
    print('🔵 날짜: $dateStr, 새 근무: $newShiftType');

    // ⭐ 규칙적이든 불규칙이든 assignedDates에 예외로 저장
    currentSchedule.assignedDates ??= {};
    currentSchedule.assignedDates![dateStr] = newShiftType;

    await txn.update(
      'shift_schedule',
      currentSchedule.toMap(),
      where: 'id = ?',
      whereArgs: [currentSchedule.id],
    );

    final existingAlarms = await txn.query(
      'alarms',
      where: 'date LIKE ? AND type = ?',
      whereArgs: ['${dateStr}%', 'fixed'],
    );
    
    print('🔵 삭제할 알람: ${existingAlarms.length}개');
    
    for (var alarmMap in existingAlarms) {
      final alarm = Alarm.fromMap(alarmMap);
      print('  - 삭제: ${alarm.time}');
      cancelIds.add(alarm.id!);
      await txn.delete('alarms', where: 'id = ?', whereArgs: [alarm.id]);
    }

    final templates = await txn.query(
      'shift_alarm_templates',
      where: 'shift_type = ?',
      whereArgs: [newShiftType],
    );
    
    print('🔵 템플릿 조회: ${templates.length}개 (근무: $newShiftType)');
    
    for (var templateMap in templates) {
      final template = AlarmTemplate.fromMap(templateMap);
      print('  + 템플릿: ${template.time}');
      
      final timeParts = template.time.split(':');
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      
      print('    알람 시간: $alarmTime, 현재: ${DateTime.now()}');
      
      if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) {
        print('    ❌ 과거 시간이라 스킵');
        continue;
      }
      
      final alarm = Alarm(
        time: template.time,
        date: alarmTime,
        type: 'fixed',
        alarmTypeId: template.alarmTypeId,
        shiftType: newShiftType,
      );
      
      final dbId = await txn.insert('alarms', alarm.toMap());
      print('    ✅ 알람 생성: ID $dbId');
      
      scheduleData.add({
        'id': dbId,
        'dateTime': alarmTime,
        'label': newShiftType,
      });
    }
    
    print('🔵 생성 예정 알람: ${scheduleData.length}개');
  });

  for (var id in cancelIds) {
    await AlarmService().cancelAlarm(id);
  }
  
  for (var data in scheduleData) {
    await AlarmService().scheduleAlarm(
      id: data['id'],
      dateTime: data['dateTime'],
      label: data['label'],
      soundType: 'loud',
    );
  }

  state = AsyncValue.data(currentSchedule);
  
  print('✅ 스케줄 + 알람 변경 완료');
  try {
    await MethodChannel('com.example.shiftbell/alarm').invokeMethod('triggerGuardCheck');
    print('✅ Provider에서 AlarmGuardReceiver 트리거 완료');
  } catch (e) {
    print('⚠️ Provider에서 AlarmGuardReceiver 트리거 실패: $e');
  }
}
}











DatabaseHelper.kt


// android/app/src/main/kotlin/com/example/shiftbell/DatabaseHelper.kt

package com.example.shiftbell

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build

class DatabaseHelper private constructor(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    companion object {
        private const val DATABASE_NAME = "shiftbell.db"
        private const val DATABASE_VERSION = 6
        
        @Volatile
        private var INSTANCE: DatabaseHelper? = null
        
        // ⭐ Device Protected Context 사용
        fun getInstance(context: Context): DatabaseHelper {
            return INSTANCE ?: synchronized(this) {
                val actualContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    context.createDeviceProtectedStorageContext()
                } else {
                    context.applicationContext
                }
                
                INSTANCE ?: DatabaseHelper(actualContext).also {
                    INSTANCE = it
                }
            }
        }
    }
    
    override fun onCreate(db: SQLiteDatabase) {
        // Flutter에서 관리하므로 비워둠
    }
    
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Flutter에서 관리하므로 비워둠
    }
}






DirectBootReceiver.kt
// android/app/src/main/kotlin/com/example/shiftbell/DirectBootReceiver.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

class DirectBootReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            Log.d("DirectBoot", "⏭️ 다른 액션: ${intent.action}")
            return
        }
        
        Log.e("DirectBoot", "========== LOCKED BOOT DETECTED ==========")
        
        try {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }
            
            saveBootTime(deviceContext)
            
            val nextAlarm = getNextAlarmFromDB(context)
            
            if (nextAlarm != null) {
                scheduleNativeAlarm(
                    context = context,
                    id = nextAlarm.id,
                    timestamp = nextAlarm.timestamp,
                    label = nextAlarm.shiftType
                )
                
                Log.e("DirectBoot", "✅ 긴급 알람 등록: ${nextAlarm.shiftType} ${nextAlarm.time}")
            } else {
                Log.e("DirectBoot", "⚠️ 등록할 알람 없음")
            }
            
            // ⭐ AlarmGuardReceiver 예약
            scheduleGuardWakeup(context)
            
            Log.e("DirectBoot", "========== DIRECT BOOT COMPLETE ==========")
        } catch (e: Exception) {
            Log.e("DirectBoot", "========== ERROR ==========", e)
        }
    }
    
    private fun scheduleGuardWakeup(context: Context) {
        val intent = Intent(context, AlarmGuardReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // 자정 예약
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
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
        
        Log.e("DirectBoot", "✅ AlarmGuardReceiver 예약 완료")
    }
    
    private fun saveBootTime(context: Context) {
        val prefs = context.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        val bootTime = System.currentTimeMillis()
        prefs.edit().putLong("last_boot_time", bootTime).apply()
        
        Log.d("DirectBoot", "📝 부팅 시각 저장: ${Date(bootTime)}")
    }
    
    private fun getNextAlarmFromDB(context: Context): AlarmData? {
        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase
            
            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.getDefault()
            ).format(Date())
            
            Log.d("DirectBoot", "현재 시각: $now")
            
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
                val time = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                
                val timestamp = SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss",
                    Locale.getDefault()
                ).parse(dateStr)?.time
                
                if (timestamp != null) {
                    alarm = AlarmData(id, timestamp, time, shiftType)
                    Log.d("DirectBoot", "✅ 다음 알람 조회: $time ($shiftType)")
                }
            } else {
                Log.d("DirectBoot", "⚠️ DB에 알람 없음")
            }
            
            cursor.close()
            db.close()
            
            alarm
        } catch (e: Exception) {
            Log.e("DirectBoot", "DB 읽기 실패", e)
            null
        }
    }
    
    private fun scheduleNativeAlarm(
        context: Context,
        id: Int,
        timestamp: Long,
        label: String
    ) {
        try {
            val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                putExtra(CustomAlarmReceiver.EXTRA_ID, id)
                putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
                putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                setPackage(context.packageName)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val alarmClockInfo = AlarmManager.AlarmClockInfo(timestamp, pendingIntent)
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            
            Log.d("DirectBoot", "✅ Native 알람 등록 (AlarmClock): ID=$id, timestamp=$timestamp")
        } catch (e: Exception) {
            Log.e("DirectBoot", "Native 알람 등록 실패: ID=$id", e)
        }
    }
    
    data class AlarmData(
        val id: Int,
        val timestamp: Long,
        val time: String,
        val shiftType: String
    )
}








AlarmRefreshUtil.kt



// android/app/src/main/kotlin/com/example/shiftbell/AlarmRefreshUtil.kt

package com.example.shiftbell

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.*

object AlarmRefreshUtil {
    
    /**
     * 갱신 필요 여부 체크 & Native 갱신 실행
     * (하루 1회 중복 방지)
     */
    fun checkAndTriggerRefresh(context: Context) {
        try {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }
            
            val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
            
            // ⭐ 날짜 체크 (하루 1회)
            val lastRefresh = prefs.getLong("last_alarm_refresh", 0L)  // ⭐ 0L
            val lastDate = Calendar.getInstance().apply { 
                timeInMillis = if (lastRefresh > 0L) lastRefresh else 0L  // ⭐ 0L
            }
            val today = Calendar.getInstance()
            
            val dateChanged = if (lastRefresh == 0L) {  // ⭐ 0L로 수정!
                true  // 첫 실행
            } else {
                lastDate.get(Calendar.DAY_OF_YEAR) != today.get(Calendar.DAY_OF_YEAR) ||
                lastDate.get(Calendar.YEAR) != today.get(Calendar.YEAR)
            }
            
            if (dateChanged) {
                Log.d("AlarmRefreshUtil", "🔄 날짜 변경 감지 - Native 갱신 실행")
                Log.d("AlarmRefreshUtil", "   마지막: ${lastDate.get(Calendar.YEAR)}-${lastDate.get(Calendar.MONTH)+1}-${lastDate.get(Calendar.DAY_OF_MONTH)}")
                Log.d("AlarmRefreshUtil", "   현재: ${today.get(Calendar.YEAR)}-${today.get(Calendar.MONTH)+1}-${today.get(Calendar.DAY_OF_MONTH)}")
                
                // ⭐ AlarmRefreshReceiver 트리거!
                val intent = Intent("com.example.shiftbell.REFRESH_ALARMS")
                context.sendBroadcast(intent)
                
                // ⭐ 갱신 완료 시각 저장
                prefs.edit()
                    .putLong("last_alarm_refresh", System.currentTimeMillis())
                    .apply()
                
                Log.d("AlarmRefreshUtil", "✅ Native 갱신 트리거 완료")
            } else {
                Log.d("AlarmRefreshUtil", "⏭️ 오늘 이미 갱신됨 (${today.get(Calendar.MONTH)+1}/${today.get(Calendar.DAY_OF_MONTH)}) - 스킵")
            }
        } catch (e: Exception) {
            Log.e("AlarmRefreshUtil", "❌ 갱신 체크 실패", e)
        }
    }
}









AlarmGuardReceiver.kt

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







AlarmActionReceiver.kt


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
                cancelAlarm(context, alarmId, label, soundType)
                
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8888)
            }
            "EXTEND_ALARM" -> {
                val timestamp = intent.getLongExtra("timestamp", 0L)
                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"
                Log.d("AlarmAction", "⏰ 알람 5분 연장: ID=$alarmId")
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
            putExtra("alarmId", alarmId)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId + 10000,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val extendIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = "EXTEND_ALARM"
            putExtra("alarmId", alarmId)
            putExtra("timestamp", newTimestamp)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
        }
        val extendPendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId + 20000,
            extendIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(context, "twenty_min_channel")
            .setContentTitle("알람이 $newTimeStr 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)  // ⭐ 소리/진동 안 남
            .setContentIntent(openAppPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "끄기", cancelPendingIntent)
            .addAction(android.R.drawable.ic_menu_add, "5분 후", extendPendingIntent)
            .build()
        
        notificationManager.notify(8888, notification)
        
        Log.d("AlarmAction", "📢 Notification 업데이트: $newTimeStr")
    }
}








alarm_refresh_helper.dart

// lib/services/alarm_refresh_helper.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class AlarmRefreshHelper {
  static final AlarmRefreshHelper instance = AlarmRefreshHelper._internal();
  AlarmRefreshHelper._internal();
  
  static const String KEY_LAST_REFRESH = 'last_alarm_refresh';
  
  /// 갱신이 필요한지 체크
  Future<bool> needsRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. 재부팅 감지 (무조건 갱신)
      if (await _isRebootDetected(prefs)) {
        print('🔄 갱신 필요: 재부팅 감지됨');
        return true;
      }
      
      // 2. ⭐ 날짜 변경 감지 (하루 1회 갱신)
      if (await _isDateChanged(prefs)) {
        print('🔄 갱신 필요: 날짜 변경됨');
        return true;
      }
      
      // 3. 알람 비어있음
      if (await _isAlarmEmpty()) {
        print('🔄 갱신 필요: 알람 없음');
        return true;
      }
      
      print('✅ 갱신 불필요 (오늘 이미 갱신됨)');
      return false;
    } catch (e) {
      print('❌ 갱신 체크 실패: $e');
      return true;
    }
  }
  
  /// 재부팅 감지
  Future<bool> _isRebootDetected(SharedPreferences prefs) async {
    final savedBootTime = prefs.getInt('system_boot_time') ?? 0;
    final lastBootTime = prefs.getInt('last_boot_time') ?? 0;
    
    if (savedBootTime > lastBootTime) {
      print('  - 재부팅 감지');
      return true;
    }
    
    return false;
  }
  
  /// ⭐ 날짜 변경 감지
  Future<bool> _isDateChanged(SharedPreferences prefs) async {
  final lastRefresh = prefs.getInt(KEY_LAST_REFRESH) ?? 0;
  
  if (lastRefresh == 0) {
    print('  - 첫 실행');
    
    // ⭐ 첫 실행이면 현재 시각을 저장하고 갱신 스킵
    await markRefreshed();
    return false;  // ⭐ false로 변경!
  }
  
  final lastDate = DateTime.fromMillisecondsSinceEpoch(lastRefresh);
  final today = DateTime.now();
  
  final dateChanged = lastDate.year != today.year ||
                     lastDate.month != today.month ||
                     lastDate.day != today.day;
  
  if (dateChanged) {
    print('  - 마지막 갱신: ${lastDate.year}-${lastDate.month}-${lastDate.day}');
    print('  - 현재 날짜: ${today.year}-${today.month}-${today.day}');
  }
  
  return dateChanged;
}
  
  /// 알람 비어있는지
  Future<bool> _isAlarmEmpty() async {
    final alarms = await DatabaseService.instance.getAllAlarms();
    final futureAlarms = alarms.where((a) => 
      a.date != null && a.date!.isAfter(DateTime.now())
    ).toList();
    
    print('  - 미래 알람 개수: ${futureAlarms.length}');
    
    return futureAlarms.isEmpty;
  }
  
  /// 갱신 완료 후 호출
  Future<void> markRefreshed() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await prefs.setInt(KEY_LAST_REFRESH, now);
    
    // 현재 부팅 시각도 저장
    final bootTime = prefs.getInt('system_boot_time') ?? now;
    await prefs.setInt('last_boot_time', bootTime);
    
    final date = DateTime.fromMillisecondsSinceEpoch(now);
    print('✅ 갱신 완료 기록: ${date.year}-${date.month}-${date.day}');
  }
  
  /// 시스템 부팅 시각 저장
  Future<void> saveBootTime(int bootTimeMillis) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('system_boot_time', bootTimeMillis);
  }
}












alarm_refresh_service.dart


// lib/services/alarm_refresh_service.dart

import 'database_service.dart';
import 'alarm_service.dart';
import '../models/alarm.dart';
import '../models/shift_schedule.dart';
import 'alarm_refresh_helper.dart';

class AlarmRefreshService {
  static final AlarmRefreshService instance = AlarmRefreshService._internal();
  AlarmRefreshService._internal();
  
  bool _isRefreshing = false;
  
  /// 조건 체크 후 필요하면 갱신
  Future<void> refreshIfNeeded() async {
    if (_isRefreshing) {
      print('⏭️ 이미 갱신 중...');
      return;
    }
    
    try {
      _isRefreshing = true;
      
      // 갱신 필요 여부 체크
      final needsRefresh = await AlarmRefreshHelper.instance.needsRefresh();
      
      if (!needsRefresh) {
        print('⏭️ 갱신 스킵');
        return;
      }
      
      print('🔄 알람 갱신 시작...');
      
      await _refresh10DaysAlarms();
      
      // 갱신 완료 표시
      await AlarmRefreshHelper.instance.markRefreshed();
      
      print('✅ 알람 갱신 완료');
    } catch (e) {
      print('❌ 알람 갱신 실패: $e');
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// 강제 갱신 (조건 체크 없이)
  Future<void> forceRefresh() async {
    if (_isRefreshing) {
      print('⏭️ 이미 갱신 중...');
      return;
    }
    
    try {
      _isRefreshing = true;
      print('🔄 강제 갱신 시작...');
      
      await _refresh10DaysAlarms();
      await AlarmRefreshHelper.instance.markRefreshed();
      
      print('✅ 강제 갱신 완료');
    } catch (e) {
      print('❌ 강제 갱신 실패: $e');
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// 30일치 알람 재생성
  Future<void> _refresh10DaysAlarms() async {  // 30 → 10
  print('🔄 10일치 알람 갱신 시작...');  // 로그 수정
  
  // 1. 기존 Native 알람 전부 취소
  final existingAlarms = await DatabaseService.instance.getAllAlarms();
  for (var alarm in existingAlarms) {
    if (alarm.id != null) {
      await AlarmService().cancelAlarm(alarm.id!);
    }
  }
  
  // 2. DB 알람 전부 삭제
  await DatabaseService.instance.deleteAllAlarms();
  
  print('🗑️ 기존 알람 전부 삭제');
  
  // 3. 스케줄 조회
  final schedule = await DatabaseService.instance.getShiftSchedule();
  if (schedule == null) {
    print('⚠️ 스케줄 없음 - 갱신 중단');
    return;
  }
  
  if (!schedule.isRegular) {
    print('⚠️ 불규칙 근무 - 자동 갱신 안 함');
    return;
  }
  
  // 4. 템플릿 조회
  final templates = await DatabaseService.instance.getAllAlarmTemplates();
  if (templates.isEmpty) {
    print('⚠️ 템플릿 없음 - 갱신 중단');
    return;
  }
  
  // 5. ⭐ 10일치 생성
  final List<Alarm> newAlarms = [];
  final today = DateTime.now();
  
  for (var i = 0; i < 10; i++) {  // ⭐ 30 → 10
    final date = today.add(Duration(days: i));
    final shiftType = schedule.getShiftForDate(date);
    
    if (shiftType == '미설정') continue;
    
    final shiftTemplates = templates.where((t) => t.shiftType == shiftType).toList();
    
    for (var template in shiftTemplates) {
      final timeParts = template.time.split(':');
      final alarmTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      
      // 과거 알람 스킵
      if (alarmTime.isBefore(DateTime.now().subtract(Duration(minutes: 1)))) {
        continue;
      }
      
      final alarm = Alarm(
        time: template.time,
        date: alarmTime,
        type: 'fixed',
        alarmTypeId: template.alarmTypeId,
        shiftType: shiftType,
      );
      
      newAlarms.add(alarm);
    }
  }
  
  print('📝 생성할 알람: ${newAlarms.length}개');
  
  if (newAlarms.isEmpty) {
    print('⚠️ 생성할 알람 없음');
    return;
  }
  
  // 6. DB 저장
  await DatabaseService.instance.insertAlarmsInBatch(newAlarms);
  
  // 7. 저장된 알람 다시 읽어서 Native 등록
  final savedAlarms = await DatabaseService.instance.getAllAlarms();
  int registeredCount = 0;
  
  for (var alarm in savedAlarms) {
    if (alarm.date != null && alarm.date!.isAfter(DateTime.now())) {
      await AlarmService().scheduleAlarm(
        id: alarm.id!,
        dateTime: alarm.date!,
        label: alarm.shiftType ?? '알람',
        soundType: 'loud',
      );
      registeredCount++;
    }
  }
  
  print('✅ ${registeredCount}개 알람 Native 등록 완료');
}
}









DirectBootReceiver.kt

// android/app/src/main/kotlin/com/example/shiftbell/DirectBootReceiver.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

class DirectBootReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
        return
    }
    
    Log.e("DirectBoot", "========== LOCKED BOOT DETECTED ==========")
    
    try {
        // 기존 로직 (긴급 알람 등록)
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        
        saveBootTime(deviceContext)
        
        val nextAlarm = getNextAlarmFromDB(context)
        
        if (nextAlarm != null) {
            scheduleNativeAlarm(
                context = context,
                id = nextAlarm.id,
                timestamp = nextAlarm.timestamp,
                label = nextAlarm.shiftType
            )
            
            Log.e("DirectBoot", "✅ 긴급 알람 등록: ${nextAlarm.shiftType} ${nextAlarm.time}")
        } else {
            Log.e("DirectBoot", "⚠️ 등록할 알람 없음")
        }
        
        // ⭐ 신규: Foreground Service 시작하여 프로세스 유지
        try {
            val serviceIntent = Intent(context, DirectBootGuardService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.e("DirectBoot", "✅ Guard Service 시작 (프로세스 유지)")
        } catch (e: Exception) {
            Log.e("DirectBoot", "❌ Guard Service 시작 실패", e)
        }
        
        Log.e("DirectBoot", "========== DIRECT BOOT COMPLETE ==========")
    } catch (e: Exception) {
        Log.e("DirectBoot", "========== ERROR ==========", e)
    }
}
    
    private fun saveBootTime(context: Context) {
        val prefs = context.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        val bootTime = System.currentTimeMillis()
        prefs.edit().putLong("last_boot_time", bootTime).apply()
        
        Log.d("DirectBoot", "📝 부팅 시각 저장: ${Date(bootTime)}")
    }
    
    private fun getNextAlarmFromDB(context: Context): AlarmData? {
        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase
            
            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.getDefault()
            ).format(Date())
            
            Log.d("DirectBoot", "현재 시각: $now")
            
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
                val time = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                
                val timestamp = SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss",
                    Locale.getDefault()
                ).parse(dateStr)?.time
                
                if (timestamp != null) {
                    alarm = AlarmData(id, timestamp, time, shiftType)
                    Log.d("DirectBoot", "✅ 다음 알람 조회: $time ($shiftType)")
                }
            } else {
                Log.d("DirectBoot", "⚠️ DB에 알람 없음")
            }
            
            cursor.close()
            db.close()
            
            alarm
        } catch (e: Exception) {
            Log.e("DirectBoot", "DB 읽기 실패", e)
            null
        }
    }
    
    private fun scheduleNativeAlarm(
        context: Context,
        id: Int,
        timestamp: Long,
        label: String
    ) {
        try {
            val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                putExtra(CustomAlarmReceiver.EXTRA_ID, id)
                putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
                putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                setPackage(context.packageName)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // ⭐ setAlarmClock 사용
            val alarmClockInfo = AlarmManager.AlarmClockInfo(timestamp, pendingIntent)
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            
            Log.d("DirectBoot", "✅ Native 알람 등록 (AlarmClock): ID=$id, timestamp=$timestamp")
        } catch (e: Exception) {
            Log.e("DirectBoot", "Native 알람 등록 실패: ID=$id", e)
        }
    }
    
    data class AlarmData(
        val id: Int,
        val timestamp: Long,
        val time: String,
        val shiftType: String
    )
}









AlarmActionReceiver.kt


// android/app/src/main/kotlin/com/example/shiftbell/AlarmActionReceiver.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("alarmId", 0)
        
        when (intent.action) {
            "CANCEL_ALARM" -> {
                Log.d("AlarmAction", "🗑️ 알람 취소: ID=$alarmId")
                
                // ⭐ Intent에서 Extra 정보 가져오기
                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"
                
                cancelAlarm(context, alarmId, label, soundType)
                
                // 20분 전 알림 제거
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8888)
            }
            "EXTEND_ALARM" -> {
                val timestamp = intent.getLongExtra("timestamp", 0L)
                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"
                
                Log.d("AlarmAction", "⏰ 알람 5분 연장: ID=$alarmId")
                extendAlarm(context, alarmId, timestamp, label, soundType)
                
                // 20분 전 알림 제거
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8888)
            }
        }
    }
    
    // ⭐ Extra 파라미터 추가
    private fun cancelAlarm(context: Context, alarmId: Int, label: String, soundType: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // ⭐ 동일한 Extra로 Intent 생성
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
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
        
        // DB에서도 삭제
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
            db.close()
            Log.d("AlarmAction", "✅ DB 알람 삭제 완료: ID=$alarmId")
            
            // ⭐ Flutter 갱신 트리거
            AlarmRefreshWorker.triggerRefresh(context)
            Log.d("AlarmAction", "✅ Flutter 갱신 트리거 완료")
            
            // ⭐ AlarmGuardReceiver 즉시 재실행 (다음 알람 체크)
            val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
            context.sendBroadcast(guardIntent)
            Log.d("AlarmAction", "✅ AlarmGuardReceiver 즉시 재실행")
            
        } catch (e: Exception) {
            Log.e("AlarmAction", "❌ DB 삭제 실패", e)
        }
    }
    
    // ⭐ Extra 파라미터 추가
    private fun extendAlarm(context: Context, alarmId: Int, originalTimestamp: Long, label: String, soundType: String) {
        val newTimestamp = originalTimestamp + (5 * 60 * 1000) // +5분
        
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // ⭐ 1단계: 기존 알람 명시적으로 취소
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
        
        // ⭐ 2단계: 새 알람 등록
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
        
        // DB 업데이트
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            
            val dateStr = java.text.SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                java.util.Locale.getDefault()
            ).format(java.util.Date(newTimestamp))
            
            val values = android.content.ContentValues().apply {
                put("date", dateStr)
            }
            
            db.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))
            db.close()
            Log.d("AlarmAction", "✅ DB 업데이트 완료: ID=$alarmId")
            
            // ⭐ Flutter 갱신 트리거
            AlarmRefreshWorker.triggerRefresh(context)
            Log.d("AlarmAction", "✅ Flutter 갱신 트리거 완료")
            
            // ⭐ AlarmGuardReceiver 즉시 재실행 (다음 알람 체크)
            val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
            context.sendBroadcast(guardIntent)
            Log.d("AlarmAction", "✅ AlarmGuardReceiver 즉시 재실행")
            
        } catch (e: Exception) {
            Log.e("AlarmAction", "❌ DB 업데이트 실패", e)
        }
    }
}















alarm_history.dart


class AlarmHistory {
  final int? id;
  final int alarmId;
  final String scheduledTime;
  final DateTime scheduledDate;
  final DateTime actualRingTime;
  final String dismissType;  // 'swiped', 'snoozed', 'timeout', 'ringing'
  final int snoozeCount;
  final String? shiftType;
  final DateTime createdAt;

  AlarmHistory({
    this.id,
    required this.alarmId,
    required this.scheduledTime,
    required this.scheduledDate,
    required this.actualRingTime,
    required this.dismissType,
    required this.snoozeCount,
    this.shiftType,
    required this.createdAt,
  });

  factory AlarmHistory.fromMap(Map<String, dynamic> map) {
    return AlarmHistory(
      id: map['id'],
      alarmId: map['alarm_id'],
      scheduledTime: map['scheduled_time'],
      scheduledDate: DateTime.parse(map['scheduled_date']),
      actualRingTime: DateTime.parse(map['actual_ring_time']),
      dismissType: map['dismiss_type'],
      snoozeCount: map['snooze_count'] ?? 0,
      shiftType: map['shift_type'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  String get dismissTypeText {
    switch (dismissType) {
      case 'swiped':
        return '스와이프로 끔';
      case 'snoozed':
        return '스누즈 ${snoozeCount}회';
      case 'timeout':
        return '자동 종료 (놓침)';
      case 'ringing':
        return '울리는 중...';
      default:
        return dismissType;
    }
  }
}















AlarmRefreshReceiver.kt


package com.example.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

class AlarmRefreshReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmRefresh", "========== 자정 갱신 시작 ==========")
        
        try {
            // 1. 스케줄 체크 (규칙적인지 확인)
            if (!isRegularSchedule(context)) {
                Log.d("AlarmRefresh", "⏭️ 불규칙 스케줄 - 갱신 스킵")
                return
            }
            
            // 2. 기존 알람 전부 삭제
            deleteAllAlarms(context)
            
            // 3. 10일치 알람 재생성
            generate10DaysAlarms(context)
            
            // 4. 갱신 완료 표시 (Flutter용)
            markRefreshed(context)
            
            // 5. Flutter UI 갱신 트리거 (앱 켜져있으면)
            notifyFlutter(context)
            
            Log.d("AlarmRefresh", "========== 자정 갱신 완료 ==========")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "========== 갱신 실패 ==========", e)
        }
    }
    
    // 규칙적 스케줄인지 확인
    private fun isRegularSchedule(context: Context): Boolean {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase
            
            val cursor = db.query("shift_schedule", null, null, null, null, null, null, "1")
            
            if (!cursor.moveToFirst()) {
                cursor.close()
                db.close()
                return false
            }
            
            val isRegular = cursor.getInt(cursor.getColumnIndexOrThrow("is_regular")) == 1
            cursor.close()
            db.close()
            
            return isRegular
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "스케줄 조회 실패", e)
            return false
        }
    }
    
    // 기존 알람 전부 삭제
    private fun deleteAllAlarms(context: Context) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            
            // DB에서 모든 알람 조회
            val cursor = db.query("alarms", null, null, null, null, null, null)
            val alarmIds = mutableListOf<Int>()
            
            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                alarmIds.add(id)
            }
            cursor.close()
            
            // Native 알람 취소
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (id in alarmIds) {
                val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$id")
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    id,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
            }
            
            // DB에서 삭제
            db.delete("alarms", null, null)
            db.close()
            
            Log.d("AlarmRefresh", "🗑️ 기존 알람 ${alarmIds.size}개 삭제 완료")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "알람 삭제 실패", e)
        }
    }
    
    // 10일치 알람 생성
    private fun generate10DaysAlarms(context: Context) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            
            // 1. 스케줄 조회
            val scheduleCursor = db.query("shift_schedule", null, null, null, null, null, null, "1")
            if (!scheduleCursor.moveToFirst()) {
                scheduleCursor.close()
                return
            }
            
            val pattern = scheduleCursor.getString(scheduleCursor.getColumnIndexOrThrow("pattern")).split(",")
            val todayIndex = scheduleCursor.getInt(scheduleCursor.getColumnIndexOrThrow("today_index"))
            val startDateStr = scheduleCursor.getString(scheduleCursor.getColumnIndexOrThrow("start_date"))
            scheduleCursor.close()
            
            // 2. 템플릿 조회
            val templateCursor = db.query("shift_alarm_templates", null, null, null, null, null, null)
            val templates = mutableMapOf<String, MutableList<Pair<String, Int>>>()
            
            while (templateCursor.moveToNext()) {
                val shiftType = templateCursor.getString(templateCursor.getColumnIndexOrThrow("shift_type"))
                val time = templateCursor.getString(templateCursor.getColumnIndexOrThrow("time"))
                val alarmTypeId = templateCursor.getInt(templateCursor.getColumnIndexOrThrow("alarm_type_id"))
                
                if (!templates.containsKey(shiftType)) {
                    templates[shiftType] = mutableListOf()
                }
                templates[shiftType]?.add(Pair(time, alarmTypeId))
            }
            templateCursor.close()
            
            // 3. 10일치 생성
            val today = Calendar.getInstance()
            val startDate = Calendar.getInstance().apply {
                time = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).parse(startDateStr)!!
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            var createdCount = 0
            
            for (i in 0 until 10) {
                val targetDate = Calendar.getInstance().apply {
                    timeInMillis = today.timeInMillis
                    add(Calendar.DAY_OF_MONTH, i)
                }
                
                // 패턴에서 근무 종류 찾기
                val daysDiff = ((targetDate.timeInMillis - startDate.timeInMillis) / (24 * 60 * 60 * 1000)).toInt()
                val patternIndex = ((todayIndex + daysDiff) % pattern.size + pattern.size) % pattern.size
                val shiftType = pattern[patternIndex]
                
                // 해당 근무의 알람 템플릿 찾기
                val shiftTemplates = templates[shiftType] ?: continue
                
                for ((time, alarmTypeId) in shiftTemplates) {
                    val timeParts = time.split(":")
                    val alarmTime = Calendar.getInstance().apply {
                        timeInMillis = targetDate.timeInMillis
                        set(Calendar.HOUR_OF_DAY, timeParts[0].toInt())
                        set(Calendar.MINUTE, timeParts[1].toInt())
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    
                    // 과거 알람 스킵
                    if (alarmTime.timeInMillis < System.currentTimeMillis() - 60000) {
                        continue
                    }
                    
                    // DB 저장
                    val values = android.content.ContentValues().apply {
                        put("time", time)
                        put("date", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(alarmTime.time))
                        put("type", "fixed")
                        put("alarm_type_id", alarmTypeId)
                        put("shift_type", shiftType)
                    }
                    
                    val alarmId = db.insert("alarms", null, values).toInt()
                    
                    // Native 알람 등록
                    val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                        data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                        putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
                        putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
                        putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
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
                            alarmTime.timeInMillis,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP,
                            alarmTime.timeInMillis,
                            pendingIntent
                        )
                    }
                    
                    createdCount++
                }
            }
            
            db.close()
            Log.d("AlarmRefresh", "✅ ${createdCount}개 알람 생성 완료")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "알람 생성 실패", e)
        }
    }
    
    // 갱신 완료 표시 (Flutter용)
    // AlarmRefreshReceiver.kt - markRefreshed() 수정

private fun markRefreshed(context: Context) {
    try {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        
        val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        
        // ⭐ alarm_state에만 저장 (Flutter SharedPreferences와 분리)
        prefs.edit()
            .putLong("last_alarm_refresh", now)
            .apply()
        
        val date = Calendar.getInstance().apply { timeInMillis = now }
        Log.d("AlarmRefresh", "✅ 갱신 완료 표시: ${date.get(Calendar.YEAR)}-${date.get(Calendar.MONTH)+1}-${date.get(Calendar.DAY_OF_MONTH)}")
    } catch (e: Exception) {
        Log.e("AlarmRefresh", "갱신 표시 실패", e)
    }
}
    
    // Flutter에 갱신 알림 (앱 켜져있으면)
    private fun notifyFlutter(context: Context) {
        try {
            val intent = Intent("com.example.shiftbell.FLUTTER_REFRESH")
            context.sendBroadcast(intent)
            Log.d("AlarmRefresh", "📢 Flutter 갱신 트리거")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "Flutter 알림 실패", e)
        }
    }
}
