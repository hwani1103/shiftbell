package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

/**
 * ⭐ 알람 끄기/스누즈/타임아웃의 유일한 DB 처리 로직
 *
 * 예전엔 AlarmActivity(잠금화면), AlarmOverlayService(오버레이), AlarmActionReceiver
 * (Notification 버튼)가 각자 거의 똑같은 DB 코드(알람 조회 → 삭제/갱신 → 이력 기록)를
 * 따로 복붙해서 구현하고 있었음. 그래서 한쪽만 고치고 다른 쪽은 놓치는 일이 반복됐음
 * (예: 시간 충돌 체크 로직이 파일마다 미묘하게 달랐음).
 *
 * 이제 DB에 실제로 손을 대는 부분(알람 취소/삭제/갱신 + 이력 기록 + 생성 로그 기록)은
 * 여기 한 곳에만 있고, 호출부(Activity/Overlay/Receiver)는 자기 UI만 책임짐
 * (화면 닫기, Overlay 제거, 어떤 Notification ID를 지울지 등).
 */
object AlarmActionHelper {
    private const val TAG = "AlarmActionHelper"
    private const val DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"

    data class SnoozeResult(val newTimeStr: String, val shiftType: String)

    /**
     * 알람을 완전히 종료 (끄기/타임아웃 공용).
     * dismissType: "swiped"(울리는 중 확인) | "cancelled_before_ring"(울리기 전 취소) | "timeout"
     */
    fun dismiss(context: Context, alarmId: Int, dismissType: String) {
        val dbHelper = DatabaseHelper.getInstance(context)
        // ⭐ DB 파일이 없으면(=아직 스케줄 자체가 없음) Native가 만들면 안 됨 - DatabaseHelper.kt
        // 상세 주석 참고. 이 시점엔 지울 알람도 없는 게 정상이라 그냥 취소만 하고 넘어감.
        val db = dbHelper.getWritableDatabaseWithRetry()
        if (db == null) {
            Log.w(TAG, "⚠️ dismiss: DB 파일 없음 - Native 알람 취소만 수행")
            AlarmWakeScheduler.cancelIfGone(context, null, alarmId)
            finishUp(context, alarmId)
            return
        }

        try {
            db.beginTransaction()
            try {
                db.query(
                    "alarms", arrayOf("time", "date", "shift_type", "day_offset"),
                    "id = ?", arrayOf(alarmId.toString()), null, null, null
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val time = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                        val date = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                        val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: ""
                        val dayOffsetIdx = cursor.getColumnIndex("day_offset")
                        val dayOffset = if (dayOffsetIdx >= 0) cursor.getInt(dayOffsetIdx) else 0
                        if (time != null && date != null) {
                            insertHistory(db, alarmId, date, time, shiftType, dayOffset, dismissType)
                        }
                    } else {
                        Log.d(TAG, "⚠️ dismiss: DB에 알람 없음 (이미 삭제됨) id=$alarmId")
                    }
                }
                db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ dismiss 실패: alarmId=$alarmId", e)
        }
        // ⭐ 2026-09-14 (출시전 감사 #16) - OS 취소는 DB 커밋 뒤, 행을 다시 확인하고 반영(AlarmWakeScheduler) -
        // 트랜잭션이 실패해 행이 남았고 미래 시각이면 취소 대신 그 시각으로 다시 걸림
        AlarmWakeScheduler.cancelIfGone(context, db, alarmId)
        // ⭐ CRITICAL FIX: db.close() 제거. DatabaseHelper는 앱 전체에서 공유하는
        // 싱글턴인데, getReadableDatabase()/getWritableDatabase()가 돌려주는 건
        // "새로 연 연결"이 아니라 SQLiteOpenHelper가 내부적으로 캐싱해서 계속
        // 재사용하는 공유 연결임. 이걸 매번 쓰고 나서 close()하면, 다른 스레드/
        // 컴포넌트(AlarmGuardReceiver, MainActivity 등)가 동시에 그 연결을 쓰고
        // 있거나 막 쓰려던 참이면 "이미 닫힌 객체" 예외나, 심하면 재오픈 도중
        // 테이블이 일시적으로 안 보이는(no such table) 레이스가 생김 - 실제로
        // logcat에서 이 정확한 예외를 확인함. SQLiteOpenHelper는 원래 앱 생명주기
        // 동안 계속 열어두고 쓰도록 설계된 것이라 명시적으로 닫을 필요가 없음.

        finishUp(context, alarmId)
    }

    /** 알람을 N분 뒤로 미룸. 성공 시 새 시간 정보 반환, 실패(알람 없음 등)면 null */
    fun snooze(context: Context, alarmId: Int, minutes: Int = 5): SnoozeResult? {
        val dbHelper = DatabaseHelper.getInstance(context)
        // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 - DatabaseHelper.kt 상세 주석 참고.
        val db = dbHelper.getWritableDatabaseWithRetry() ?: run {
            Log.e(TAG, "❌ snooze: DB 파일 없음 id=$alarmId")
            return null
        }
        var result: SnoozeResult? = null

        try {
            var alarmTypeId = 1
            var shiftType = "알람"
            var originalTime = ""
            var originalDate = ""
            var dayOffset = 0
            var found = false

            db.query("alarms", null, "id = ?", arrayOf(alarmId.toString()), null, null, null).use { cursor ->
                if (cursor.moveToFirst()) {
                    found = true
                    alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id"))
                    shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                    originalTime = cursor.getString(cursor.getColumnIndexOrThrow("time")) ?: ""
                    originalDate = cursor.getString(cursor.getColumnIndexOrThrow("date")) ?: ""
                    val dayOffsetIdx = cursor.getColumnIndex("day_offset")
                    dayOffset = if (dayOffsetIdx >= 0) cursor.getInt(dayOffsetIdx) else 0
                }
            }

            if (!found) {
                Log.e(TAG, "❌ snooze: 알람 정보 없음 id=$alarmId")
                return null
            }

            // ⭐ 시간 충돌 시 최대 +5분까지 뒤로 조정 (기존 여러 구현에 흩어져 있던 로직 통일)
            var adjustedMinutes = minutes
            var newTimestamp = System.currentTimeMillis() + (adjustedMinutes * 60 * 1000)
            val maxAdjustment = minutes + 5
            while (dbHelper.isTimeConflict(db, newTimestamp, alarmId) && adjustedMinutes < maxAdjustment) {
                adjustedMinutes++
                newTimestamp = System.currentTimeMillis() + (adjustedMinutes * 60 * 1000)
                Log.d(TAG, "⚠️ 시간 충돌 감지 → ${adjustedMinutes}분 후로 조정")
            }

            // ⭐ 2026-09-14 (출시전 감사 #16/#27) - OS 예약은 DB 커밋 뒤로 옮김(아래). 새 시각은 초 단위로 맞춰
            // DB 문자열·수신 시 예정 시각 대조와 정확히 일치하게 함
            newTimestamp = AlarmWakeScheduler.normalize(newTimestamp)

            val dateStr = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date(newTimestamp))
            val timeStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(newTimestamp))

            db.beginTransaction()
            try {
                val values = ContentValues().apply {
                    put("date", dateStr)
                    put("time", timeStr)
                    put("type", "snoozed")  // 자동 갱신 diff 대상에서 제외되어 보호됨
                }
                db.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))

                if (originalTime.isNotEmpty() && originalDate.isNotEmpty()) {
                    insertHistory(db, alarmId, originalDate, originalTime, shiftType, dayOffset, "snoozed")
                }
                // ⭐ 스누즈도 "새로 예약된 인스턴스"이므로 생성 이력 원장에 남김
                insertCreationLog(db, alarmId, dateStr, timeStr, shiftType, alarmTypeId, dayOffset, "snoozed")

                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }

            result = SnoozeResult(timeStr, shiftType)
            // ⭐ #16 - 커밋 뒤 OS 반영(행 재확인). 실패하면 AlarmWakeScheduler가 기록해 다음 트리거에 재시도
            if (AlarmWakeScheduler.scheduleIfCurrent(context, db, alarmId, newTimestamp, shiftType) ==
                AlarmWakeScheduler.Outcome.FAILED) {
                Log.e(TAG, "❌ 스누즈 OS 예약 실패(재시도 목록에 기록): alarmId=$alarmId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ snooze 실패: alarmId=$alarmId", e)
        }
        // ⭐ db.close() 제거 (dismiss()와 동일한 이유 - 위 주석 참고)

        if (result != null) {
            finishUp(context, alarmId)
        }
        return result
    }

    fun timeout(context: Context, alarmId: Int) = dismiss(context, alarmId, "timeout")

    // ⭐ 2026-08-25 - 겹쳐 울리는 알람 대응. 이 알람이 아직 응답(끄기/스누즈/타임아웃)되기
    // 전에 다음 알람이 도착해서 화면/소리를 넘겨받아야 하는 경우 CustomAlarmReceiver가
    // 호출함 - dismiss()를 그대로 재사용하되(취소/삭제/이력 로직 전부 동일), dismissType만
    // 구분해서 "사용자가 직접 끈 게 아니라 다음 알람에 밀려 자동 종료됐다"는 사실이
    // 이력에 남게 함 (RingingAlarmTracker.kt 클래스 주석 참고).
    fun supersede(context: Context, alarmId: Int) = dismiss(context, alarmId, "superseded_by_next_alarm")

    // ─────────────────────────────────────────────────────────────────────────
    // ⭐ 2026-09-14 (출시전 감사 #3/#14, G1) - 울림 회차 관문 + 네이티브 종료 예약.
    // 예전엔 자동 종료가 AlarmActivity/AlarmOverlayService의 Handler 타이머에만 있어서, 잠금화면
    // 알람에서 홈으로 나가면(noHistory로 Activity 파괴 → onDestroy에서 타이머 취소) 끌 때까지 계속
    // 울렸음. 이제 CustomAlarmReceiver가 울리는 순간 이 회차의 종료를 AlarmManager에 예약하고
    // (AlarmActionReceiver.ACTION_RING_TIMEOUT), 화면·오버레이 타이머는 같은 회차로 보호한 채 남겨둠 -
    // 먼저 오는 쪽이 끝내고, 나중 신호는 회차가 이미 폐기돼 무시됨. 화면 타이머 제거 여부는
    // 실기기 S4(홈·잠금·Doze에서 지속시간)를 확인한 뒤 결정.
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * 울림 종료 관문. 끄기·스누즈·인계·타임아웃은 소리를 멈추거나 DB를 건드리기 **전에** 이걸 먼저
     * 통과해야 함. (ID, 회차)가 지금 울리는 회차일 때만 회차를 폐기하고 그 회차의 종료 예약을 취소한 뒤
     * true. 아니면(지난 회차의 늦은 신호 - 예: 스누즈 전 화면 타이머가 스누즈 후 재울림을 끄려는 경우)
     * 아무것도 안 바꾸고 false.
     */
    fun claimRingEnd(context: Context, alarmId: Int, round: Long): Boolean {
        if (!RingingAlarmTracker.endIfCurrent(context, alarmId, round)) return false
        cancelRingTimeout(context, alarmId, round)
        return true
    }

    /** 회차를 모르는 "지금 이 알람" 요청용(앱에서 삭제·외부 오버레이 종료) - 활성 울림의 ID가 같을 때만 끝냄. */
    fun claimCurrentRingOf(context: Context, alarmId: Int): Boolean {
        val ring = RingingAlarmTracker.endCurrentOf(context, alarmId) ?: return false
        cancelRingTimeout(context, ring.alarmId, ring.round)
        return true
    }

    /** #14 - 이 알람이 지금 울리는 중인가. 재생기 상태가 아니라 활성 회차 기준이라 진동·무음 알람도 포함. */
    fun isAlarmRinging(context: Context, alarmId: Int): Boolean =
        RingingAlarmTracker.current(context)?.alarmId == alarmId

    /**
     * #14 - 앱에서 알람을 삭제할 때(Flutter alarm_provider.deleteAlarm) 그 알람이 지금 울리는 중이면
     * 울림만 끝냄(소리·화면·오버레이·제어 알림). DB 행/이력은 호출한 Dart가 처리함. 다른 알람이
     * 울리는 중이면 아무것도 안 하고 false.
     */
    fun stopRingingAlarm(context: Context, alarmId: Int): Boolean {
        if (!claimCurrentRingOf(context, alarmId)) return false
        AlarmPlayer.getInstance(context.applicationContext).stopAlarm()
        closeRingUi(context, alarmId)
        return true
    }

    /** 화면 밖에서 울림을 끝냈을 때(종료 예약·앱 삭제) 떠 있는 잠금화면/오버레이/울림 알림을 닫음. */
    fun closeRingUi(context: Context, alarmId: Int) {
        try {
            context.sendBroadcast(Intent("FINISH_ALARM_ACTIVITY").apply {
                setPackage(context.packageName)
                putExtra("alarmId", alarmId)
            })
            // 오버레이는 이 신호에 창만 닫음 - 회차가 이미 폐기돼 소리를 다시 건드리지 않음
            context.sendBroadcast(Intent(AlarmOverlayService.ACTION_DISMISS_OVERLAY).apply {
                setPackage(context.packageName)
                putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
            })
        } catch (e: Exception) {
            Log.e(TAG, "❌ 울림 화면 종료 신호 실패: id=$alarmId", e)
        }
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.cancel(alarmId)          // 알람 ID
            nm.cancel(alarmId + 100000) // Fallback notification
            nm.cancel(7777)             // 제어
            nm.cancel(8889)             // 스누즈/타임아웃
        } catch (e: Exception) {
            Log.e(TAG, "❌ 울림 알림 정리 실패: id=$alarmId", e)
        }
    }

    /** 이 회차의 자동 종료를 예약. 같은 알람의 다른 회차 예약과는 data URI로 구분됨. */
    fun scheduleRingTimeout(context: Context, ring: RingingAlarmTracker.ActiveRing, durationMinutes: Int) {
        val minutes = durationMinutes.coerceAtLeast(1)
        val triggerAt = System.currentTimeMillis() + minutes * 60_000L
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = ringTimeoutPendingIntent(context, ring.alarmId, ring.round, PendingIntent.FLAG_UPDATE_CURRENT)
                ?: throw IllegalStateException("PendingIntent 생성 실패")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                }
            } catch (e: SecurityException) {
                // 정확한 알람 권한이 꺼진 경우 - 조금 늦더라도 끝나긴 하도록 비정확 예약으로 대체
                Log.w(TAG, "⚠️ 정확한 종료 예약 불가 - 비정확 예약으로 대체", e)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                }
            }
            Log.d(TAG, "⏱️ 울림 종료 예약: id=${ring.alarmId} 회차=${ring.round} ${minutes}분 후")
        } catch (e: Exception) {
            // 예약 실패 시에도 화면·오버레이 타이머는 남아 있음(그래서 아직 제거하지 않음)
            Log.e(TAG, "❌ 울림 종료 예약 실패: $ring", e)
        }
    }

    private fun cancelRingTimeout(context: Context, alarmId: Int, round: Long) {
        try {
            val pendingIntent = ringTimeoutPendingIntent(context, alarmId, round, PendingIntent.FLAG_NO_CREATE) ?: return
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "❌ 울림 종료 예약 취소 실패: id=$alarmId 회차=$round", e)
        }
    }

    internal fun ringTimeoutPendingIntent(context: Context, alarmId: Int, round: Long, flag: Int): PendingIntent? {
        val intent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_RING_TIMEOUT
            data = android.net.Uri.parse("shiftbell://ring-timeout/$alarmId/$round")
            putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
        }
        return PendingIntent.getBroadcast(context, alarmId, intent, flag or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun finishUp(context: Context, alarmId: Int) {
        // ⭐ 2026-09-14 (#3) - 울림 추적(RingingAlarmTracker) 폐기는 여기서 하지 않음. 모든 종료 경로가
        // 소리/DB에 손대기 전에 claimRingEnd(ID, 회차)로 먼저 폐기함 - 여기서 ID만으로 지우면 같은 ID의
        // 새 회차(스누즈 후 재울림)까지 지워버릴 수 있음.
        AlarmGuardReceiver.removeShownNotification(alarmId)
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        context.sendBroadcast(Intent(context, AlarmGuardReceiver::class.java))
        notifyFlutter(context)
    }

    private fun insertHistory(db: android.database.sqlite.SQLiteDatabase, alarmId: Int, date: String, time: String, shiftType: String, dayOffset: Int, dismissType: String) {
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        val values = ContentValues().apply {
            put("alarm_id", alarmId)
            put("scheduled_time", time)
            put("scheduled_date", date)
            put("actual_ring_time", now)
            put("dismiss_type", dismissType)
            put("snooze_count", 0)
            put("shift_type", shiftType)
            put("created_at", now)
            put("day_offset", dayOffset)
        }
        db.insert("alarm_history", null, values)
    }

    private fun insertCreationLog(db: android.database.sqlite.SQLiteDatabase, alarmId: Int, date: String, time: String, shiftType: String, alarmTypeId: Int, dayOffset: Int, source: String) {
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        val values = ContentValues().apply {
            put("alarm_id", alarmId)
            put("scheduled_date", date)
            put("scheduled_time", time)
            put("shift_type", shiftType)
            put("alarm_type_id", alarmTypeId)
            put("source", source)
            put("created_at", now)
            put("day_offset", dayOffset)
        }
        db.insert("alarm_creation_log", null, values)
    }

    private fun notifyFlutter(context: Context) {
        try {
            context.sendBroadcast(Intent("com.hwani1103.shiftbell.FLUTTER_REFRESH"))
        } catch (e: Exception) {
            Log.e(TAG, "Flutter 알림 실패", e)
        }
    }
}
