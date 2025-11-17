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