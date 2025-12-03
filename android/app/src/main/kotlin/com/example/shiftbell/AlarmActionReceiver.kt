// android/app/src/main/kotlin/com/example/shiftbell/AlarmActionReceiver.kt

package com.example.shiftbell

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_DELETE_SNOOZE_NOTIFICATION = "DELETE_SNOOZE_NOTIFICATION"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("alarmId", 0)

        when (intent.action) {
            // ⭐ 30초 후 8889 자동 삭제
            ACTION_DELETE_SNOOZE_NOTIFICATION -> {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8889)
                Log.d("AlarmAction", "🗑️ 8889 Notification 자동 삭제 (30초 경과)")
            }
            // ⭐ 홈 버튼 후 Notification에서 알람 끄기
            "DISMISS_FROM_NOTIFICATION" -> {
                Log.d("AlarmAction", "🔔 Notification에서 알람 끄기: ID=$alarmId")

                // ⭐ AlarmActivity 종료
                val finishIntent = Intent("FINISH_ALARM_ACTIVITY").apply {
                    setPackage(context.packageName)
                    putExtra("alarmId", alarmId)
                }
                context.sendBroadcast(finishIntent)

                // 알람 소리 중지
                AlarmPlayer.getInstance(context).stopAlarm()

                // 알람 삭제
                deleteAlarmFromDB(context, alarmId)

                // 7777 Notification 삭제
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(7777)
                notificationManager.cancel(8888)
                notificationManager.cancel(8889)
                Log.d("AlarmAction", "✅ Notification 삭제 완료")
            }
            // ⭐ 홈 버튼 후 Notification에서 5분 후
            "SNOOZE_FROM_NOTIFICATION" -> {
                Log.d("AlarmAction", "⏰ Notification에서 5분 후: ID=$alarmId")

                // ⭐ AlarmActivity 종료
                val finishIntent = Intent("FINISH_ALARM_ACTIVITY").apply {
                    setPackage(context.packageName)
                    putExtra("alarmId", alarmId)
                }
                context.sendBroadcast(finishIntent)

                // 알람 소리 중지
                AlarmPlayer.getInstance(context).stopAlarm()

                // 5분 후 재등록
                snoozeAlarmFromDB(context, alarmId)

                // 7777 Notification 삭제
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(7777)
                Log.d("AlarmAction", "✅ 7777 Notification 삭제 완료")
            }
            "CANCEL_ALARM" -> {
                Log.d("AlarmAction", "🗑️ 알람 취소: ID=$alarmId")

                // ⭐ DB에 알람이 있는지 먼저 확인 (삼성 "알림 다시 표시" 대응)
                if (!isAlarmExistsInDB(context, alarmId)) {
                    Log.d("AlarmAction", "⚠️ DB에 알람 없음 (이미 삭제됨) - notification만 닫기")
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(8888)
                    notificationManager.cancel(8889)
                    return
                }

                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"

                // ⭐ Overlay가 울리고 있을 수 있으므로 종료 신호 발송
                val dismissIntent = Intent(AlarmOverlayService.ACTION_DISMISS_OVERLAY).apply {
                    setPackage(context.packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                    putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                }
                context.sendBroadcast(dismissIntent)
                Log.d("AlarmAction", "📡 Overlay DISMISS 브로드캐스트 발송")

                cancelAlarm(context, alarmId, label, soundType)

                // Notification 삭제 (8888: 20분전, 8889: 스누즈/타임아웃)
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8888)
                notificationManager.cancel(8889)
            }
            "EXTEND_ALARM" -> {
                Log.d("AlarmAction", "⏰ 알람 5분 연장: ID=$alarmId")

                // ⭐ DB에 알람이 있는지 먼저 확인 (삼성 "알림 다시 표시" 대응)
                if (!isAlarmExistsInDB(context, alarmId)) {
                    Log.d("AlarmAction", "⚠️ DB에 알람 없음 (이미 삭제됨) - notification만 닫기")
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(8888)
                    notificationManager.cancel(8889)
                    return
                }

                val timestamp = intent.getLongExtra("timestamp", 0L)
                val label = intent.getStringExtra(CustomAlarmReceiver.EXTRA_LABEL) ?: "알람"
                val soundType = intent.getStringExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE) ?: "loud"

                // ⭐ Overlay가 울리고 있을 수 있으므로 종료 신호 발송
                val snoozeIntent = Intent(AlarmOverlayService.ACTION_SNOOZE_OVERLAY).apply {
                    setPackage(context.packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                    putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                }
                context.sendBroadcast(snoozeIntent)
                Log.d("AlarmAction", "📡 Overlay SNOOZE 브로드캐스트 발송")

                extendAlarm(context, alarmId, timestamp, label, soundType)
            }
        }
    }
    
    private fun cancelAlarm(context: Context, alarmId: Int, label: String, soundType: String) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    
    val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
        data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
        putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
        putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
        putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
    }
    
    val pendingIntent = PendingIntent.getBroadcast(
        context,
        alarmId,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    alarmManager.cancel(pendingIntent)
    
    Log.d("AlarmAction", "✅ Native 알람 취소 완료: ID=$alarmId")
    
    try {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.writableDatabase
        db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))
        db.close()
        Log.d("AlarmAction", "✅ DB 알람 삭제 완료: ID=$alarmId")

        // ⭐ shownNotifications에서 제거 (다음 알람 Notification 표시 위해)
        AlarmGuardReceiver.removeShownNotification(alarmId)

        // ⭐ 수정: AlarmRefreshWorker → AlarmRefreshUtil
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        Log.d("AlarmAction", "✅ 갱신 체크 완료")

        val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
        context.sendBroadcast(guardIntent)
        Log.d("AlarmAction", "✅ AlarmGuardReceiver 즉시 재실행")
        
    } catch (e: Exception) {
        Log.e("AlarmAction", "❌ DB 삭제 실패", e)
    }
}
    
    private fun extendAlarm(context: Context, alarmId: Int, originalTimestamp: Long, label: String, soundType: String) {
        val newTimestamp = originalTimestamp + (5 * 60 * 1000)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val cancelIntent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(cancelPendingIntent)
        cancelPendingIntent.cancel()
        Log.d("AlarmAction", "✅ 기존 알람 취소: ID=$alarmId")
        
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
            putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
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
                newTimestamp,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                newTimestamp,
                pendingIntent
            )
        }
        
        Log.d("AlarmAction", "✅ 알람 5분 연장 완료: ID=$alarmId, 새 시각=${java.util.Date(newTimestamp)}")
        
        try {
        val dbHelper = DatabaseHelper.getInstance(context)
        val db = dbHelper.writableDatabase
        
        val calendar = java.util.Calendar.getInstance().apply {
            timeInMillis = newTimestamp
        }
        
        val dateStr = java.text.SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss",
            java.util.Locale.getDefault()
        ).format(java.util.Date(newTimestamp))
        
        val timeStr = java.text.SimpleDateFormat(
            "HH:mm",
            java.util.Locale.getDefault()
        ).format(java.util.Date(newTimestamp))
        
        val values = android.content.ContentValues().apply {
            put("date", dateStr)
            put("time", timeStr)
        }
        
        val rowsAffected = db.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))
        db.close()
        
        Log.d("AlarmAction", "✅ DB 업데이트 완료: ID=$alarmId, time=$timeStr, date=$dateStr, rows=$rowsAffected")

        // ⭐ 수정: AlarmRefreshWorker → AlarmRefreshUtil
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        Log.d("AlarmAction", "✅ 갱신 체크 완료")

        // ⭐ shownNotifications에서 제거 (스누즈된 알람도 다시 Notification 표시 위해)
        AlarmGuardReceiver.removeShownNotification(alarmId)

        val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
        context.sendBroadcast(guardIntent)
        Log.d("AlarmAction", "✅ AlarmGuardReceiver 즉시 재실행")

        // ⭐ Notification 업데이트 (NotificationHelper 사용)
        NotificationHelper.showUpdatedNotification(context, timeStr, label)
        Log.d("AlarmAction", "✅ Notification 업데이트 완료")

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        context.startActivity(launchIntent)
        Log.d("AlarmAction", "✅ 앱 포그라운드 이동")

    } catch (e: Exception) {
        Log.e("AlarmAction", "❌ DB 업데이트 실패", e)
    }
    }
    
    // ⭐ DB에 알람이 존재하는지 확인 (삼성 "알림 다시 표시" 대응)
    private fun isAlarmExistsInDB(context: Context, alarmId: Int): Boolean {
        var cursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        return try {
            val dbHelper = DatabaseHelper.getInstance(context)
            db = dbHelper.readableDatabase
            cursor = db.query(
                "alarms",
                arrayOf("id"),
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )
            cursor.count > 0
        } catch (e: Exception) {
            Log.e("AlarmAction", "❌ DB 조회 실패", e)
            false
        } finally {
            cursor?.close()
            db?.close()
        }
    }

    // ⭐ Notification에서 알람 삭제
    private fun deleteAlarmFromDB(context: Context, alarmId: Int) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.writableDatabase
            db.delete("alarms", "id = ?", arrayOf(alarmId.toString()))

            // 이력 업데이트
            val values = android.content.ContentValues().apply {
                put("dismiss_type", "swiped")
            }
            db.update(
                "alarm_history",
                values,
                "alarm_id = ? AND dismiss_type = 'ringing'",
                arrayOf(alarmId.toString())
            )

            db.close()
            Log.d("AlarmAction", "✅ DB 알람 삭제 완료")

            AlarmGuardReceiver.removeShownNotification(alarmId)
            AlarmRefreshUtil.checkAndTriggerRefresh(context)

            val guardIntent = Intent(context, AlarmGuardReceiver::class.java)
            context.sendBroadcast(guardIntent)

        } catch (e: Exception) {
            Log.e("AlarmAction", "❌ DB 삭제 실패", e)
        }
    }

    // ⭐ Notification에서 5분 후
    private fun snoozeAlarmFromDB(context: Context, alarmId: Int) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase

            val cursor = db.query(
                "alarms",
                null,
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            if (cursor.moveToFirst()) {
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                cursor.close()

                val newTimestamp = System.currentTimeMillis() + (5 * 60 * 1000)

                // 기존 알람 취소
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val cancelIntent = Intent(context, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                }
                val cancelPendingIntent = PendingIntent.getBroadcast(
                    context,
                    alarmId,
                    cancelIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(cancelPendingIntent)
                cancelPendingIntent.cancel()

                // 새 알람 등록
                val newIntent = Intent(context, CustomAlarmReceiver::class.java).apply {
                    data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
                    putExtra(CustomAlarmReceiver.EXTRA_ID, alarmId)
                    putExtra(CustomAlarmReceiver.EXTRA_LABEL, shiftType)
                    putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
                }

                val newPendingIntent = PendingIntent.getBroadcast(
                    context,
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

                // DB 업데이트
                val writableDb = dbHelper.writableDatabase
                val dateStr = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(newTimestamp))
                val timeStr = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(newTimestamp))

                val values = android.content.ContentValues().apply {
                    put("date", dateStr)
                    put("time", timeStr)
                }
                writableDb.update("alarms", values, "id = ?", arrayOf(alarmId.toString()))

                // 이력 업데이트
                writableDb.execSQL(
                    "UPDATE alarm_history SET dismiss_type = 'snoozed', snooze_count = snooze_count + 1 WHERE alarm_id = ? AND dismiss_type = 'ringing'",
                    arrayOf(alarmId)
                )

                writableDb.close()
                Log.d("AlarmAction", "✅ 5분 후 재등록 완료")

                AlarmGuardReceiver.removeShownNotification(alarmId)
                AlarmRefreshUtil.checkAndTriggerRefresh(context)
                NotificationHelper.showUpdatedNotification(context, timeStr, shiftType)

            } else {
                cursor.close()
                Log.e("AlarmAction", "❌ 알람 정보 없음")
            }

            db.close()

        } catch (e: Exception) {
            Log.e("AlarmAction", "❌ 5분 후 재등록 실패", e)
        }
    }
}