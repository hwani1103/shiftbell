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