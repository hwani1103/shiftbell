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
        val db = dbHelper.writableDatabase

        try {
            cancelNativeAlarm(context, alarmId)

            db.beginTransaction()
            try {
                db.query(
                    "alarms", arrayOf("time", "date", "shift_type"),
                    "id = ?", arrayOf(alarmId.toString()), null, null, null
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val time = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                        val date = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                        val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: ""
                        if (time != null && date != null) {
                            insertHistory(db, alarmId, date, time, shiftType, dismissType)
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
        } finally {
            db.close()
        }

        finishUp(context, alarmId)
    }

    /** 알람을 N분 뒤로 미룸. 성공 시 새 시간 정보 반환, 실패(알람 없음 등)면 null */
    fun snooze(context: Context, alarmId: Int, minutes: Int = 5): SnoozeResult? {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.writableDatabase
        var result: SnoozeResult? = null

        try {
            var alarmTypeId = 1
            var shiftType = "알람"
            var originalTime = ""
            var originalDate = ""
            var found = false

            db.query("alarms", null, "id = ?", arrayOf(alarmId.toString()), null, null, null).use { cursor ->
                if (cursor.moveToFirst()) {
                    found = true
                    alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id"))
                    shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                    originalTime = cursor.getString(cursor.getColumnIndexOrThrow("time")) ?: ""
                    originalDate = cursor.getString(cursor.getColumnIndexOrThrow("date")) ?: ""
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

            cancelNativeAlarm(context, alarmId)
            scheduleNativeAlarmAt(context, alarmId, newTimestamp, shiftType)

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
                    insertHistory(db, alarmId, originalDate, originalTime, shiftType, "snoozed")
                }
                // ⭐ 스누즈도 "새로 예약된 인스턴스"이므로 생성 이력 원장에 남김
                insertCreationLog(db, alarmId, dateStr, timeStr, shiftType, alarmTypeId, "snoozed")

                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }

            result = SnoozeResult(timeStr, shiftType)
        } catch (e: Exception) {
            Log.e(TAG, "❌ snooze 실패: alarmId=$alarmId", e)
        } finally {
            db.close()
        }

        if (result != null) {
            finishUp(context, alarmId)
        }
        return result
    }

    fun timeout(context: Context, alarmId: Int) = dismiss(context, alarmId, "timeout")

    private fun finishUp(context: Context, alarmId: Int) {
        AlarmGuardReceiver.removeShownNotification(alarmId)
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        context.sendBroadcast(Intent(context, AlarmGuardReceiver::class.java))
        notifyFlutter(context)
    }

    private fun cancelNativeAlarm(context: Context, alarmId: Int) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, alarmId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Native 알람 취소 실패: id=$alarmId", e)
        }
    }

    private fun scheduleNativeAlarmAt(context: Context, alarmId: Int, timestamp: Long, shiftType: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
            putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, alarmId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
        }
    }

    private fun insertHistory(db: android.database.sqlite.SQLiteDatabase, alarmId: Int, date: String, time: String, shiftType: String, dismissType: String) {
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
        }
        db.insert("alarm_history", null, values)
    }

    private fun insertCreationLog(db: android.database.sqlite.SQLiteDatabase, alarmId: Int, date: String, time: String, shiftType: String, alarmTypeId: Int, source: String) {
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        val values = ContentValues().apply {
            put("alarm_id", alarmId)
            put("scheduled_date", date)
            put("scheduled_time", time)
            put("shift_type", shiftType)
            put("alarm_type_id", alarmTypeId)
            put("source", source)
            put("created_at", now)
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
