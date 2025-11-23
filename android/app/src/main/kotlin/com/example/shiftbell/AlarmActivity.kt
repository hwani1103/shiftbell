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

    // ⭐ Notification 삭제 (alarmId + 20분전 Notification)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)
    notificationManager.cancel(8888)
    Log.d("AlarmActivity", "📢 Notification 삭제")

    // ⭐ shownNotifications에서 제거 (다음 알람 Notification 표시 위해)
    AlarmGuardReceiver.removeShownNotification(alarmId)

    // ⭐ 갱신 체크 (Native에서 직접!)
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

    // ⭐ AlarmGuardReceiver 트리거 (다음 알람 Notification 즉시 표시)
    val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
    sendBroadcast(guardIntent)
    Log.d("AlarmActivity", "✅ AlarmGuardReceiver 트리거")

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