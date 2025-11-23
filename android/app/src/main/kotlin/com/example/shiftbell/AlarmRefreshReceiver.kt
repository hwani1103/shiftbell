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

class AlarmRefreshReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmRefresh", "========== 자정 갱신 시작 ==========")
        
        try {
            // 1. 스케줄 체크 (규칙적인지 확인)
            if (!isRegularSchedule(context)) {
                Log.d("AlarmRefresh", "⏭️ 불규칙 스케줄 - 갱신 스킵")
                return
            }
            
            // 2. 기존 알람 전부 삭제
            deleteAllAlarms(context)
            
            // 3. 10일치 알람 재생성
            generate10DaysAlarms(context)
            
            // 4. 갱신 완료 표시 (Flutter용)
            markRefreshed(context)
            
            // 5. Flutter UI 갱신 트리거 (앱 켜져있으면)
            notifyFlutter(context)
            
            Log.d("AlarmRefresh", "========== 자정 갱신 완료 ==========")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "========== 갱신 실패 ==========", e)
        }
    }
    
    // 규칙적 스케줄인지 확인
    private fun isRegularSchedule(context: Context): Boolean {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase
            
            val cursor = db.query("shift_schedule", null, null, null, null, null, null, "1")
            
            if (!cursor.moveToFirst()) {
                cursor.close()
                db.close()
                return false
            }
            
            val isRegular = cursor.getInt(cursor.getColumnIndexOrThrow("is_regular")) == 1
            cursor.close()
            db.close()
            
            return isRegular
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "스케줄 조회 실패", e)
            return false
        }
    }
    
    // 기존 알람 전부 삭제
    private fun deleteAllAlarms(context: Context) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            
            // DB에서 모든 알람 조회
            val cursor = db.query("alarms", null, null, null, null, null, null)
            val alarmIds = mutableListOf<Int>()
            
            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                alarmIds.add(id)
            }
            cursor.close()
            
            // Native 알람 취소
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (id in alarmIds) {
                val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$id")
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    id,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
            }
            
            // DB에서 삭제
            db.delete("alarms", null, null)
            db.close()
            
            Log.d("AlarmRefresh", "🗑️ 기존 알람 ${alarmIds.size}개 삭제 완료")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "알람 삭제 실패", e)
        }
    }
    
    // 10일치 알람 생성
    private fun generate10DaysAlarms(context: Context) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            
            // 1. 스케줄 조회
            val scheduleCursor = db.query("shift_schedule", null, null, null, null, null, null, "1")
            if (!scheduleCursor.moveToFirst()) {
                scheduleCursor.close()
                return
            }
            
            val pattern = scheduleCursor.getString(scheduleCursor.getColumnIndexOrThrow("pattern")).split(",")
            val todayIndex = scheduleCursor.getInt(scheduleCursor.getColumnIndexOrThrow("today_index"))
            val startDateStr = scheduleCursor.getString(scheduleCursor.getColumnIndexOrThrow("start_date"))
            scheduleCursor.close()
            
            // 2. 템플릿 조회
            val templateCursor = db.query("shift_alarm_templates", null, null, null, null, null, null)
            val templates = mutableMapOf<String, MutableList<Pair<String, Int>>>()
            
            while (templateCursor.moveToNext()) {
                val shiftType = templateCursor.getString(templateCursor.getColumnIndexOrThrow("shift_type"))
                val time = templateCursor.getString(templateCursor.getColumnIndexOrThrow("time"))
                val alarmTypeId = templateCursor.getInt(templateCursor.getColumnIndexOrThrow("alarm_type_id"))
                
                if (!templates.containsKey(shiftType)) {
                    templates[shiftType] = mutableListOf()
                }
                templates[shiftType]?.add(Pair(time, alarmTypeId))
            }
            templateCursor.close()
            
            // 3. 10일치 생성
            val today = Calendar.getInstance()
            val startDate = Calendar.getInstance().apply {
                time = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).parse(startDateStr)!!
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            var createdCount = 0
            
            for (i in 0 until 10) {
                val targetDate = Calendar.getInstance().apply {
                    timeInMillis = today.timeInMillis
                    add(Calendar.DAY_OF_MONTH, i)
                }
                
                // 패턴에서 근무 종류 찾기
                val daysDiff = ((targetDate.timeInMillis - startDate.timeInMillis) / (24 * 60 * 60 * 1000)).toInt()
                val patternIndex = ((todayIndex + daysDiff) % pattern.size + pattern.size) % pattern.size
                val shiftType = pattern[patternIndex]
                
                // 해당 근무의 알람 템플릿 찾기
                val shiftTemplates = templates[shiftType] ?: continue
                
                for ((time, alarmTypeId) in shiftTemplates) {
                    val timeParts = time.split(":")
                    val alarmTime = Calendar.getInstance().apply {
                        timeInMillis = targetDate.timeInMillis
                        set(Calendar.HOUR_OF_DAY, timeParts[0].toInt())
                        set(Calendar.MINUTE, timeParts[1].toInt())
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    
                    // 과거 알람 스킵
                    if (alarmTime.timeInMillis < System.currentTimeMillis() - 60000) {
                        continue
                    }
                    
                    // DB 저장
                    val values = android.content.ContentValues().apply {
                        put("time", time)
                        put("date", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(alarmTime.time))
                        put("type", "fixed")
                        put("alarm_type_id", alarmTypeId)
                        put("shift_type", shiftType)
                    }
                    
                    val alarmId = db.insert("alarms", null, values).toInt()
                    
                    // Native 알람 등록
                    val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                        data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                        putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
                        putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
                        putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                    }
                    
                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        alarmId,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            alarmTime.timeInMillis,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP,
                            alarmTime.timeInMillis,
                            pendingIntent
                        )
                    }
                    
                    createdCount++
                }
            }
            
            db.close()
            Log.d("AlarmRefresh", "✅ ${createdCount}개 알람 생성 완료")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "알람 생성 실패", e)
        }
    }
    
    // 갱신 완료 표시 (Flutter용)
    // AlarmRefreshReceiver.kt - markRefreshed() 수정

private fun markRefreshed(context: Context) {
    try {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        
        val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        
        // ⭐ alarm_state에만 저장 (Flutter SharedPreferences와 분리)
        prefs.edit()
            .putLong("last_alarm_refresh", now)
            .apply()
        
        val date = Calendar.getInstance().apply { timeInMillis = now }
        Log.d("AlarmRefresh", "✅ 갱신 완료 표시: ${date.get(Calendar.YEAR)}-${date.get(Calendar.MONTH)+1}-${date.get(Calendar.DAY_OF_MONTH)}")
    } catch (e: Exception) {
        Log.e("AlarmRefresh", "갱신 표시 실패", e)
    }
}
    
    // Flutter에 갱신 알림 (앱 켜져있으면)
    private fun notifyFlutter(context: Context) {
        try {
            val intent = Intent("com.example.shiftbell.FLUTTER_REFRESH")
            context.sendBroadcast(intent)
            Log.d("AlarmRefresh", "📢 Flutter 갱신 트리거")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "Flutter 알림 실패", e)
        }
    }
}