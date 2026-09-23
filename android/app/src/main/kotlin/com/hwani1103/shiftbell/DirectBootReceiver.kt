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
        val action = intent.action
        DiagLog.log(context, "SYSTEM_EVENT", "action" to action?.substringAfterLast('.'))
        // ⭐ 2026-09-14 (출시전 감사 V6, G1) - 예전엔 LOCKED_BOOT_COMPLETED만 처리했음:
        //  - BOOT_COMPLETED: LOCKED_BOOT가 안 오는 기기/경로(파일 기반 암호화 없음 등)에서 재부팅 후 재예약이 빠질 수 있음
        //  - MY_PACKAGE_REPLACED: 업데이트 직후 앱을 열기 전까지 새 정책(#26 등)으로 갱신·재예약이 안 됨
        //  - 정확한 알람 권한 재허용: 거부 동안 실패한 예약(#13·#27 실패 목록)을 다음 트리거까지 방치
        // Manifest intent-filter 추가는 통합 담당자 요청(g1/integration_requests.md) - 이 코드는 수신만 되면 동작.
        if (action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) {
            resyncAfterEnvironmentChange(context, action)
            return
        }
        if (action != Intent.ACTION_LOCKED_BOOT_COMPLETED && action != Intent.ACTION_BOOT_COMPLETED) {
            Log.d("DirectBoot", "⏭️ 다른 액션: $action")
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

            // ⭐ 4단계: 실제 수면 기록/자동 추정("C번 요구사항") 재예약. AlarmManager
            // 알람은 재부팅하면 전부 사라지므로 이것도 반드시 다시 걸어야 함 - 알람
            // 시스템 재등록과 완전히 독립된 별도 알람이라 위 단계들에 영향 없음.
            // 2026-09-01 - checkNow로 바꿔 재부팅 직후에도 진행 중 후보가 있으면 즉시 판정.
            SleepDetectionReceiver.checkNow(context)

            // ⭐ 5단계: 일정관리 탭 "일정에 맞춰서 알림받기" 재예약(2026-09-12 신설).
            // 이 알림도 AlarmManager 기반이라 재부팅하면 전부 사라짐 - date_schedules에
            // notify_enabled=1로 남아있는 미래 일정들을 다시 걺. 위 알람/수면감지
            // 재등록과 완전히 독립된 별도 스윕이라 서로 영향 없음.
            ScheduleNotificationScheduler.rescheduleAllFromDb(context)

            Log.e("DirectBoot", "========== DIRECT BOOT COMPLETE ==========")
        } catch (e: Exception) {
            Log.e("DirectBoot", "========== ERROR ==========", e)
        }
    }
    
    // ⭐ V6 - 업데이트·정확한 알람 권한 재허용: 부팅 시각은 그대로 두고 알람·일정 알림만 즉시 다시 맞춤.
    // 엔진 갱신은 "오늘 이미 갱신함"과 무관하게 실행되고(refresh 직접 호출), 시작 시 OS 반영 실패 목록부터 재시도함.
    private fun resyncAfterEnvironmentChange(context: Context, action: String) {
        if (action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.d("DirectBoot", "⏭️ 정확한 알람 권한 상태 변경(허용 아님) - 재조정 안 함")
                return
            }
        }
        Log.e("DirectBoot", "🔄 $action - 알람·일정 알림 재조정")
        try {
            AlarmRefreshEngine.refresh(context)
            AlarmGuardReceiver.triggerCheck(context)
            ScheduleNotificationScheduler.rescheduleAllFromDb(context)
        } catch (e: Exception) {
            Log.e("DirectBoot", "❌ 재조정 실패: $action", e)
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
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 (DatabaseHelper.kt 상세 주석 참고).
            db = dbHelper.getReadableDatabaseWithRetry() ?: return null

            val now = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss",
                Locale.US
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
                    Locale.US
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
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고)
            cursor?.close()
        }
    }
    
    // ⭐ 2026-09-14 (출시전 감사 #27/#20) - 예전엔 여기만 Intent에 setPackage()를 넣어서 다른 예약 경로와 PendingIntent가
    // 달라졌음 → 재부팅 후 같은 알람이 두 번 예약·수신됐고(0.47초 간격, g1/handoff.md) 엔진의 취소도 이 예약을 못 지웠음.
    // AlarmWakeScheduler로 통일(같은 Intent·setAlarmClock·예정 시각 extra, 옛 변형 예약도 함께 제거).
    private fun scheduleNativeAlarm(
        context: Context,
        id: Int,
        timestamp: Long,
        label: String
    ) {
        try {
            AlarmWakeScheduler.scheduleRaw(context, id, timestamp, label)
            Log.d("DirectBoot", "✅ Native 알람 등록: ID=$id, timestamp=$timestamp")
        } catch (e: Exception) {
            AlarmWakeScheduler.recordFailure(context, id)
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