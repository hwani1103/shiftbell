// android/app/src/main/kotlin/com/example/shiftbell/AlarmActivity.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.BroadcastReceiver
import android.content.ContentValues
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
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs

class AlarmActivity : AppCompatActivity() {
    private var alarmId: Int = 0
    private var alarmDuration: Int = 1  // 기본 1분 (테스트용)
    private var alarmTimeStr: String = ""  // 알람 시간 저장
    private var alarmLabel: String = "알람"  // 알람 라벨 저장
    private lateinit var gestureDetector: GestureDetectorCompat
    private var timeoutHandler: Handler? = null
    private var timeoutRunnable: Runnable? = null

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
        alarmDuration = intent.getIntExtra("alarmDuration", 1)  // 기본 1분 (테스트용)

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
            db = dbHelper.readableDatabase

            cursor = db.query(
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
            cursor?.close()
            db?.close()
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

    // 알람 소리 중지
    AlarmPlayer.getInstance(applicationContext).stopAlarm()

    // ⭐ CRITICAL FIX: Native 알람 먼저 취소 (유령 알람 방지!)
    cancelNativeAlarm()

    // ⭐ DB에서 알람 삭제
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

    // 이력 생성
    createAlarmHistory(alarmId, "timeout")

    // shownNotifications에서 제거
    AlarmGuardReceiver.removeShownNotification(alarmId)

    // ⭐ HIGH FIX #6: Notification 삭제 (모든 관련 notification 정리)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(alarmId)          // 알람 ID
    notificationManager.cancel(alarmId + 100000) // Fallback notification
    notificationManager.cancel(7777)             // 제어
    notificationManager.cancel(8888)             // 20분 전
    notificationManager.cancel(8889)             // 스누즈/타임아웃
    Log.d("AlarmActivity", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8888, 8889)")

    // 갱신 체크
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

    // ⭐ 다음 알람의 8888 Notification 표시 (직접 호출)
    AlarmGuardReceiver.triggerCheck(this)
    Log.d("AlarmActivity", "✅ AlarmGuardReceiver.triggerCheck() → 다음 알람 8888 표시")

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

    // ⭐ Overlay 서비스도 종료
    stopOverlayService()

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
            Log.d("AlarmActivity", "✅ 알람 정보 읽기 완료: $scheduledDate $scheduledTime")
        }

        cursor.close()

        // ⭐ CRITICAL FIX: Native 알람 먼저 취소 (유령 알람 방지!)
        cancelNativeAlarm()

        // 2. 알람 삭제
        val deleted = db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        Log.d("AlarmActivity", if (deleted > 0) {
            "✅ DB 알람 삭제: ID=$alarmId"
        } else {
            "⚠️ DB 알람 없음: ID=$alarmId"
        })

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
            Log.d("AlarmActivity", "✅ 알람 이력 생성: ID=$alarmId, type=swiped")
        }

    } catch (e: Exception) {
        Log.e("AlarmActivity", "❌ DB 작업 실패", e)
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
    Log.d("AlarmActivity", "🗑️ Notification 삭제 (alarmId, alarmId+100000, 7777, 8888, 8889)")

    // ⭐ shownNotifications에서 제거 (다음 알람 Notification 표시 위해)
    AlarmGuardReceiver.removeShownNotification(alarmId)

    // ⭐ 갱신 체크 (Native에서 직접!)
    AlarmRefreshUtil.checkAndTriggerRefresh(applicationContext)

    // ⭐ AlarmGuardReceiver 트리거 (다음 알람 Notification 즉시 표시)
    val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
    sendBroadcast(guardIntent)
    Log.d("AlarmActivity", "✅ AlarmGuardReceiver 트리거")

    // ⭐ Flutter UI 갱신 트리거
    val flutterIntent = Intent("com.example.shiftbell.FLUTTER_REFRESH")
    sendBroadcast(flutterIntent)
    Log.d("AlarmActivity", "📢 Flutter UI 갱신 브로드캐스트 전송")

    // ⭐ finish()만 호출하면 잠금 화면으로 돌아감
    finish()
}
    
    private fun snoozeAlarm() {
        cancelTimeoutTimer()

        AlarmPlayer.getInstance(applicationContext).stopAlarm()

        // ⭐ Overlay 서비스도 종료
        stopOverlayService()

        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

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
                            val alarmDate = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.getDefault()).parse(dateStr)
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
                    Log.d("AlarmActivity", "⚠️ 시간 충돌 감지 → ${adjustedMinutes}분 후로 조정")
                }

                // ⭐ 기존 알람 취소
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val cancelIntent = Intent(this, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                }
                val cancelPendingIntent = PendingIntent.getBroadcast(
                    this,
                    alarmId,
                    cancelIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(cancelPendingIntent)
                cancelPendingIntent.cancel()
                Log.d("AlarmActivity", "✅ 기존 알람 취소: ID=$alarmId")

                // ⭐ 새 알람 등록
                val newIntent = Intent(this, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                    putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
                    putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
                    putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                }

                val newPendingIntent = PendingIntent.getBroadcast(
                    this,
                    alarmId,
                    newIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        newTimestamp,
                        newPendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        newTimestamp,
                        newPendingIntent
                    )
                }
                Log.d("AlarmActivity", "✅ 5분 후 알람 등록: ID=$alarmId, 시각=${java.util.Date(newTimestamp)}")

                // ⭐ DB 업데이트 (time, date 필드)
                val dateStr = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(newTimestamp))
                val timeStr = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(newTimestamp))

                val values = ContentValues().apply {
                    put("date", dateStr)
                    put("time", timeStr)
                    put("type", "snoozed")  // ⭐ CRITICAL FIX: 자정 갱신 시 삭제 방지
                }
                db.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))
                Log.d("AlarmActivity", "✅ DB 업데이트: time=$timeStr, date=$dateStr")

                // ⭐ 이력 생성 (원래 시간 사용!)
                val now = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
                val historyValues = ContentValues().apply {
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
                Log.d("AlarmActivity", "✅ 알람 이력 생성: ID=$alarmId, type=snoozed, 원래시간=$originalTime")

                // ⭐ 갱신 체크
                AlarmRefreshUtil.checkAndTriggerRefresh(this)

                // ⭐ shownNotifications에서 제거 (스누즈된 알람도 다시 Notification 표시 위해)
                AlarmGuardReceiver.removeShownNotification(alarmId)

                // ⭐ AlarmGuardReceiver 트리거 (다음 알람 Notification 즉시 표시)
                val guardIntent = Intent(this, AlarmGuardReceiver::class.java)
                sendBroadcast(guardIntent)
                Log.d("AlarmActivity", "✅ AlarmGuardReceiver 트리거")

                // ⭐ 연장 Notification 표시 (NotificationHelper 사용)
                NotificationHelper.showUpdatedNotification(applicationContext, timeStr, shiftType)

                // ⭐ Flutter UI 갱신 트리거
                val flutterIntent = Intent("com.example.shiftbell.FLUTTER_REFRESH")
                sendBroadcast(flutterIntent)
                Log.d("AlarmActivity", "📢 Flutter UI 갱신 브로드캐스트 전송")

            } else {
                Log.e("AlarmActivity", "❌ 알람 정보 없음: ID=$alarmId")
            }

        } catch (e: Exception) {
            Log.e("AlarmActivity", "❌ 5분 후 재등록 실패", e)
        } finally {
            cursor?.close()
            db?.close()
        }

        // ⭐ 유령 Notification 방지
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(7777)              // 알람 울림중
        notificationManager.cancel(8888)              // 20분 전

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

        // "알람 끄기" 버튼
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

        // "5분 후" 버튼
        val snoozeIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = "SNOOZE_FROM_NOTIFICATION"
            putExtra("alarmId", alarmId)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId + 20000,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Notification 생성
        val notification = NotificationCompat.Builder(this, "alarm_control")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("알람 울림 중")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)  // ⭐ 스와이프로 지울 수 없게
            .setAutoCancel(false)
            .setContentIntent(activityPendingIntent)
            .addAction(android.R.drawable.ic_delete, "알람 끄기", dismissPendingIntent)
            .addAction(android.R.drawable.ic_media_play, "5분 후", snoozePendingIntent)
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

        // ⭐ 종료 신호 리시버 해제
        try {
            unregisterReceiver(finishReceiver)
        } catch (e: Exception) {
            Log.e("AlarmActivity", "리시버 해제 실패", e)
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
                val historyValues = ContentValues().apply {
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
                Log.d("AlarmActivity", "✅ 알람 이력 생성: ID=$alarmId, type=$dismissType")
            }
        } catch (e: Exception) {
            Log.e("AlarmActivity", "❌ 이력 생성 실패", e)
        } finally {
            cursor?.close()
            db?.close()  // ⭐ CRITICAL FIX: DB 리소스 누수 방지
        }
    }

    private fun cancelTimeoutTimer() {
        timeoutRunnable?.let {
            timeoutHandler?.removeCallbacks(it)
        }
        Log.d("AlarmActivity", "⏱️ 타임아웃 타이머 취소")
    }

    // ⭐ CRITICAL FIX: Native 알람 취소 (유령 알람 방지!)
    private fun cancelNativeAlarm() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, CustomAlarmReceiver::class.java).apply {
                data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d("AlarmActivity", "✅ Native 알람 취소: ID=$alarmId")
        } catch (e: Exception) {
            Log.e("AlarmActivity", "❌ Native 알람 취소 실패", e)
        }
    }
}