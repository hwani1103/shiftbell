package com.example.shiftbell

import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
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

    companion object {
        const val ACTION_DISMISS_OVERLAY = "com.example.shiftbell.DISMISS_OVERLAY"
        const val ACTION_SNOOZE_OVERLAY = "com.example.shiftbell.SNOOZE_OVERLAY"
        const val EXTRA_ALARM_ID = "alarmId"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: android.view.View? = null
    private var alarmId: Int = 0
    private var alarmTimeStr: String = ""  // 알람 시간 저장
    private var alarmLabel: String = "알람"  // 알람 라벨 저장
    private var timeoutHandler: Handler? = null
    private var timeoutRunnable: Runnable? = null
    private var alarmDuration: Int = 5  // 기본 5분

    // 외부에서 Overlay 종료/스누즈 신호를 받기 위한 BroadcastReceiver
    private val overlayActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val targetAlarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)

            // 현재 Overlay의 알람 ID와 일치하는 경우에만 처리
            if (targetAlarmId != alarmId && targetAlarmId != -1) {
                Log.d("AlarmOverlay", "⚠️ 다른 알람 ID 무시: target=$targetAlarmId, current=$alarmId")
                return
            }

            when (intent.action) {
                ACTION_DISMISS_OVERLAY -> {
                    Log.d("AlarmOverlay", "📥 외부에서 DISMISS 신호 수신: ID=$alarmId")
                    dismissAlarmFromExternal()
                }
                ACTION_SNOOZE_OVERLAY -> {
                    Log.d("AlarmOverlay", "📥 외부에서 SNOOZE 신호 수신: ID=$alarmId")
                    snoozeAlarmFromExternal()
                }
            }
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        alarmId = intent?.getIntExtra("alarmId", 0) ?: 0

        // Overlay 권한 체크
        if (!canDrawOverlays()) {
            Log.e("AlarmOverlayService", "Overlay 권한 없음!")
            stopSelf()
            return START_NOT_STICKY
        }

        // ⭐ 외부 종료 신호를 받기 위한 BroadcastReceiver 등록
        val filter = IntentFilter().apply {
            addAction(ACTION_DISMISS_OVERLAY)
            addAction(ACTION_SNOOZE_OVERLAY)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(overlayActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(overlayActionReceiver, filter)
        }
        Log.d("AlarmOverlay", "📡 외부 신호 리시버 등록")

        // DB에서 알람 정보 조회
        loadAlarmInfo()

        showOverlay()
        startTimeoutTimer()

        return START_NOT_STICKY
    }

    // 외부에서 호출된 DISMISS (소리만 중지, DB 작업은 이미 외부에서 처리됨)
    private fun dismissAlarmFromExternal() {
        cancelTimeoutTimer()
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        removeOverlay()
        stopSelf()
        Log.d("AlarmOverlay", "✅ 외부 신호로 Overlay 종료")
    }

    // 외부에서 호출된 SNOOZE (소리만 중지, DB 작업은 이미 외부에서 처리됨)
    private fun snoozeAlarmFromExternal() {
        cancelTimeoutTimer()
        AlarmPlayer.getInstance(applicationContext).stopAlarm()
        removeOverlay()
        stopSelf()
        Log.d("AlarmOverlay", "✅ 외부 신호로 Overlay 종료 (스누즈)")
    }

    private fun loadAlarmInfo() {
        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            val db = dbHelper.readableDatabase

            val cursor = db.query(
                "alarms",
                arrayOf("time", "shift_type", "alarm_type_id"),
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            if (cursor.moveToFirst()) {
                alarmTimeStr = cursor.getString(cursor.getColumnIndexOrThrow("time")) ?: ""
                alarmLabel = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                val alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id"))

                // alarm_type_id로 duration 조회
                val typeCursor = db.query(
                    "alarm_types",
                    arrayOf("duration"),
                    "id = ?",
                    arrayOf(alarmTypeId.toString()),
                    null, null, null
                )

                if (typeCursor.moveToFirst()) {
                    alarmDuration = typeCursor.getInt(typeCursor.getColumnIndexOrThrow("duration"))
                }
                typeCursor.close()
            }
            cursor.close()
            db.close()

            Log.d("AlarmOverlay", "✅ 알람 정보 로드: time=$alarmTimeStr, label=$alarmLabel, duration=${alarmDuration}분")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ 알람 정보 로드 실패", e)
        }
    }

    private fun startTimeoutTimer() {
        timeoutHandler = Handler(Looper.getMainLooper())
        timeoutRunnable = Runnable {
            Log.d("AlarmOverlay", "⏰ 타임아웃: ${alarmDuration}분 경과")
            timeoutAlarm()
        }

        timeoutHandler?.postDelayed(timeoutRunnable!!, (alarmDuration * 60 * 1000).toLong())
        Log.d("AlarmOverlay", "⏱️ 타임아웃 타이머 시작: ${alarmDuration}분")
    }

    private fun cancelTimeoutTimer() {
        timeoutRunnable?.let {
            timeoutHandler?.removeCallbacks(it)
        }
        Log.d("AlarmOverlay", "⏱️ 타임아웃 타이머 취소")
    }

    private fun timeoutAlarm() {
        Log.d("AlarmOverlay", "⏰ 알람 타임아웃 - 자동 종료")

        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()

        // DB에서 알람 삭제
        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            val db = dbHelper.writableDatabase
            db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))

            // 알람 이력 업데이트
            val values = android.content.ContentValues().apply {
                put("dismiss_type", "timeout")
            }
            db.update(
                "alarm_history",
                values,
                "alarm_id = ? AND dismiss_type = 'ringing'",
                arrayOf(alarmId.toString())
            )

            db.close()
            Log.d("AlarmOverlay", "✅ DB 알람 삭제 및 이력 업데이트: ID=$alarmId")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ DB 작업 실패", e)
        }

        // shownNotifications에서 제거
        AlarmGuardReceiver.removeShownNotification(alarmId)

        // ⭐ Timeout Notification 표시 (삭제 대신 텍스트 변경)
        showTimeoutNotification()

        // 갱신 체크
        AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

        // AlarmGuardReceiver 트리거
        val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
        sendBroadcast(guardIntent)

        // Overlay 제거
        removeOverlay()

        // 서비스 종료
        stopSelf()
    }

    private fun showTimeoutNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // ⭐ 스누즈/타임아웃 전용 채널 (드롭다운 버튼 없음)
            val channel = NotificationChannel(
                "alarm_result_channel_v2",
                "알람 결과 알림",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "알람 스누즈/타임아웃 결과"
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

        val notification = NotificationCompat.Builder(this, "alarm_result_channel_v2")
            .setContentTitle("$alarmTimeStr 알람이 timeout되었습니다")
            .setContentText(alarmLabel)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)  // ⭐ STATUS로 변경 (드롭다운 방지)
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)  // ⭐ 드롭다운 스누즈 방지
            .setContentIntent(openAppPendingIntent)
            .build()

        notificationManager.notify(8889, notification)
        Log.d("AlarmOverlay", "📢 Timeout Notification 표시: $alarmTimeStr")
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
    cancelTimeoutTimer()

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
    
    // Notification 삭제 (8888: 20분전, 8889: 스누즈/타임아웃)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)
    notificationManager.cancel(8888)
    notificationManager.cancel(8889)
    Log.d("AlarmOverlay", "📢 Notification 삭제 (8888, 8889)")

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
        cancelTimeoutTimer()

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

                // ⭐ shownNotifications에서 제거 (스누즈된 알람도 다시 Notification 표시 위해)
                AlarmGuardReceiver.removeShownNotification(alarmId)

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

        // ⭐ 스누즈/타임아웃 전용 채널
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "alarm_result_channel_v2",
                "알람 결과 알림",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "알람 스누즈/타임아웃 결과"
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

        val notification = NotificationCompat.Builder(this, "alarm_result_channel_v2")
            .setContentTitle("알람이 $newTimeStr 로 연장되었습니다")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppPendingIntent)
            .build()

        notificationManager.notify(8889, notification)
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
        cancelTimeoutTimer()

        // ⭐ BroadcastReceiver 해제
        try {
            unregisterReceiver(overlayActionReceiver)
            Log.d("AlarmOverlay", "📡 외부 신호 리시버 해제")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "리시버 해제 실패 (이미 해제됨)", e)
        }

        removeOverlay()
    }
}