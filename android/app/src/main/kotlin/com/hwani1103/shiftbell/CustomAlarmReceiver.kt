package com.hwani1103.shiftbell

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CustomAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_SOUND_TYPE = "soundType"
        const val EXTRA_LABEL = "label"
        const val EXTRA_ID = "id"
        const val CHANNEL_ID = "shiftbell_alarm_v3"  // ⭐ 채널 ID 변경 + "알람" 키워드 제거
    }
    
    // CustomAlarmReceiver.kt - onReceive() 수정

override fun onReceive(context: Context, intent: Intent) {
    Log.e("CustomAlarmReceiver", "========== 알람 수신! ==========")

    val soundType = intent.getStringExtra(EXTRA_SOUND_TYPE) ?: "loud"
    val label = intent.getStringExtra(EXTRA_LABEL) ?: "알람"
    val id = intent.getIntExtra(EXTRA_ID, 0)

    Log.e("CustomAlarmReceiver", "ID: $id, Label: $label")

    // ⭐ 안전장치: DB에 이 id의 알람이 더 이상 없으면(이미 취소/수정으로 삭제됨) 재생하지
    // 않고 종료. AlarmManager에 등록된 PendingIntent가 어떤 이유로든 취소되지 않고 남아있는
    // 경우(예: 설정에서 알람 시간 수정 시 옛 알람)에도, 최소한 실제로 울리는 것만큼은 막는
    // 마지막 방어선. (진짜 원인은 diff 갱신 엔진의 cancelNativeAlarm이 담당하지만, 어떤
    // 이유로든 새어나간 PendingIntent가 있어도 여기서 한 번 더 걸러짐)
    if (!alarmExistsInDb(context, id)) {
        Log.e("CustomAlarmReceiver", "⚠️ DB에 없는 알람(id=$id) - 재생 건너뜀 (이미 취소/수정됨)")
        return
    }

    // ⭐ 2026-08-25 - 겹쳐 울리는 알람 처리: 아직 응답(끄기/스누즈/타임아웃)되지 않은
    // 이전 알람이 있으면, 이 새 알람이 화면/소리를 넘겨받기 전에 그 이전 알람을 먼저
    // 깔끔하게 마무리함(이력 기록 + DB 삭제 + notification 정리). 안 그러면 화면은 옛
    // 알람을 계속 보여주는데 버튼은 새 알람 id에 연결되는 불일치, 또는 DB에 영원히 안
    // 지워지는 유령 행이 생길 수 있었음(RingingAlarmTracker.kt 클래스 주석 참고).
    // 실제 소리는 이미 AlarmPlayer(싱글턴, 아래에서 재생)가 최신 알람 것 하나로 항상
    // 자동 전환하므로 이 처리는 "화면/DB/이력을 소리와 일치시키는" 역할.
    val previousRingingId = RingingAlarmTracker.getRingingAlarmId(context)
    if (previousRingingId != null && previousRingingId != id) {
        Log.e("CustomAlarmReceiver", "⏰ 이전 알람($previousRingingId)이 아직 응답 전인데 새 알람($id) 도착 - 이전 알람 자동 마무리")
        AlarmActionHelper.supersede(context, previousRingingId)
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(previousRingingId)
            nm.cancel(previousRingingId + 100000)
            nm.cancel(7777)
            nm.cancel(8889)
        } catch (e: Exception) {
            Log.e("CustomAlarmReceiver", "⚠️ 이전 알람 notification 정리 실패", e)
        }
        try {
            // ⭐ 이전 알람이 잠금화면(AlarmActivity)에 떠 있었을 수도 있으니 확실히 닫음 -
            // AlarmActivity.kt가 이미 등록해둔 FINISH_ALARM_ACTIVITY 리시버를 재사용.
            val finishIntent = Intent("FINISH_ALARM_ACTIVITY").apply {
                putExtra("alarmId", previousRingingId)
                setPackage(context.packageName)
            }
            context.sendBroadcast(finishIntent)
        } catch (e: Exception) {
            Log.e("CustomAlarmReceiver", "⚠️ 이전 알람 화면 종료 신호 실패", e)
        }
    }
    RingingAlarmTracker.setRingingAlarmId(context, id)

    // ⭐ 신규: 알람 울릴 때 즉시 갱신 체크!
    AlarmRefreshUtil.checkAndTriggerRefresh(context)

    // ⭐ 알람 울리면 20분 전 Notification 갱신 (이 알람은 더 이상 "다음 알람"이 아니므로
    // AlarmGuardReceiver가 재계산 - 만약 15~30분 뒤 다른 알람이 있다면 그쪽 8888이 새로 표시됨)
    AlarmGuardReceiver.triggerCheck(context)

    // ⭐ ringing 이력 생성 제거 (사용자에게 무의미한 내부 상태)
    // 실제 이력은 dismiss/snooze/timeout 시 생성됨

    // 알람 재생 (DB에서 설정 읽어서 적용)
    AlarmPlayer.getInstance(context.applicationContext).playAlarmFromDB(id)
    
    // 화면 강제로 깨우기
    wakeUpScreen(context)
    
    // 잠금 상태 확인
    val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
    val isLocked = keyguardManager.isKeyguardLocked
    
    Log.e("CustomAlarmReceiver", "잠금 상태: ${if (isLocked) "잠금" else "해제"}")
    
    Handler(Looper.getMainLooper()).postDelayed({
        if (isLocked) {
            Log.e("CustomAlarmReceiver", "✅ 잠금 상태 - AlarmActivity 표시")
            // ⭐ 잠금화면 AlarmActivity만 표시 (홈 버튼 시 Notification으로 제어)
            showAlarmActivity(context, id, label)
        } else {
            if (canDrawOverlays(context)) {
                Log.e("CustomAlarmReceiver", "✅ 잠금 해제 - Overlay 표시")
                showOverlayWindow(context, id, label)
            } else {
                Log.e("CustomAlarmReceiver", "⚠️ Overlay 권한 없음 - Notification")
                showNotification(context, id, label)
            }
        }
    }, 500)
}
    
    private fun alarmExistsInDb(context: Context, id: Int): Boolean {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null
        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 (DatabaseHelper.kt 상세 주석 참고).
            // 확인 자체가 불가능한 상황이므로 기존 예외 처리와 동일하게 재생을 막지 않음.
            db = dbHelper.getReadableDatabaseWithRetry() ?: return true
            cursor = db.query("alarms", arrayOf("id"), "id = ?", arrayOf(id.toString()), null, null, null)
            cursor.moveToFirst()
        } catch (e: Exception) {
            Log.e("CustomAlarmReceiver", "❌ 알람 존재 확인 실패 - 안전하게 재생 진행", e)
            true  // 확인 자체가 실패하면 (기존 동작 유지 위해) 재생은 막지 않음
        } finally {
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고)
            cursor?.close()
        }
    }

    private fun wakeUpScreen(context: Context) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "ShiftBell:AlarmWakeLock"
            )
            wakeLock.acquire(10000) // 10초
            
            Log.e("CustomAlarmReceiver", "✅ 화면 깨움")
        } catch (e: Exception) {
            Log.e("CustomAlarmReceiver", "❌ 화면 깨우기 실패", e)
        }
    }
    
    private fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(context)
        } else {
            true
        }
    }
    
    private fun showAlarmActivity(context: Context, id: Int, label: String) {
    // ⭐ DB에서 duration 읽기
    val duration = getDurationFromDB(context, id)

    val activityIntent = Intent(context, AlarmActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TASK or
                Intent.FLAG_ACTIVITY_NO_USER_ACTION
        putExtra("alarmId", id)
        putExtra("label", label)
        putExtra("alarmDuration", duration)
    }

    try {
        context.startActivity(activityIntent)
        Log.e("CustomAlarmReceiver", "✅ AlarmActivity 시작 (duration=${duration}분)")
    } catch (e: Exception) {
        Log.e("CustomAlarmReceiver", "❌ AlarmActivity 시작 실패", e)
        showNotification(context, id, label)
    }
}

    // ⭐ DB에서 알람 타입의 duration 읽기
    private fun getDurationFromDB(context: Context, alarmId: Int): Int {
        var alarmCursor: android.database.Cursor? = null
        var typeCursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 (DatabaseHelper.kt 상세 주석 참고).
            db = dbHelper.getReadableDatabaseWithRetry() ?: return 3
            val database = db

            // 알람에서 alarm_type_id 조회
            alarmCursor = database.query(
                "alarms",
                arrayOf("alarm_type_id"),
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            var alarmTypeId = 1  // 기본값
            if (alarmCursor.moveToFirst()) {
                alarmTypeId = alarmCursor.getInt(alarmCursor.getColumnIndexOrThrow("alarm_type_id"))
            }

            // alarm_types에서 duration 조회
            typeCursor = database.query(
                "alarm_types",
                arrayOf("duration"),
                "id = ?",
                arrayOf(alarmTypeId.toString()),
                null, null, null
            )

            var duration = 3  // 기본값 3분
            if (typeCursor.moveToFirst()) {
                duration = typeCursor.getInt(typeCursor.getColumnIndexOrThrow("duration"))
            }

            Log.d("CustomAlarmReceiver", "✅ DB duration: $duration 분")
            return duration
        } catch (e: Exception) {
            Log.e("CustomAlarmReceiver", "❌ duration 조회 실패, 기본값 3분 사용", e)
            return 3
        } finally {
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고)
            alarmCursor?.close()
            typeCursor?.close()
        }
    }
    
    private fun showOverlayWindow(context: Context, id: Int, label: String) {
        Log.e("CustomAlarmReceiver", "✅ Overlay 표시 시작")
        
        val overlayIntent = Intent(context, AlarmOverlayService::class.java).apply {
            putExtra("alarmId", id)
        }
        
        context.startService(overlayIntent)
    }
    
    private fun showNotification(context: Context, id: Int, label: String) {
        Log.e("CustomAlarmReceiver", "⚠️ Notification으로 폴백")
        
        val fullScreenIntent = Intent(context, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("alarmId", id)
        }
        
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            id,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // ⭐ 채널 생성 (무음 - 소리는 AlarmPlayer에서 재생) - "알람" 키워드 제거
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Shiftbell",  // ⭐ "알람" 제거 (삼성 시스템 스누즈 방지)
                NotificationManager.IMPORTANCE_HIGH  // fullScreenIntent를 위해 HIGH 유지
            ).apply {
                description = "근무 시간 알림"
                enableVibration(false)
                setSound(null, null)  // notification 자체는 무음
            }
            notificationManager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Shiftbell")  // ⭐ "알람" 제거
            .setContentText(label)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)  // ⭐ CALL 사용 (삼성 시스템 스누즈 방지, full-screen 지원)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setSilent(true)  // ⭐ 소리/진동 없음 (알람 소리는 AlarmPlayer)
            .setAutoCancel(true)
            .setGroup("shiftbell_notifications")  // ⭐ 그룹 설정 (삼성 시스템 스누즈 방지)
            .setGroupSummary(false)
            .setLocalOnly(true)  // ⭐ 로컬 전용 (삼성 시스템 스누즈 방지)
            .setStyle(NotificationCompat.BigTextStyle().bigText(label))  // ⭐ 스타일 설정 (삼성 시스템 스누즈 방지)
            .build()
        
        notificationManager.notify(id + 100000, notification)  // ⭐ 8888/8889와 충돌 방지
        
        Log.e("CustomAlarmReceiver", "✅ Notification 표시")
    }
}