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