package com.hwani1103.shiftbell

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
import android.util.Log

class AlarmOverlayService : Service() {

    companion object {
        const val ACTION_DISMISS_OVERLAY = "com.hwani1103.shiftbell.DISMISS_OVERLAY"
        const val ACTION_SNOOZE_OVERLAY = "com.hwani1103.shiftbell.SNOOZE_OVERLAY"
        const val EXTRA_ALARM_ID = "alarmId"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: android.view.View? = null
    private var alarmId: Int = 0
    private var alarmTimeStr: String = ""  // 알람 시간 저장
    private var alarmLabel: String = "알람"  // 알람 라벨 저장
    private var timeoutHandler: Handler? = null
    private var timeoutRunnable: Runnable? = null
    private var alarmDuration: Int = 3  // 기본 3분
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
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 - DatabaseHelper.kt 상세 주석 참고.
            db = dbHelper.getReadableDatabaseWithRetry() ?: return
            val database = db

            cursor = database.query(
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
                typeCursor = database.query(
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
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고)
            typeCursor?.close()
            cursor?.close()
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

        // ⭐ Native 알람 취소 + DB 삭제 + 이력 기록을 하나의 트랜잭션으로 (AlarmActionHelper)
        AlarmActionHelper.timeout(applicationContext, alarmId)

        // ⭐ 모든 관련 notification 정리 (8888은 AlarmGuardReceiver가 전담)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(alarmId)          // 알람 ID
        notificationManager.cancel(alarmId + 100000) // Fallback notification
        notificationManager.cancel(7777)             // 제어
        notificationManager.cancel(8889)             // 스누즈/타임아웃
        Log.d("AlarmOverlay", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8889)")

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

    // ⭐ Native 알람 취소 + DB 삭제 + 이력 기록을 하나의 트랜잭션으로 (AlarmActionHelper)
    AlarmActionHelper.dismiss(applicationContext, alarmId, "swiped")

    // ⭐ 모든 관련 notification 정리 (8888은 AlarmGuardReceiver가 전담)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)          // 알람 ID
    notificationManager.cancel(alarmId + 100000) // Fallback notification
    notificationManager.cancel(7777)             // 제어
    notificationManager.cancel(8889)             // 스누즈/타임아웃
    Log.d("AlarmOverlay", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8889)")

    // Overlay 제거
    removeOverlay()

    // 서비스 종료
    stopSelf()
}
    
    private fun snoozeAlarm() {
        cancelTimeoutTimer()

        // 알람 소리 중지
        AlarmPlayer.getInstance(applicationContext).stopAlarm()

        // ⭐ 네이티브 알람 재등록 + DB 갱신 + 이력/생성로그 기록을 하나의 트랜잭션으로 (AlarmActionHelper)
        // 끄기(dismissAlarm)와 동일하게, 앱을 강제로 앞으로 가져오지 않음 - 사용자가 보고 있던
        // 화면(다른 앱 등)을 그대로 유지한 채 알람만 조용히 사라져야 함. Flutter UI는
        // AlarmActionHelper.snooze 내부의 finishUp()이 브로드캐스트로 갱신 신호를 보내므로,
        // 앱이 실행 중이면 포그라운드로 끌어오지 않아도 다음에 열었을 때 최신 상태로 보임.
        val result = AlarmActionHelper.snooze(applicationContext, alarmId)
        if (result != null) {
            NotificationHelper.showUpdatedNotification(applicationContext, result.newTimeStr, result.shiftType)
        } else {
            Log.e("AlarmOverlay", "❌ 알람 정보 없음: ID=$alarmId")
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