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
import android.app.NotificationChannel
import android.app.PendingIntent
import androidx.core.app.NotificationCompat

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
    
    // ⭐ DB 작업 통합 (한 번에 처리)
    try {
        val dbHelper = DatabaseHelper.getInstance(applicationContext)
        val db = dbHelper.writableDatabase
        
        // 1. 알람 삭제
        db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        Log.d("AlarmOverlay", "✅ DB 알람 삭제: ID=$alarmId")
        
        // 2. 알람 이력 업데이트
        val values = android.content.ContentValues().apply {
            put("dismiss_type", "swiped")
        }
        db.update(
            "alarm_history",
            values,
            "alarm_id = ? AND dismiss_type = 'ringing'",
            arrayOf(alarmId.toString())
        )
        Log.d("AlarmOverlay", "✅ 알람 이력 업데이트: swiped")
        
        db.close()
        
    } catch (e: Exception) {
        Log.e("AlarmOverlay", "❌ DB 작업 실패", e)
    }
    
    // Notification 삭제
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)
    notificationManager.cancel(8888)
    Log.d("AlarmOverlay", "📢 Notification 삭제")

    // ⭐ shownNotifications에서 제거 (다음 알람 Notification 표시 위해)
    AlarmGuardReceiver.removeShownNotification(alarmId)

    // ⭐ 갱신 체크
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

    // ⭐ AlarmGuardReceiver 재실행 (다음 알람 Notification 표시)
    val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
    sendBroadcast(guardIntent)

    // ⭐ 앱 포그라운드로 가져와서 Flutter UI 즉시 갱신
    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
    launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    startActivity(launchIntent)
    Log.d("AlarmOverlay", "✅ 앱 포그라운드 이동 → Flutter UI 갱신")

    // Overlay 제거
    removeOverlay()

    // 서비스 종료
    stopSelf()
}
    
    private fun snoozeAlarm() {
        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()

        // 5분 후 알람 재등록
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
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                cursor.close()

                // 5분 후 시간 계산
                val newTimestamp = System.currentTimeMillis() + (5 * 60 * 1000)

                // 기존 알람 취소
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                val cancelIntent = Intent(this, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                }
                val cancelPendingIntent = android.app.PendingIntent.getBroadcast(
                    this,
                    alarmId,
                    cancelIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(cancelPendingIntent)
                cancelPendingIntent.cancel()
                Log.d("AlarmOverlay", "✅ 기존 알람 취소: ID=$alarmId")

                // 새 알람 등록
                val newIntent = Intent(this, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                    putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
                    putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
                    putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                }

                val newPendingIntent = android.app.PendingIntent.getBroadcast(
                    this,
                    alarmId,
                    newIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        android.app.AlarmManager.RTC_WAKEUP,
                        newTimestamp,
                        newPendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        android.app.AlarmManager.RTC_WAKEUP,
                        newTimestamp,
                        newPendingIntent
                    )
                }
                Log.d("AlarmOverlay", "✅ 5분 후 알람 등록: ID=$alarmId, 시각=${Date(newTimestamp)}")

                // DB 업데이트 (time, date 필드)
                val writableDb = dbHelper.writableDatabase
                val dateStr = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date(newTimestamp))
                val timeStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(newTimestamp))

                val values = android.content.ContentValues().apply {
                    put("date", dateStr)
                    put("time", timeStr)
                }
                writableDb.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))
                Log.d("AlarmOverlay", "✅ DB 업데이트: time=$timeStr, date=$dateStr")

                // 알람 이력 업데이트 (snooze_count 증가)
                writableDb.execSQL(
                    "UPDATE alarm_history SET dismiss_type = 'snoozed', snooze_count = snooze_count + 1 WHERE alarm_id = ? AND dismiss_type = 'ringing'",
                    arrayOf(alarmId)
                )
                Log.d("AlarmOverlay", "✅ 알람 이력 업데이트: snoozed")

                writableDb.close()

                // 갱신 체크
                AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

                // AlarmGuardReceiver 재실행
                val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
                sendBroadcast(guardIntent)

                // ⭐ 연장 Notification 표시
                showUpdatedNotification(newTimestamp, timeStr, shiftType)

                // ⭐ 앱 포그라운드로 가져와서 Flutter UI 즉시 갱신
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                startActivity(launchIntent)
                Log.d("AlarmOverlay", "✅ 앱 포그라운드 이동 → Flutter UI 갱신")

            } else {
                cursor.close()
                Log.e("AlarmOverlay", "❌ 알람 정보 없음: ID=$alarmId")
            }

            db.close()

        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ 5분 후 재등록 실패", e)
        }

        // Overlay 제거
        removeOverlay()

        // 서비스 종료
        stopSelf()
    }

    private fun showUpdatedNotification(newTimestamp: Long, newTimeStr: String, label: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 채널 생성 (Android O 이상)
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

        // 앱 열기 Intent
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

        // 끄기 액션
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

        // 5분 후 액션
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
            .setContentTitle("알람이 $newTimeStr 로 연장되었습니다")
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
        Log.d("AlarmOverlay", "📢 연장 Notification 표시: $newTimeStr")
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