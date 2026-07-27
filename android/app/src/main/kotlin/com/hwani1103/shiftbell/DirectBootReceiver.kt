// android/app/src/main/kotlin/com/example/shiftbell/DirectBootReceiver.kt

package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

class DirectBootReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            Log.d("DirectBoot", "⏭️ 다른 액션: ${intent.action}")
            return
        }
        
        Log.e("DirectBoot", "========== LOCKED BOOT DETECTED ==========")
        
        try {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }

            saveBootTime(deviceContext)

            // ⭐ 1단계: 가장 가까운 알람은 최대한 빨리 즉시 등록 (가장 빠른 안전장치)
            val nextAlarm = getNextAlarmFromDB(context)
            if (nextAlarm != null) {
                scheduleNativeAlarm(
                    context = context,
                    id = nextAlarm.id,
                    timestamp = nextAlarm.timestamp,
                    label = nextAlarm.shiftType
                )
                Log.e("DirectBoot", "✅ 긴급 알람 즉시 등록: ${nextAlarm.shiftType} ${nextAlarm.time}")
            } else {
                Log.e("DirectBoot", "⚠️ 등록할 알람 없음")
            }

            // ⭐ 2단계: CRITICAL FIX - 나머지 미래 알람도 전부 즉시 재등록.
            // 예전엔 여기서 가장 가까운 알람 1개만 등록하고 나머지는 "다음 자정"까지
            // 기다렸는데, 그러면 재부팅 당일에 알람이 2개 이상 남아있는 경우
            // (예: 같은 날 출근 알람 + 다른 알람) 두 번째 알람은 자정 전까지
            // AlarmManager에 전혀 등록되지 않은 상태로 방치되어 조용히 울리지 않을 수 있었음.
            // AlarmRefreshEngine.refresh()가 재부팅 여부와 무관하게 즉시 전체 재조정하면서
            // DB에 있는 모든 미래 알람을 다시 등록해줌.
            AlarmRefreshEngine.refresh(context)

            // ⭐ 3단계: Guard 하트비트 재가동 (다음 알람 20분 전 / 자정 중 더 이른 시점으로 예약)
            // 예전의 자체 scheduleGuardWakeup()은 무조건 "다음 자정"만 예약해서 부정확했음.
            AlarmGuardReceiver.triggerCheck(context)

            Log.e("DirectBoot", "========== DIRECT BOOT COMPLETE ==========")
        } catch (e: Exception) {
            Log.e("DirectBoot", "========== ERROR ==========", e)
        }
    }
    
    private fun saveBootTime(context: Context) {
        val prefs = context.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        val bootTime = System.currentTimeMillis()
        prefs.edit()
            .putLong("last_boot_time", bootTime)
            .putLong("last_alarm_refresh", 0L)  // ⭐ 재부팅 시 갱신 플래그 리셋!
            .apply()

        Log.d("DirectBoot", "📝 부팅 시각 저장 & 갱신 플래그 리셋: ${Date(bootTime)}")
    }
    
    private fun getNextAlarmFromDB(context: Context): AlarmData? {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.readableDatabase

            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.getDefault()
            ).format(Date())

            Log.d("DirectBoot", "현재 시각: $now")

            cursor = db.query(
                "alarms",
                null,
                "date > ?",
                arrayOf(now),
                null,
                null,
                "date ASC",
                "1"
            )

            var alarm: AlarmData? = null

            if (cursor.moveToFirst()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                val dateStr = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                val time = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"

                val timestamp = SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss",
                    Locale.getDefault()
                ).parse(dateStr)?.time

                if (timestamp != null) {
                    alarm = AlarmData(id, timestamp, time, shiftType)
                    Log.d("DirectBoot", "✅ 다음 알람 조회: $time ($shiftType)")
                }
            } else {
                Log.d("DirectBoot", "⚠️ DB에 알람 없음")
            }

            alarm
        } catch (e: Exception) {
            Log.e("DirectBoot", "DB 읽기 실패", e)
            null
        } finally {
            cursor?.close()
            db?.close()
        }
    }
    
    private fun scheduleNativeAlarm(
        context: Context,
        id: Int,
        timestamp: Long,
        label: String
    ) {
        try {
            val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                putExtra(CustomAlarmReceiver.EXTRA_ID, id)
                putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
                putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                setPackage(context.packageName)
                data = android.net.Uri.parse("shiftbell://alarm/$id")  // ⭐ PendingIntent 충돌 방지
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val alarmClockInfo = AlarmManager.AlarmClockInfo(timestamp, pendingIntent)
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            
            Log.d("DirectBoot", "✅ Native 알람 등록 (AlarmClock): ID=$id, timestamp=$timestamp")
        } catch (e: Exception) {
            Log.e("DirectBoot", "Native 알람 등록 실패: ID=$id", e)
        }
    }
    
    data class AlarmData(
        val id: Int,
        val timestamp: Long,
        val time: String,
        val shiftType: String
    )
}