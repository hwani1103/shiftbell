// android/app/src/main/kotlin/com/hwani1103/shiftbell/ScheduleNotificationScheduler.kt
//
// ⭐ 2026-09-12 - 일정관리 탭 "일정에 맞춰서 알림받기" 실제 구현
// (전체근무표_개선안_및_일정알림_설계메모.md 2장). date_schedules(DB v23)
// notify_enabled/notify_offset_minutes 컬럼 기준으로 AlarmManager에 정확한
// 1회성 알림을 예약/취소한다.
//
// 기존 알람(scheduleNativeAlarm/CustomAlarmReceiver - 잠금화면/벨소리/스누즈)과
// 완전히 별개 - 이 파일은 그 어떤 기존 알람 로직도 건드리지 않는다.
//
// schedule()/cancel()은 MainActivity의 MethodChannel 핸들러(Dart가 일정을
// 만들거나 수정/삭제할 때마다 호출 - date_schedule_provider.dart 참고)가 부른다.
// rescheduleAllFromDb()는 DirectBootReceiver가 재부팅 직후에 부른다 - AlarmManager
// 알람은 재부팅하면 전부 사라지므로, DB에 notify_enabled=1로 남아있는 미래
// 일정들을 다시 걸어줘야 함(기존 알람/수면감지 재부팅 재예약과 동일한 이유).
package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

object ScheduleNotificationScheduler {

    private const val TAG = "ScheduleNotify"

    // ⭐ CustomAlarmReceiver가 알람 id를 notify(id + 100000)으로 쓰고 있어서
    // (NotificationHelper.kt 8888/8889까지 포함해도 여유 있게), 이 신규 기능은
    // 완전히 다른 대역(+300000)을 씀 - AlarmManager 요청 코드/Notification ID
    // 둘 다 이 오프셋을 그대로 재사용(PendingIntent는 Intent의 data Uri도 서로
    // 다르게 줘서 이중으로 충돌을 막음 - 아래 buildPendingIntent 참고). private가
    // 아닌 이유 - ScheduleNotificationReceiver가 실제 notify()에도 똑같은 ID를
    // 써야 cancel()의 notificationManager.cancel(id + REQUEST_CODE_OFFSET)이
    // 정확히 그 알림을 지울 수 있음.
    const val REQUEST_CODE_OFFSET = 300000

    // ⭐ 2026-09-14 (출시전 감사 #5, G1) - 예약 당시 트리거 시각(ms). 수신 시 DB 기준으로 다시 계산한 시각과 정확히 비교.
    const val EXTRA_EXPECTED_AT = "schedule_expected_at"

    // ⭐ #5 - 일정관리 탭 사용 여부를 Device Protected alarm_state에도 둠. Flutter 설정(schedule_tab_enabled)은 잠금 해제
    // 전에는 읽을 수 없어서, 탭을 숨긴 뒤 재부팅하면 DirectBootReceiver가 일정 알림을 전부 되살렸음.
    // 쓰는 곳: MainActivity(탭 숨김·복원 채널, 앱 시작 동기화 syncScheduleTabEnabled). 기본값 true(기존 사용자 동작 유지).
    private const val PREFS_NAME = "alarm_state"
    internal const val KEY_TAB_ENABLED = "schedule_tab_enabled"

    private fun prefs(context: Context) = (
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
    ).getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isTabEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_TAB_ENABLED, true)

    fun setTabEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_TAB_ENABLED, enabled).commit()
    }

    /** 앱 시작 시 Flutter 값과 맞춤 - 값이 바뀐 경우에만 예약을 거두거나 되살림. */
    fun syncTabEnabled(context: Context, enabled: Boolean) {
        val previous = isTabEnabled(context)
        setTabEnabled(context, enabled)
        if (previous == enabled) return
        if (enabled) rescheduleAllFromDb(context) else cancelAllFromDb(context)
    }

    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        date: String,
        startMinutes: Int,
        content: String,
        durationMinutes: Int = 0
    ): Boolean {
        if (!isTabEnabled(context)) {
            // #5 - 탭을 숨긴 상태에선 새로 걸지 않음(탭 복원 시 rescheduleAllFromDb가 DB 기준으로 다시 검)
            Log.d(TAG, "⏭️ 일정관리 탭 숨김 - 일정 알림 예약 안 함: id=$id")
            return true
        }
        // ⭐ 2026-09-14 (출시전 감사 #13) - 예약 성공 여부를 돌려줌. 예전엔 실패를 로그로만 삼켜서
        // Dart(일정 저장 화면)가 성공으로 알고 아무 안내도 안 했음.
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = buildPendingIntent(context, id, date, startMinutes, content, durationMinutes, triggerAtMillis)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
            Log.d(TAG, "✅ 일정 알림 예약: id=$id trigger=$triggerAtMillis")
            return true
        } catch (e: Exception) {
            // ⭐ 정확한 알람 권한(SCHEDULE_EXACT_ALARM)이 꺼져 있는 등의 사유로
            // SecurityException이 날 수 있음 - 이 알림 하나를 못 건 것뿐이라
            // 기존 알람 시스템 전체에는 영향 없이 조용히 로그만 남김.
            Log.e(TAG, "❌ 일정 알림 예약 실패: id=$id", e)
            return false
        }
    }

    fun cancel(context: Context, id: Int) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // ⭐ 취소만 할 때는 실제 알림 문구(date/startMinutes/content)가 중요하지
            // 않음 - PendingIntent 매칭은 requestCode + data Uri만 보므로 더미 값으로
            // 충분함(FLAG_UPDATE_CURRENT라 값이 달라도 같은 PendingIntent로 인식됨).
            val pendingIntent = buildPendingIntent(context, id, "", 0, "", 0, 0L)
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()

            // ⭐ 이미 화면에 떠 있는 알림도 같이 지움(예: 일정 삭제 시점에 마침
            // 알림이 이미 표시된 직후인 경우) - 위생 차원, 없어도 다음 알림에
            // 영향 없음(notify()가 매번 새로 그리므로).
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            notificationManager.cancel(id + REQUEST_CODE_OFFSET)
            Log.d(TAG, "🗑️ 일정 알림 취소: id=$id")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 일정 알림 취소 실패: id=$id", e)
        }
    }

    // ⭐ 재부팅 직후(DirectBootReceiver) 전용 - date_schedules를 Native가 직접
    // 읽어서, notify_enabled=1이면서 트리거 시각이 아직 미래인 것만 다시 건다.
    // 이미 지난 시각은 조용히 스킵(Dart의 syncForSchedule과 같은 원칙 -
    // schedule_notification_service.dart 상단 주석 참고, "지난 일정은 예약하지
    // 않는다"). Native가 date_schedules를 읽는 건 이번이 처음(DB_스키마_변경_
    // 가이드.md v23 항목 참고) - 이 함수 하나가 유일한 진입점.
    fun rescheduleAllFromDb(context: Context, ownerToken: String? = null) {
        // ⭐ G4 #19 - 복원 중엔 재예약하지 않음(복원 owner가 복원된 탭 설정으로 마지막에 다시 부름)
        if (RestoreGate.shouldDefer(context, "scheduleReschedule", ownerToken)) return
        // ⭐ 2026-09-14 (#5) - 탭을 숨긴 상태면 되살리지 않고 오히려 남아 있을 수 있는 예약을 거둠
        if (!isTabEnabled(context)) {
            Log.d(TAG, "⏭️ 일정관리 탭 숨김 - 재예약 대신 일괄 취소")
            cancelAllFromDb(context)
            return
        }
        var cursor: android.database.Cursor? = null
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            // ⭐ DB 파일이 아직 없거나 버전이 안 맞으면 null - Native가 함부로
            // 만들거나 건드리면 안 됨(DatabaseHelper.kt 상단 주석 참고). 이 경우
            // 그냥 스킵 - 다음에 앱이 열려서 Dart가 다시 만들 때 자연히 정상화됨.
            val db = dbHelper.getReadableDatabaseWithRetry() ?: run {
                Log.d(TAG, "⏭️ DB 준비 안 됨 - 일정 알림 재예약 스킵")
                return
            }

            cursor = db.query(
                "date_schedules",
                arrayOf("id", "date", "start_minutes", "notify_offset_minutes", "content", "duration_minutes"),
                "notify_enabled = 1",
                null, null, null, null
            )

            val now = System.currentTimeMillis()
            var count = 0
            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                val date = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                val startMinutes = cursor.getInt(cursor.getColumnIndexOrThrow("start_minutes"))
                val offsetMinutes = cursor.getInt(cursor.getColumnIndexOrThrow("notify_offset_minutes"))
                val content = cursor.getString(cursor.getColumnIndexOrThrow("content")) ?: ""
                // ⭐ duration_minutes는 v20부터 있던 컬럼(0=지속시간 미정 sentinel,
                // date_schedule.dart의 DateSchedule.toMap() 참고) - 구버전 DB엔
                // 없을 수 있어 dayOffset과 동일하게 -1 체크.
                val durationIdx = cursor.getColumnIndex("duration_minutes")
                val durationMinutes = if (durationIdx >= 0) cursor.getInt(durationIdx) else 0

                val triggerAtMillis = triggerMillisFor(date, startMinutes, offsetMinutes) ?: continue
                if (triggerAtMillis <= now) {
                    // ⭐ 2026-09-14 (출시전 감사 #10) - 지난 일정은 건너뛰기 "전에" 예약을 지움. 시간대·시계 변경으로 이
                    // 함수가 다시 불렸을 때, 옛 절대 시각으로 걸려 있던 예약이 남아 엉뚱한 때 울리지 않게.
                    // 이미 화면에 떠 있는 알림은 지우지 않음(사용자가 아직 못 봤을 수 있음).
                    cancelAlarmOnly(context, id)
                    continue
                }

                schedule(context, id, triggerAtMillis, date, startMinutes, content, durationMinutes)
                count++
            }
            Log.d(TAG, "✅ 재부팅 후 일정 알림 재예약 완료: ${count}건")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 일정 알림 재예약 실패", e)
        } finally {
            cursor?.close()
        }
    }

    // ⭐ 2026-09-13 - "일정관리 화면 사용하지 않기"(탭 숨기기) 전용. 탭을 숨기면
    // 그 화면으로 돌아갈 방법이 없어지는데, 일정 알림을 탭하면 억지로 그 탭을
    // 다시 열게 되는 모순이 생김(main.dart의 숨김탭 안전망이 즉시 다른 탭으로
    // 튕겨버려 알림을 눌러도 아무 일도 안 일어나는 것처럼 보임) - 그래서 탭을
    // 숨기는 시점에 그 진입 경로 자체(예약된 알림 + 이미 떠 있는 알림)를 전부
    // 없앤다. DB의 notify_enabled 값 자체는 안 건드림(단순 일시중지) - 탭을
    // 다시 켜면 rescheduleAllFromDb()를 그대로 재사용해 원래 상태로 완전히
    // 복원함(재부팅 재예약과 동일한 함수를 재사용하는 이유 - 이미 검증된
    // "DB의 notify_enabled=1 전체를 다시 건다" 로직을 그대로 믿을 수 있음).
    fun cancelAllFromDb(context: Context) {
        var cursor: android.database.Cursor? = null
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.getReadableDatabaseWithRetry() ?: run {
                Log.d(TAG, "⏭️ DB 준비 안 됨 - 일정 알림 일괄 취소 스킵")
                return
            }
            cursor = db.query(
                "date_schedules", arrayOf("id"), "notify_enabled = 1",
                null, null, null, null
            )
            var count = 0
            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                cancel(context, id) // 예약 취소 + 이미 뜬 알림 dismiss까지 한 번에
                count++
            }
            Log.d(TAG, "✅ 일정관리 탭 숨김 - 일정 알림 일괄 취소 완료: ${count}건")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 일정 알림 일괄 취소 실패", e)
        } finally {
            cursor?.close()
        }
    }

    /** 예약만 취소(이미 표시된 알림은 그대로). */
    private fun cancelAlarmOnly(context: Context, id: Int) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = buildPendingIntent(context, id, "", 0, "", 0, 0L)
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "❌ 지난 일정 예약 취소 실패: id=$id", e)
        }
    }

    internal data class ScheduleDisplay(
        val id: Int,
        val date: String,
        val startMinutes: Int,
        val content: String,
        val durationMinutes: Int
    )

    /**
     * ⭐ 2026-09-14 (출시전 감사 #5) - 수신 시 표시 여부를 DB로 다시 판정. 표시할 내용(DB 기준) 또는 null.
     * 표시 조건: 탭 사용 중 + 행 존재 + notify_enabled = 1 + DB로 다시 계산한 트리거 시각 == 예약 당시 시각(허용 오차 없음).
     * 시각이 다르면 표시하지 않고, DB 시각이 미래면 그 시각으로 다시 예약(같은 ID 일정의 시각을 바꿨는데 옛 예약이 남은 경우).
     * 예약 당시 시각이 없는 이 수정 이전 예약은 정확히 대조할 수 없으므로 표시하지 않음. DB 시각이 미래면 재예약.
     * DB를 못 열면 확인할 수 없으므로 표시하지 않음(가벼운 일정 알림이라 기상 알람과 달리 fail-closed).
     */
    internal fun resolveOnReceive(context: Context, id: Int, expectedAtMillis: Long?): ScheduleDisplay? {
        if (!isTabEnabled(context)) {
            Log.d(TAG, "⏭️ 일정관리 탭 숨김 - 일정 알림 표시 안 함: id=$id")
            return null
        }
        val db = try {
            DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
        } catch (e: Exception) {
            Log.e(TAG, "수신 판정 DB 열기 실패: id=$id", e)
            null
        } ?: return null
        db.query(
            "date_schedules",
            arrayOf("date", "start_minutes", "notify_offset_minutes", "content", "duration_minutes", "notify_enabled"),
            "id = ?", arrayOf(id.toString()), null, null, null
        ).use { c ->
            if (!c.moveToFirst()) {
                Log.d(TAG, "⏭️ 삭제된 일정의 알림 - 표시 안 함: id=$id")
                return null
            }
            if (c.getInt(5) != 1) {
                Log.d(TAG, "⏭️ 알림이 꺼진 일정 - 표시 안 함: id=$id")
                return null
            }
            val date = c.getString(0)
            val startMinutes = c.getInt(1)
            val durationMinutes = if (c.isNull(4)) 0 else c.getInt(4)
            val content = c.getString(3) ?: ""
            val trigger = triggerMillisFor(date, startMinutes, c.getInt(2)) ?: return null
            val now = System.currentTimeMillis()
            val matches = expectedAtMillis != null && trigger == expectedAtMillis
            if (!matches) {
                if (trigger > now) {
                    Log.w(TAG, "⚠️ 옛 시각 예약 도착 - 표시 안 하고 DB 시각으로 재예약: id=$id")
                    schedule(context, id, trigger, date, startMinutes, content, durationMinutes)
                } else {
                    Log.w(TAG, "⚠️ 예약 시각과 DB 시각 불일치(DB 시각은 지남) - 표시 안 함: id=$id")
                }
                return null
            }
            return ScheduleDisplay(id, date, startMinutes, content, durationMinutes)
        }
    }

    // ⭐ Dart schedule_notification_service.dart의 _triggerDateTime()과 반드시
    // 같은 계산이어야 함(그 파일 상단 주석 참고) - date('YYYY-MM-DD') 자정 +
    // startMinutes - offsetMinutes, 전부 기기 로컬 타임존 기준.
    // ⭐ 2026-09-12 - 원래 private였으나, 테스트_계획_2026-09-12.md B-2 대상으로
    // Robolectric 유닛테스트(ScheduleNotificationSchedulerTest.kt)가 날짜/시각
    // 경계값(자정, 22시대 등)을 직접 assert할 수 있어야 해서 internal로 넓힘 -
    // 외부 공개 API가 늘어난 건 아님(모듈 내부에서만 보임), 동작 변경 없음.
    internal fun triggerMillisFor(date: String, startMinutes: Int, offsetMinutes: Int): Long? {
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val base = sdf.parse(date) ?: return null
            val cal = Calendar.getInstance()
            cal.time = base
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            cal.add(Calendar.MINUTE, startMinutes - offsetMinutes)
            cal.timeInMillis
        } catch (e: Exception) {
            Log.e(TAG, "❌ 트리거 시각 계산 실패: date=$date", e)
            null
        }
    }

    private fun buildPendingIntent(
        context: Context,
        id: Int,
        date: String,
        startMinutes: Int,
        content: String,
        durationMinutes: Int,
        triggerAtMillis: Long
    ): PendingIntent {
        val intent = Intent(context, ScheduleNotificationReceiver::class.java).apply {
            // ⭐ id별로 항상 다른 data Uri - CustomAlarmReceiver의 "shiftbell://alarm/$id"와
            // 같은 이유(PendingIntent 충돌 방지, 요청 코드가 우연히 겹쳐도 안전).
            data = Uri.parse("shiftbell://schedule_notify/$id")
            putExtra(ScheduleNotificationReceiver.EXTRA_ID, id)
            putExtra(ScheduleNotificationReceiver.EXTRA_DATE, date)
            putExtra(ScheduleNotificationReceiver.EXTRA_START_MINUTES, startMinutes)
            putExtra(ScheduleNotificationReceiver.EXTRA_CONTENT, content)
            putExtra(ScheduleNotificationReceiver.EXTRA_DURATION_MINUTES, durationMinutes)
            putExtra(EXTRA_EXPECTED_AT, triggerAtMillis)
        }
        return PendingIntent.getBroadcast(
            context,
            id + REQUEST_CODE_OFFSET,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
