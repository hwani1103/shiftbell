// android/app/src/main/kotlin/com/example/shiftbell/DirectBootReceiver.kt

package com.example.shiftbell

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
            
            val nextAlarm = getNextAlarmFromDB(context)
            
            if (nextAlarm != null) {
                scheduleNativeAlarm(
                    context = context,
                    id = nextAlarm.id,
                    timestamp = nextAlarm.timestamp,
                    label = nextAlarm.shiftType
                )
                
                Log.e("DirectBoot", "✅ 긴급 알람 등록: ${nextAlarm.shiftType} ${nextAlarm.time}")
            } else {
                Log.e("DirectBoot", "⚠️ 등록할 알람 없음")
            }
            
            // ⭐ AlarmGuardReceiver 예약
            scheduleGuardWakeup(context)
            
            Log.e("DirectBoot", "========== DIRECT BOOT COMPLETE ==========")
        } catch (e: Exception) {
            Log.e("DirectBoot", "========== ERROR ==========", e)
        }
    }
    
    private fun scheduleGuardWakeup(context: Context) {
        val intent = Intent(context, AlarmGuardReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // 자정 예약
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                midnight,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                midnight,
                pendingIntent
            )
        }
        
        Log.e("DirectBoot", "✅ AlarmGuardReceiver 예약 완료")
    }
    
    private fun saveBootTime(context: Context) {
        val prefs = context.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        val bootTime = System.currentTimeMillis()
        prefs.edit().putLong("last_boot_time", bootTime).apply()
        
        Log.d("DirectBoot", "📝 부팅 시각 저장: ${Date(bootTime)}")
    }
    
    private fun getNextAlarmFromDB(context: Context): AlarmData? {
        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase
            
            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.getDefault()
            ).format(Date())
            
            Log.d("DirectBoot", "현재 시각: $now")
            
            val cursor = db.query(
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
            
            cursor.close()
            db.close()
            
            alarm
        } catch (e: Exception) {
            Log.e("DirectBoot", "DB 읽기 실패", e)
            null
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