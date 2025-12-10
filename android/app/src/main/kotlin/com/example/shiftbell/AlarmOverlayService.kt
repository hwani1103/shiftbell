package com.example.shiftbell

import android.app.KeyguardManager
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
import android.view.View
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
    private var isOverlayVisible: Boolean = false  // ⭐ Overlay 표시 상태

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

        // ⭐ Overlay 즉시 표시 (잠금 해제 상태에서만 사용)
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
        var cursor: android.database.Cursor? = null
        var typeCursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            db = dbHelper.readableDatabase

            cursor = db.query(
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
                typeCursor = db.query(
                    "alarm_types",
                    arrayOf("duration"),
                    "id = ?",
                    arrayOf(alarmTypeId.toString()),
                    null, null, null
                )

                if (typeCursor.moveToFirst()) {
                    alarmDuration = typeCursor.getInt(typeCursor.getColumnIndexOrThrow("duration"))
                }
            }

            Log.d("AlarmOverlay", "✅ 알람 정보 로드: time=$alarmTimeStr, label=$alarmLabel, duration=${alarmDuration}분")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ 알람 정보 로드 실패", e)
        } finally {
            typeCursor?.close()
            cursor?.close()
            db?.close()
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

        // ⭐ CRITICAL FIX: Native 알람 먼저 취소 (유령 알람 방지!)
        cancelNativeAlarm()

        // ⭐ BUG FIX: 이력 먼저 생성 (DB에 알람 데이터가 있을 때!)
        createAlarmHistory(alarmId, "timeout")

        // DB에서 알람 삭제 (이력 생성 후!)
        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            val db = dbHelper.writableDatabase
            db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
            db.close()
            Log.d("AlarmOverlay", "✅ DB 알람 삭제: ID=$alarmId")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ DB 삭제 실패", e)
        }

        // shownNotifications에서 제거
        AlarmGuardReceiver.removeShownNotification(alarmId)

        // ⭐ HIGH FIX #7: Notification 삭제 (모든 관련 notification 정리)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(alarmId)          // 알람 ID
        notificationManager.cancel(alarmId + 100000) // Fallback notification
        notificationManager.cancel(7777)             // 제어
        notificationManager.cancel(8888)             // 20분 전
        notificationManager.cancel(8889)             // 스누즈/타임아웃
        Log.d("AlarmOverlay", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8888, 8889)")

        // 갱신 체크
        AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

        // ⭐ 다음 알람의 8888 Notification 표시 (직접 호출)
        AlarmGuardReceiver.triggerCheck(this)
        Log.d("AlarmOverlay", "✅ AlarmGuardReceiver.triggerCheck() → 다음 알람 8888 표시")

        // Overlay 제거
        removeOverlay()

        // 서비스 종료
        stopSelf()
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
    
    // ⭐ Overlay View 준비 (생성만 하고 표시하지 않음)
    private fun prepareOverlay() {
        Log.d("AlarmOverlay", "🔧 prepareOverlay() 호출: overlayView=${overlayView != null}")

        if (overlayView != null) {
            Log.d("AlarmOverlay", "⚠️ overlayView 이미 존재 → 재사용")
            return
        }

        try {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            // Overlay View 생성
            overlayView = LayoutInflater.from(this).inflate(R.layout.overlay_alarm, null)

            // ⭐ 알람 설정 시간 표시 (현재 시간 아님!)
            val timeText = overlayView?.findViewById<TextView>(R.id.timeText)
            timeText?.text = alarmTimeStr

            // 근무 타입 설정
            val shiftTypeText = overlayView?.findViewById<TextView>(R.id.shiftTypeText)
            shiftTypeText?.text = alarmLabel

            // 끄기 버튼
            overlayView?.findViewById<Button>(R.id.dismissButton)?.setOnClickListener {
                Log.d("AlarmOverlay", "👆 끄기 버튼 클릭")
                dismissAlarm()
            }

            // 5분 후 버튼
            overlayView?.findViewById<Button>(R.id.snoozeButton)?.setOnClickListener {
                Log.d("AlarmOverlay", "👆 5분 후 버튼 클릭")
                snoozeAlarm()
            }

            Log.d("AlarmOverlay", "✅ Overlay View 준비 완료 (미표시)")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ Overlay View 준비 실패", e)
        }
    }

    // ⭐ Overlay Window 표시 (windowManager에 추가)
    private fun showOverlayWindow() {
        Log.d("AlarmOverlay", "🔔 showOverlayWindow() 호출: isOverlayVisible=$isOverlayVisible, overlayView=${overlayView != null}")

        if (isOverlayVisible) {
            Log.d("AlarmOverlay", "⚠️ 이미 표시 중 → 스킵")
            return
        }

        if (overlayView == null) {
            Log.d("AlarmOverlay", "🔧 overlayView가 null → prepareOverlay() 호출")
            prepareOverlay()
        }

        if (overlayView == null) {
            Log.e("AlarmOverlay", "❌ prepareOverlay() 후에도 overlayView가 null!")
            return
        }

        try {
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
            isOverlayVisible = true

            Log.d("AlarmOverlay", "✅ Overlay Window 표시 완료!")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ Overlay Window 표시 실패", e)
        }
    }

    // ⭐ Overlay 전체 표시 (View 생성 + Window 추가)
    private fun showOverlay() {
        prepareOverlay()
        showOverlayWindow()
    }
    
    private fun dismissAlarm() {
    cancelTimeoutTimer()

    // 알람 소리 중지
    AlarmPlayer.getInstance(applicationContext).stopAlarm()

    // ⭐ 알람 정보 먼저 읽어서 저장 (이력 생성용)
    var scheduledTime = ""
    var scheduledDate = ""
    var shiftType = ""

    var cursor: android.database.Cursor? = null
    var db: android.database.sqlite.SQLiteDatabase? = null

    try {
        val dbHelper = DatabaseHelper.getInstance(applicationContext)
        db = dbHelper.writableDatabase

        // 1. 알람 정보 읽기
        cursor = db.query(
            "alarms",
            arrayOf("time", "date", "shift_type"),
            "id = ?",
            arrayOf(alarmId.toString()),
            null, null, null
        )

        if (cursor.moveToFirst()) {
            scheduledTime = cursor.getString(cursor.getColumnIndexOrThrow("time"))
            scheduledDate = cursor.getString(cursor.getColumnIndexOrThrow("date"))
            shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type"))
            Log.d("AlarmOverlay", "✅ 알람 정보 읽기 완료: $scheduledDate $scheduledTime")
        }

        cursor.close()

        // ⭐ CRITICAL FIX: Native 알람 먼저 취소 (유령 알람 방지!)
        cancelNativeAlarm()

        // 2. 알람 삭제
        db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        Log.d("AlarmOverlay", "✅ DB 알람 삭제: ID=$alarmId")

        // 3. 이력 생성 (저장한 정보 사용, 같은 DB 재사용)
        if (scheduledTime.isNotEmpty() && scheduledDate.isNotEmpty()) {
            val now = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())

            val historyValues = android.content.ContentValues().apply {
                put("alarm_id", alarmId)
                put("scheduled_time", scheduledTime)
                put("scheduled_date", scheduledDate)
                put("actual_ring_time", now)
                put("dismiss_type", "swiped")
                put("snooze_count", 0)
                put("shift_type", shiftType)
                put("created_at", now)
            }

            db.insert("alarm_history", null, historyValues)
            Log.d("AlarmOverlay", "✅ 알람 이력 생성: ID=$alarmId, type=swiped")
        }

    } catch (e: Exception) {
        Log.e("AlarmOverlay", "❌ DB 작업 실패", e)
    } finally {
        cursor?.close()
        db?.close()
    }

    // ⭐ HIGH FIX #8: Notification 삭제 (모든 관련 notification 정리)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)          // 알람 ID
    notificationManager.cancel(alarmId + 100000) // Fallback notification
    notificationManager.cancel(7777)             // 제어
    notificationManager.cancel(8888)             // 20분 전
    notificationManager.cancel(8889)             // 스누즈/타임아웃
    Log.d("AlarmOverlay", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8888, 8889)")

    // ⭐ shownNotifications에서 제거 (다음 알람 Notification 표시 위해)
    AlarmGuardReceiver.removeShownNotification(alarmId)

    // ⭐ 갱신 체크
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

    // ⭐ AlarmGuardReceiver 재실행 (다음 알람 Notification 표시)
    val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
    sendBroadcast(guardIntent)

    // ⭐ Flutter UI 갱신 트리거
    val flutterIntent = Intent("com.example.shiftbell.FLUTTER_REFRESH")
    sendBroadcast(flutterIntent)
    Log.d("AlarmOverlay", "📢 Flutter UI 갱신 브로드캐스트 전송")

    // Overlay 제거
    removeOverlay()

    // 서비스 종료
    stopSelf()
}
    
    private fun snoozeAlarm() {
        cancelTimeoutTimer()

        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()

        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        // 5분 후 알람 재등록
        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            db = dbHelper.writableDatabase  // ⭐ HIGH FIX: 처음부터 writableDatabase 사용 (중복 방지)

            cursor = db.query(
                "alarms",
                null,
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            if (cursor.moveToFirst()) {
                val alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"

                // ⭐ 원래 시간 저장 (이력 생성용)
                val originalTime = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                val originalDate = cursor.getString(cursor.getColumnIndexOrThrow("date"))

                // ⭐ HIGH FIX: 한 번에 모든 알람 시간 읽어서 메모리에서 충돌 체크 (DB 재연결 방지)
                val existingAlarmTimes = mutableSetOf<Long>()
                val alarmsCursor = db.query(
                    "alarms",
                    arrayOf("date"),
                    "id != ?",
                    arrayOf(alarmId.toString()),
                    null, null, null
                )

                try {
                    while (alarmsCursor.moveToNext()) {
                        val dateStr = alarmsCursor.getString(alarmsCursor.getColumnIndexOrThrow("date"))
                        try {
                            val alarmDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).parse(dateStr)
                            alarmDate?.let { existingAlarmTimes.add(it.time) }
                        } catch (e: Exception) {
                            // 파싱 실패 무시
                        }
                    }
                } finally {
                    alarmsCursor.close()  // ⭐ HIGH FIX: Cursor 리소스 누수 방지
                }

                // ⭐ 5분 후 시간 계산 + 스마트 시간 조정 (중복 방지, 메모리에서 체크)
                var adjustedMinutes = 5
                var newTimestamp = System.currentTimeMillis() + (adjustedMinutes * 60 * 1000)
                val maxAdjustment = 10  // 최대 10분

                while (existingAlarmTimes.contains(newTimestamp) && adjustedMinutes < maxAdjustment) {
                    adjustedMinutes++
                    newTimestamp = System.currentTimeMillis() + (adjustedMinutes * 60 * 1000)
                    Log.d("AlarmOverlay", "⚠️ 시간 충돌 감지 → ${adjustedMinutes}분 후로 조정")
                }

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
                val dateStr = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date(newTimestamp))
                val timeStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(newTimestamp))

                val values = android.content.ContentValues().apply {
                    put("date", dateStr)
                    put("time", timeStr)
                    put("type", "snoozed")  // ⭐ CRITICAL FIX: 자정 갱신 시 삭제 방지
                }
                db.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))
                Log.d("AlarmOverlay", "✅ DB 업데이트: time=$timeStr, date=$dateStr")

                // ⭐ 이력 생성 (원래 시간 사용!)
                val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
                val historyValues = android.content.ContentValues().apply {
                    put("alarm_id", alarmId)
                    put("scheduled_time", originalTime)  // 원래 시간!
                    put("scheduled_date", originalDate)  // 원래 날짜!
                    put("actual_ring_time", now)
                    put("dismiss_type", "snoozed")
                    put("snooze_count", 0)
                    put("shift_type", shiftType)
                    put("created_at", now)
                }
                db.insert("alarm_history", null, historyValues)
                Log.d("AlarmOverlay", "✅ 알람 이력 생성: ID=$alarmId, type=snoozed, 원래시간=$originalTime")

                // 갱신 체크
                AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

                // ⭐ shownNotifications에서 제거 (스누즈된 알람도 다시 Notification 표시 위해)
                AlarmGuardReceiver.removeShownNotification(alarmId)

                // ⭐ AlarmGuardReceiver 트리거 (다음 알람 Notification 즉시 표시)
                val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
                sendBroadcast(guardIntent)
                Log.d("AlarmOverlay", "✅ AlarmGuardReceiver 트리거")

                // ⭐ 연장 Notification 표시 (NotificationHelper 사용)
                NotificationHelper.showUpdatedNotification(applicationContext, timeStr, shiftType)

                // ⭐ Flutter UI 갱신 트리거
                val flutterIntent = Intent("com.example.shiftbell.FLUTTER_REFRESH")
                sendBroadcast(flutterIntent)
                Log.d("AlarmOverlay", "📢 Flutter UI 갱신 브로드캐스트 전송")

                // ⭐ 앱 포그라운드로 가져와서 Flutter UI 즉시 갱신
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                startActivity(launchIntent)
                Log.d("AlarmOverlay", "✅ 앱 포그라운드 이동 → Flutter UI 갱신")

            } else {
                Log.e("AlarmOverlay", "❌ 알람 정보 없음: ID=$alarmId")
            }

        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ 5분 후 재등록 실패", e)
        } finally {
            cursor?.close()
            db?.close()
        }

        // Overlay 제거
        removeOverlay()

        // 서비스 종료
        stopSelf()
    }

    private fun removeOverlay() {
        try {
            if (overlayView != null) {
                if (isOverlayVisible) {
                    windowManager?.removeView(overlayView)
                    Log.d("AlarmOverlay", "✅ Overlay Window 제거")
                }
                overlayView = null
                isOverlayVisible = false
                Log.d("AlarmOverlay", "✅ Overlay View 정리 완료")
            }
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ Overlay 제거 실패", e)
        }
    }

    // ⭐ CRITICAL FIX: Native 알람 취소 (유령 알람 방지!)
    private fun cancelNativeAlarm() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val intent = Intent(this, CustomAlarmReceiver::class.java).apply {
                data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
            }
            val pendingIntent = android.app.PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d("AlarmOverlay", "✅ Native 알람 취소: ID=$alarmId")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ Native 알람 취소 실패", e)
        }
    }

    // ⭐ 변경: 이력 업데이트 → 이력 생성 (ringing 이력 없으므로)
    private fun createAlarmHistory(alarmId: Int, dismissType: String) {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            db = dbHelper.writableDatabase

            // 알람 정보 조회
            cursor = db.query(
                "alarms",
                arrayOf("time", "date", "shift_type"),
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            if (cursor.moveToFirst()) {
                val scheduledTime = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                val scheduledDate = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type"))

                val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())

                // 새 이력 생성
                val historyValues = android.content.ContentValues().apply {
                    put("alarm_id", alarmId)
                    put("scheduled_time", scheduledTime)
                    put("scheduled_date", scheduledDate)
                    put("actual_ring_time", now)
                    put("dismiss_type", dismissType)
                    put("snooze_count", 0)  // 항상 0
                    put("shift_type", shiftType)
                    put("created_at", now)
                }

                db.insert("alarm_history", null, historyValues)
                Log.d("AlarmOverlay", "✅ 알람 이력 생성: ID=$alarmId, type=$dismissType")
            }

        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ 이력 생성 실패", e)
        } finally {
            cursor?.close()
            db?.close()  // ⭐ CRITICAL FIX: DB 리소스 누수 방지
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
            Log.e("AlarmOverlay", "외부 신호 리시버 해제 실패", e)
        }

        removeOverlay()
    }
}