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
                Log.d("AlarmRefresh", "⏭️ 불규칙 스케줄 - 기존 알람 재등록만 수행")

                // ⭐ 불규칙 스케줄: DB에 있는 알람을 Native에 재등록
                reRegisterExistingAlarms(context)

                // 10일 이상 지난 알람 이력 삭제
                deleteOldAlarmHistory(context)

                // 갱신 완료 표시
                markRefreshed(context)

                // Flutter UI 갱신 트리거
                notifyFlutter(context)

                Log.d("AlarmRefresh", "========== 불규칙 스케줄 재등록 완료 ==========")
                return
            }

            // 2. 기존 알람 전부 삭제
            deleteAllAlarms(context)

            // 3. 10일치 알람 재생성
            generate10DaysAlarms(context)

            // 4. ⭐ 10일 이상 지난 알람 이력 삭제
            deleteOldAlarmHistory(context)

            // 5. 갱신 완료 표시 (Flutter용)
            markRefreshed(context)

            // 6. Flutter UI 갱신 트리거 (앱 켜져있으면)
            notifyFlutter(context)

            Log.d("AlarmRefresh", "========== 자정 갱신 완료 ==========")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "========== 갱신 실패 ==========", e)
        }
    }
    
    // 규칙적 스케줄인지 확인
    private fun isRegularSchedule(context: Context): Boolean {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.readableDatabase

            cursor = db.query("shift_schedule", null, null, null, null, null, null, "1")

            if (!cursor.moveToFirst()) {
                return false
            }

            cursor.getInt(cursor.getColumnIndexOrThrow("is_regular")) == 1
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "스케줄 조회 실패", e)
            false
        } finally {
            cursor?.close()
            db?.close()
        }
    }
    
    // 기존 알람 전부 삭제 (스누즈 알람 보호)
    private fun deleteAllAlarms(context: Context) {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.writableDatabase

            // ⭐ CRITICAL FIX: type='fixed'인 알람만 조회 (스누즈 알람 보호)
            cursor = db.query(
                "alarms",
                null,
                "type = ?",
                arrayOf("fixed"),
                null, null, null
            )
            val alarmIds = mutableListOf<Int>()

            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                alarmIds.add(id)
            }

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

            // ⭐ CRITICAL FIX: type='fixed'인 알람만 삭제 (스누즈 알람 보호)
            db.delete("alarms", "type = ?", arrayOf("fixed"))

            Log.d("AlarmRefresh", "🗑️ 고정 알람 ${alarmIds.size}개 삭제 완료 (스누즈 보호)")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "알람 삭제 실패", e)
        } finally {
            cursor?.close()
            db?.close()
        }
    }
    
    // 10일치 알람 생성
    private fun generate10DaysAlarms(context: Context) {
        var scheduleCursor: android.database.Cursor? = null
        var templateCursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.writableDatabase

            // 1. 스케줄 조회
            scheduleCursor = db.query("shift_schedule", null, null, null, null, null, null, "1")
            if (!scheduleCursor.moveToFirst()) {
                return
            }

            val patternStr = scheduleCursor.getString(scheduleCursor.getColumnIndexOrThrow("pattern"))
            if (patternStr.isNullOrEmpty()) {
                Log.d("AlarmRefresh", "⚠️ Pattern null/empty - 불규칙 스케줄로 간주, 스킵")
                return
            }
            val pattern = patternStr.split(",")
            val todayIndex = scheduleCursor.getInt(scheduleCursor.getColumnIndexOrThrow("today_index"))
            val startDateStr = scheduleCursor.getString(scheduleCursor.getColumnIndexOrThrow("start_date"))

            // 2. 템플릿 조회
            templateCursor = db.query("shift_alarm_templates", null, null, null, null, null, null)
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

            // 3. 10일치 생성
            val today = Calendar.getInstance()

            // ⭐ CRITICAL FIX #3: Null 안전성 처리
            val parsedDate = try {
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).parse(startDateStr)
            } catch (e: Exception) {
                Log.e("AlarmRefresh", "❌ startDate 파싱 실패: $startDateStr", e)
                return  // 파싱 실패 시 알람 생성 중단
            }

            if (parsedDate == null) {
                Log.e("AlarmRefresh", "❌ startDate가 null")
                return
            }

            val startDate = Calendar.getInstance().apply {
                time = parsedDate
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            var createdCount = 0

            for (i in 0 until 2) {  // ⭐ 테스트용: 10 → 2
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

                    // ⭐ CRITICAL FIX #2: Long to Int 안전 변환 (오버플로우 방지)
                    val rowId = db.insert("alarms", null, values)
                    if (rowId == -1L) {
                        Log.e("AlarmRefresh", "❌ DB 삽입 실패")
                        continue
                    }
                    if (rowId > Int.MAX_VALUE) {
                        Log.e("AlarmRefresh", "❌ 알람 ID 오버플로우: $rowId (스킵)")
                        continue
                    }
                    val alarmId = rowId.toInt()

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

            Log.d("AlarmRefresh", "✅ ${createdCount}개 알람 생성 완료")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "알람 생성 실패", e)
        } finally {
            templateCursor?.close()
            scheduleCursor?.close()
            db?.close()
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

    // ⭐ 10일 이상 지난 알람 이력 삭제
    private fun deleteOldAlarmHistory(context: Context) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase

            // 10일 전 날짜 계산
            val calendar = Calendar.getInstance()
            calendar.add(Calendar.DAY_OF_YEAR, -10)
            val cutoffDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(calendar.time)

            // 10일 이상 지난 이력 삭제
            val deletedCount = db.delete(
                "alarm_history",
                "created_at < ?",
                arrayOf(cutoffDate)
            )

            db.close()

            if (deletedCount > 0) {
                Log.d("AlarmRefresh", "🗑️ 10일 이상 지난 알람 이력 ${deletedCount}개 삭제 완료")
            }
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "⚠️ 오래된 알람 이력 삭제 실패", e)
        }
    }

    // ⭐ 불규칙 스케줄: DB에 있는 모든 알람을 Native에 재등록
    private fun reRegisterExistingAlarms(context: Context) {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.readableDatabase

            // 현재 시각 이후의 모든 알람 조회
            val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            cursor = db.query(
                "alarms",
                null,
                "date > ?",
                arrayOf(now),
                null,
                null,
                "date ASC"
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            var reRegisteredCount = 0

            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                val dateStr = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"

                val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).parse(dateStr)?.time

                if (timestamp != null && timestamp > System.currentTimeMillis()) {
                    // Native 알람 재등록
                    val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
                        data = android.net.Uri.parse("shiftbell://alarm/$id")
                        putExtra(CustomAlarmReceiver.EXTRA_ID, id)
                        putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
                        putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                    }

                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        id,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            timestamp,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP,
                            timestamp,
                            pendingIntent
                        )
                    }

                    reRegisteredCount++
                }
            }

            Log.d("AlarmRefresh", "✅ 불규칙 스케줄 알람 ${reRegisteredCount}개 재등록 완료")
        } catch (e: Exception) {
            Log.e("AlarmRefresh", "❌ 알람 재등록 실패", e)
        } finally {
            cursor?.close()
            db?.close()
        }
    }
}