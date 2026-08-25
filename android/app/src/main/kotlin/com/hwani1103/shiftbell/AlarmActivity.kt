// android/app/src/main/kotlin/com/example/shiftbell/AlarmActivity.kt

package com.hwani1103.shiftbell

import android.app.PendingIntent
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import kotlin.math.abs

class AlarmActivity : AppCompatActivity() {
    private var alarmId: Int = 0
    private var alarmDuration: Int = 3  // 기본 3분
    private var alarmTimeStr: String = ""  // 알람 시간 저장
    private var alarmLabel: String = "알람"  // 알람 라벨 저장
    private lateinit var gestureDetector: GestureDetectorCompat
    private var timeoutHandler: Handler? = null
    private var timeoutRunnable: Runnable? = null
    private var swipeHintAnimator: android.animation.Animator? = null

    // ⭐ 의도적 종료 플래그 (timeout/dismiss/snooze 중에는 7777 생성 방지)
    private var isIntentionalExit: Boolean = false

    // ⭐ Notification에서 Activity 종료 신호 수신
    private val finishReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val targetAlarmId = intent.getIntExtra("alarmId", -1)
            if (targetAlarmId == alarmId) {
                Log.d("AlarmActivity", "📡 종료 신호 수신 → Activity 종료")
                finish()
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        alarmId = intent.getIntExtra("alarmId", 0)
        alarmDuration = intent.getIntExtra("alarmDuration", 3)  // 기본 3분

        setupWindowFlags()

        // DB에서 알람 정보 로드
        loadAlarmInfo()

        setContentView(R.layout.activity_alarm)
        setupUI()

        gestureDetector = GestureDetectorCompat(this, SwipeGestureListener())

        findViewById<ConstraintLayout>(R.id.rootLayout).setOnTouchListener { _, event ->
            gestureDetector.onTouchEvent(event)
            true
        }

        // ⭐ 종료 신호 리시버 등록
        val filter = IntentFilter("FINISH_ALARM_ACTIVITY")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(finishReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(finishReceiver, filter)
        }

        startTimeoutTimer()
    }

    private fun loadAlarmInfo() {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(applicationContext)
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 - DatabaseHelper.kt 상세 주석 참고.
            db = dbHelper.getReadableDatabaseWithRetry() ?: return
            val database = db

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

            Log.d("AlarmActivity", "✅ 알람 정보 로드: time=$alarmTimeStr, label=$alarmLabel")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "❌ 알람 정보 로드 실패", e)
        } finally {
            // ⭐ db.close() 제거: DatabaseHelper는 앱 전체 공유 싱글턴이라 매번 닫으면
            // 다른 컴포넌트와 동시 접근 시 "이미 닫힌 객체"/"no such table" 레이스가 생김
            // (AlarmActionHelper.kt의 상세 주석 참고)
            cursor?.close()
        }
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

    // ⭐ 의도적 종료 플래그 설정 (onUserLeaveHint에서 7777 생성 방지)
    isIntentionalExit = true

    // 알람 소리 중지
    AlarmPlayer.getInstance(applicationContext).stopAlarm()

    // ⭐ Native 알람 취소 + DB 삭제 + 이력 기록을 하나의 트랜잭션으로 (AlarmActionHelper)
    AlarmActionHelper.timeout(applicationContext, alarmId)

    // ⭐ 모든 관련 notification 정리
    // ⭐ CRITICAL FIX: 8888은 여기서 지우면 안 됨! 이 알람 본인의 8888은
    // CustomAlarmReceiver가 울릴 때 이미 지웠고, 지금 8888이 떠있다면 그건
    // "다음" 알람(20분 이내로 붙어있는 다른 알람) 것일 수 있음 - 여기서 지우면
    // 그 알람의 정당한 리마인더가 사라지고, AlarmGuardReceiver는 이미 한 번
    // 보여준 걸로 기억하고 있어서(shownNotifications) 다시 안 띄워줌.
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)          // 알람 ID
    notificationManager.cancel(alarmId + 100000) // Fallback notification
    notificationManager.cancel(7777)             // 제어
    notificationManager.cancel(8889)             // 스누즈/타임아웃
    Log.d("AlarmActivity", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8889)")

    // 홈 화면으로 이동
    goToHomeScreen()

    // Activity 종료
    finish()
}

    private fun setupWindowFlags() {
        // ⭐ 잠금 화면 위에 표시 (잠금을 해제하지 않음)
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

        // ⭐ 상태바 텍스트를 검정색으로 변경 (Light status bar)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            window.decorView.systemUiVisibility =
                android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
    }
    
    private fun setupUI() {
        val timeText = findViewById<TextView>(R.id.timeText)

        // ⭐ 알람 설정 시간 표시 (현재 시간 아님!)
        timeText.text = alarmTimeStr

        // 근무 타입 설정
        val shiftTypeText = findViewById<TextView>(R.id.shiftTypeText)
        shiftTypeText.text = alarmLabel

        findViewById<Button>(R.id.dismissButton).setOnClickListener {
            dismissAlarm()
        }

        findViewById<Button>(R.id.snoozeButton).setOnClickListener {
            snoozeAlarm()
        }

        startSwipeHintAnimation()
    }

    // ⭐ "위로 스와이프해서 끄기" 안내가 위로 살짝 올라갔다가 아래로 뚝
    // 떨어지길 반복하는 힌트 애니메이션. Keyframe으로 구간을 나눔:
    // 0~55% 구간(감속 보간)에서 위로 14dp 올라갔다가, 55~62%의 짧은 구간에서
    // 원위치로 뚝 떨어지고, 62~100%는 그 자리에서 잠깐 멈췄다가 반복.
    private fun startSwipeHintAnimation() {
        val hintView = findViewById<android.view.View>(R.id.swipeHintContainer) ?: return
        val riseDistance = -14f * resources.displayMetrics.density

        val kf0 = android.animation.Keyframe.ofFloat(0f, 0f)
        val kf1 = android.animation.Keyframe.ofFloat(0.55f, riseDistance).apply {
            interpolator = android.view.animation.DecelerateInterpolator()
        }
        val kf2 = android.animation.Keyframe.ofFloat(0.62f, 0f)
        val kf3 = android.animation.Keyframe.ofFloat(1f, 0f)
        val pvh = android.animation.PropertyValuesHolder.ofKeyframe("translationY", kf0, kf1, kf2, kf3)

        swipeHintAnimator = android.animation.ObjectAnimator.ofPropertyValuesHolder(hintView, pvh).apply {
            duration = 1400L
            repeatCount = android.animation.ObjectAnimator.INFINITE
            start()
        }
    }
    
    private inner class SwipeGestureListener : GestureDetector.SimpleOnGestureListener() {
        // ⭐ 2026-08-25 - "살짝 스치기만 해도 꺼진다"는 피드백으로 상향(기존
        // 100/100은 사실상 아무 움직임에나 반응할 만큼 낮았음). 그렇다고 화면을
        // 거의 다 가로지를 만큼 길게 만들진 않고, "확실히 의도한 스와이프"만
        // 인식하는 정도로 3~4배 올림.
        private val SWIPE_THRESHOLD = 300
        private val SWIPE_VELOCITY_THRESHOLD = 400
        
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

    // ⭐ 의도적 종료 플래그 설정 (onUserLeaveHint에서 7777 생성 방지)
    isIntentionalExit = true

    AlarmPlayer.getInstance(applicationContext).stopAlarm()

    // ⭐ Overlay 서비스도 종료
    stopOverlayService()

    // ⭐ Native 알람 취소 + DB 삭제 + 이력 기록을 하나의 트랜잭션으로 (AlarmActionHelper)
    AlarmActionHelper.dismiss(applicationContext, alarmId, "swiped")

    // ⭐ 모든 관련 notification 정리 (8888은 AlarmGuardReceiver가 전담 - AlarmActionHelper.dismiss가
    // 이미 내부적으로 guard를 재트리거해서 8888을 최신 상태로 다시 계산해줌)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)          // 알람 ID
    notificationManager.cancel(alarmId + 100000) // Fallback notification
    notificationManager.cancel(7777)             // 제어
    notificationManager.cancel(8889)             // 스누즈/타임아웃
    Log.d("AlarmActivity", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8889)")

    // ⭐ finish()만 호출하면 잠금 화면으로 돌아감
    finish()
}
    
    private fun snoozeAlarm() {
        cancelTimeoutTimer()

        // ⭐ 의도적 종료 플래그 설정 (onUserLeaveHint에서 7777 생성 방지)
        isIntentionalExit = true

        AlarmPlayer.getInstance(applicationContext).stopAlarm()

        // ⭐ Overlay 서비스도 종료
        stopOverlayService()

        // ⭐ 네이티브 알람 재등록 + DB 갱신 + 이력/생성로그 기록을 하나의 트랜잭션으로 (AlarmActionHelper)
        val result = AlarmActionHelper.snooze(applicationContext, alarmId)
        if (result != null) {
            // ⭐ 연장 Notification 표시
            NotificationHelper.showUpdatedNotification(applicationContext, result.newTimeStr, result.shiftType)
        } else {
            Log.e("AlarmActivity", "❌ 알람 정보 없음: ID=$alarmId")
        }

        // ⭐ 7777만 삭제 (8888은 삭제하면 안 됨! triggerCheck()가 새로 표시한 것)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(7777)              // 알람 울림중

        // ⭐ finish()만 호출하면 잠금 화면으로 돌아감
        finish()
    }

    private fun goToHomeScreen() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
    }

    private fun stopOverlayService() {
        try {
            val serviceIntent = Intent(this, AlarmOverlayService::class.java).apply {
                action = AlarmOverlayService.ACTION_DISMISS_OVERLAY
                putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
            }
            stopService(serviceIntent)
            Log.d("AlarmActivity", "✅ Overlay 서비스 종료 요청")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "❌ Overlay 서비스 종료 실패", e)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // ⭐ 의도적 종료 중에는 7777 생성 안 함 (goToHomeScreen()이 이 함수를 트리거함)
        if (isIntentionalExit) {
            Log.d("AlarmActivity", "👋 의도적 종료 중 → Notification 생성 안 함")
            return
        }
        // ⭐ 홈 버튼 눌렀을 때 → 알람 제어 Notification 표시
        Log.d("AlarmActivity", "👋 홈 버튼 감지 → Notification 표시")
        showAlarmControlNotification()
    }

    private fun showAlarmControlNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 채널 생성
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "alarm_control",
                "알람 제어",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "울리는 알람을 제어할 수 있습니다"
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Notification 탭 시 AlarmActivity 재시작
        val activityIntent = Intent(this, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("alarmId", alarmId)
            putExtra("alarmDuration", alarmDuration)
        }
        val activityPendingIntent = PendingIntent.getActivity(
            this,
            alarmId,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "알람 끄기" 버튼 (스와이프로 지울 때도 동일한 액션을 씀 - setDeleteIntent)
        val dismissIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = "DISMISS_FROM_NOTIFICATION"
            putExtra("alarmId", alarmId)
        }
        val dismissPendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId + 10000,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Notification 생성
        // ⭐ "5분 후" 버튼 제거함 (알람 제어 경로를 하나로 단순화).
        // ⭐ setOngoing(false) + setDeleteIntent: 사용자가 이 알림을 스와이프로 지워도
        //   "알람 끄기" 버튼을 누른 것과 동일하게 처리됨 (의도: 실수로 잠금해제해서
        //   AlarmActivity를 못 보고 이 알림만 남았을 때, 버튼을 누르든 알림을 치우든
        //   똑같이 "알람 확인"으로 취급).
        val notification = NotificationCompat.Builder(this, "alarm_control")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("알람 울림 중")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(false)
            .setAutoCancel(true)
            .setContentIntent(activityPendingIntent)
            .setDeleteIntent(dismissPendingIntent)
            .addAction(android.R.drawable.ic_delete, "알람 끄기", dismissPendingIntent)
            .build()

        notificationManager.notify(7777, notification)
        Log.d("AlarmActivity", "✅ 알람 제어 Notification 표시 (ID=7777)")
    }

    override fun onBackPressed() {
        // ⭐ 뒤로가기 버튼 무시 (알람을 끄기 전까지 화면 유지)
        // 아무 동작도 하지 않음
    }

    override fun onDestroy() {
        super.onDestroy()
        cancelTimeoutTimer()
        swipeHintAnimator?.cancel()
        swipeHintAnimator = null

        // ⭐ 주의: onDestroy()에서 Notification 삭제하면 안 됨!
        // - noHistory="true" 때문에 홈 버튼 누르면 Activity가 바로 destroy됨
        // - 이때 7777을 삭제하면 홈버튼 후 알람 제어 불가능해짐
        // - dismiss/snooze/timeout에서 이미 7777 삭제하고 finish() 호출하므로 여기서 중복 삭제 불필요
        // - 8888, 8889도 triggerCheck()가 새로 표시한 것이므로 삭제하면 안 됨
        Log.d("AlarmActivity", "🗑️ onDestroy 호출됨 (Notification 삭제 안 함)")

        // ⭐ 종료 신호 리시버 해제
        try {
            unregisterReceiver(finishReceiver)
        } catch (e: Exception) {
            Log.e("AlarmActivity", "리시버 해제 실패", e)
        }
    }

    private fun cancelTimeoutTimer() {
        timeoutRunnable?.let {
            timeoutHandler?.removeCallbacks(it)
        }
        Log.d("AlarmActivity", "⏱️ 타임아웃 타이머 취소")
    }
}