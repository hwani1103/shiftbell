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
        const val EXTRA_ALARM_DURATION = "alarmDuration"
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
    // ⭐ 2026-09-14 (출시전 감사 #3) - 이 오버레이가 보여주는 울림 회차(AlarmActionHelper.claimRingEnd)
    private var ringRound: Long = RingingAlarmTracker.NO_ROUND

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
    
    // ⭐ 2026-08-25 - registerReceiver()를 onStartCommand()마다 다시 부르면(겹쳐 울리는
    // 알람으로 같은 Service 인스턴스가 재사용될 때) 같은 리시버가 중복 등록돼서 신호 한
    // 번에 onReceive가 여러 번 불릴 수 있었음 - Service 생애주기 동안 한 번만 등록.
    private var isReceiverRegistered = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val newAlarmId = intent?.getIntExtra("alarmId", 0) ?: 0

        // Overlay 권한 체크
        if (!canDrawOverlays()) {
            Log.e("AlarmOverlayService", "Overlay 권한 없음!")
            stopSelf()
            return START_NOT_STICKY
        }

        // ⭐ 외부 종료 신호를 받기 위한 BroadcastReceiver 등록 (한 번만)
        if (!isReceiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(ACTION_DISMISS_OVERLAY)
                addAction(ACTION_SNOOZE_OVERLAY)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(overlayActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(overlayActionReceiver, filter)
            }
            isReceiverRegistered = true
            Log.d("AlarmOverlay", "📡 외부 신호 리시버 등록")
        }

        // ⭐ 2026-09-14 (교차 검토 X-12) - 회차 없는 옛 Intent는 옛 버전이 남긴 같은 ID의 울림에만 매핑
        val newRound = RingingAlarmTracker.normalizeRound(
            applicationContext, newAlarmId,
            intent?.getLongExtra(AlarmActionReceiver.EXTRA_RING_ROUND, RingingAlarmTracker.NO_ROUND)
                ?: RingingAlarmTracker.NO_ROUND
        )
        // ⭐ 2026-09-14 (#3) - 표시 요청이 도착하기 전에 그 회차가 이미 끝났으면(앱에서 삭제·인계 등) 안 띄움
        if (!RingingAlarmTracker.isCurrent(applicationContext, newAlarmId, newRound)) {
            Log.w("AlarmOverlay", "⚠️ 지난 회차 표시 요청 무시: id=$newAlarmId 회차=$newRound")
            if (!isOverlayVisible) stopSelf()
            return START_NOT_STICKY
        }

        // ⭐ 2026-08-25 - 겹쳐 울리는 알람: 이미 다른 알람의 Overlay가 떠 있는 상태에서
        // 새 알람이 도착한 경우. CustomAlarmReceiver.onReceive()가 이전 알람의 DB/이력은
        // 이미 정리했지만(RingingAlarmTracker 참고), 이 Service는 같은 인스턴스가
        // 재사용되면서 이전 알람의 View를 그대로 두고 alarmId 필드만 새 값으로
        // 덮어썼었음 - prepareOverlay()가 "overlayView가 이미 있으면 재사용"하기
        // 때문에 화면엔 옛 시간/근무명이 계속 보이는데 버튼은 새 알람 것에 연결되는
        // 표시 불일치가 생겼음. 뷰를 통째로 제거해서 다시 그리게 함.
        if (isOverlayVisible && alarmId != 0 && alarmId != newAlarmId) {
            Log.d("AlarmOverlay", "⏰ 다른 알람($alarmId) 표시 중에 새 알람($newAlarmId) 도착 - Overlay 새로 그림")
            removeOverlay()
        }

        alarmId = newAlarmId
        ringRound = newRound
        // ⭐ 2026-09-15 (출시 적합성 재검토 AUD-03) - 지속시간은 수신 때 확정한 값(복원 전 설정 스냅샷 우선, 종료 예약과 같은 값).
        // 예전엔 loadAlarmInfo()가 현재 DB의 alarm_types.duration을 다시 읽어서, 스누즈 대기 중 복원으로 타입 설정이 바뀌면
        // 오버레이 타이머가 네이티브 종료 예약보다 먼저(예: 10분 → 1분, 백업에 타입이 없으면 기본 3분) 이 회차를 끝낼 수 있었음.
        alarmDuration = intent?.getIntExtra(EXTRA_ALARM_DURATION, -1)?.takeIf { it > 0 }
            ?: CustomAlarmReceiver.ringDurationMinutes(applicationContext, newAlarmId)

        // DB에서 알람 표시 정보(시각·근무명) 조회
        loadAlarmInfo()

        // ⭐ Overlay 즉시 표시 (잠금 해제 상태에서만 사용)
        showOverlay()

        startTimeoutTimer()

        return START_NOT_STICKY
    }

    // 외부에서 호출된 DISMISS (소리만 중지, DB 작업은 이미 외부에서 처리됨)
    private fun dismissAlarmFromExternal() {
        cancelTimeoutTimer()
        // ⭐ 2026-09-14 (출시전 감사 #3/#14) - 예전엔 여기서 무조건 소리를 멈췄음. 이 신호는
        // CustomAlarmReceiver의 인계(이전 알람 정리)·종료 예약·앱 삭제(AlarmActionHelper.closeRingUi)가
        // 보내는데, 브로드캐스트라 새 알람 재생이 시작된 뒤에 도착할 수 있어서 새 알람 소리까지 멈출 수
        // 있었음. 보낸 쪽이 이미 회차를 폐기했으면 창만 닫고, 이 알람이 아직 활성 울림일 때만
        // (외부에서 dismissOverlay만 보낸 경우) 울림을 끝냄.
        if (AlarmActionHelper.claimCurrentRingOf(applicationContext, alarmId)) {
            AlarmPlayer.getInstance(applicationContext).stopAlarm()
            // ⭐ 2026-09-14 (#4) - 울리는 내내 떠 있던 제어 알림도 정리
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NotificationHelper.RING_CONTROL_ID)
        }
        removeOverlay()
        stopSelf()
        Log.d("AlarmOverlay", "✅ 외부 신호로 Overlay 종료")
    }

    // 외부에서 호출된 SNOOZE (소리만 중지, DB 작업은 이미 외부에서 처리됨)
    private fun snoozeAlarmFromExternal() {
        cancelTimeoutTimer()
        // ⭐ 2026-09-14 (#3/#14) - dismissAlarmFromExternal()과 같은 이유로 활성 울림일 때만 멈춤
        if (AlarmActionHelper.claimCurrentRingOf(applicationContext, alarmId)) {
            AlarmPlayer.getInstance(applicationContext).stopAlarm()
            // ⭐ 2026-09-14 (#4) - 울리는 내내 떠 있던 제어 알림도 정리
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NotificationHelper.RING_CONTROL_ID)
        }
        removeOverlay()
        stopSelf()
        Log.d("AlarmOverlay", "✅ 외부 신호로 Overlay 종료 (스누즈)")
    }

    private fun loadAlarmInfo() {
        var cursor: android.database.Cursor? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 - DatabaseHelper.kt 상세 주석 참고.
            val database = dbHelper.getReadableDatabaseWithRetry() ?: return

            cursor = database.query(
                "alarms",
                arrayOf("time", "shift_type"),
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            if (cursor.moveToFirst()) {
                alarmTimeStr = cursor.getString(cursor.getColumnIndexOrThrow("time")) ?: ""
                alarmLabel = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
            }
            // 지속시간은 onStartCommand에서 확정(AUD-03) - 여기서 DB로 다시 덮어쓰지 않음

            Log.d("AlarmOverlay", "✅ 알람 정보 로드: time=$alarmTimeStr, label=$alarmLabel, duration=${alarmDuration}분")
        } catch (e: Exception) {
            Log.e("AlarmOverlay", "❌ 알람 정보 로드 실패", e)
        } finally {
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고)
            cursor?.close()
        }
    }

    private fun startTimeoutTimer() {
        // ⭐ 2026-08-25 - 겹쳐 울리는 알람 대응으로 onStartCommand()가 같은 Service
        // 인스턴스에서 다시 호출될 수 있게 됨. 여기서 기존 타이머를 먼저 취소하지 않으면
        // Handler/Runnable 필드만 새 걸로 덮어써질 뿐 이전에 postDelayed()로 이미
        // 큐잉된 옛 타임아웃이 그대로 남아있어서(같은 메인 Looper 큐에 독립적으로
        // 존재), 엉뚱한 시점에 (그 사이 바뀐) alarmId를 기준으로 timeoutAlarm()이
        // 한 번 더 실행되는 이중 타임아웃이 생길 수 있었음.
        cancelTimeoutTimer()

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

        // ⭐ 2026-09-14 (#3) - 종료 예약이 먼저 끝냈거나 지난 회차면 창만 닫음
        if (!AlarmActionHelper.claimRingEnd(applicationContext, alarmId, ringRound)) {
            removeOverlay()
            stopSelf()
            return
        }

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
            // ⭐ 2026-09-13(사용자 요청 - "카톡 메시지 온 것 같은 카드 형태로,
            // 상태표시줄이랑은 안 닿는 위치로") - FLAG_LAYOUT_IN_SCREEN이라
            // y=0은 상태표시줄 영역까지 포함한 화면 맨 위를 가리켰음(카드
            // 위쪽이 상태표시줄에 딱 붙어서 시작). 상태표시줄 높이만큼 내리고
            // 추가로 12dp 여백을 더 둬서 카드와 상태표시줄 사이를 살짝 띄움 -
            // 색상/버튼 등 카드 내용물 자체는 전혀 안 바꿈, 화면상 y좌표만 조정.
            val statusBarHeightPx = run {
                val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
                if (resId > 0) resources.getDimensionPixelSize(resId) else 0
            }
            val extraGapPx = (12 * resources.displayMetrics.density).toInt()
            params.y = statusBarHeightPx + extraGapPx

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

    // ⭐ 2026-09-14 (#3) - 지난 회차 창의 버튼이면 다른 울림을 건드리지 않고 창만 닫음
    if (!AlarmActionHelper.claimRingEnd(applicationContext, alarmId, ringRound)) {
        removeOverlay()
        stopSelf()
        return
    }

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

        // ⭐ 2026-09-14 (#3) - 지난 회차 창의 버튼이면 다른 울림을 건드리지 않고 창만 닫음
        if (!AlarmActionHelper.claimRingEnd(applicationContext, alarmId, ringRound)) {
            removeOverlay()
            stopSelf()
            return
        }

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

        // ⭐ 2026-09-14 (출시전 감사 #4) - 제어 알림(7777)은 울리는 내내 떠 있으므로 스누즈에서도 정리
        // (예전엔 오버레이 스누즈가 7777을 지우지 않았음 - 그땐 오버레이 상태에서 7777이 없었기 때문)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NotificationHelper.RING_CONTROL_ID)

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