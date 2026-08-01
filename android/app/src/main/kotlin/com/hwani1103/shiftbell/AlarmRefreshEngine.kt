package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

/**
 * ⭐ 알람 자동 갱신의 유일한 실행 주체 (single owner)
 *
 * 예전 문제: Dart(AlarmRefreshService)와 Kotlin(AlarmRefreshReceiver)이 각자 독립적으로
 * "전체 삭제 → 10일치 재생성"을 수행했고, "오늘 이미 갱신했는지" 플래그도 서로 다른 저장소에
 * 따로 관리해서 하루가 바뀐 직후 둘 다 "갱신 필요"라고 판단 → 거의 동시에 두 번 실행되며
 * 알람이 사라지는 race condition이 있었음.
 *
 * 지금은 이 객체가 유일하게 alarms(type='fixed') 테이블을 변경함:
 *  - Dart는 더 이상 자체적으로 삭제/재생성하지 않고 이 엔진을 트리거만 함
 *  - 전체 삭제 후 재생성이 아니라 "있어야 할 것 vs 지금 있는 것"을 diff해서
 *    바뀐 것만 건드림 → 스누즈 중인 알람(type='snoozed')은애초에 대상이 아니고,
 *    바뀌지 않은 미래 알람은 취소/재등록 자체를 안 하니 원자성 문제도 크게 줄어듦.
 *  - 전체 작업(diff 적용)은 하나의 SQLite 트랜잭션으로 묶여서, 중간에 실패하면
 *    아무 것도 안 바뀐 것처럼 롤백됨 (삭제만 되고 생성은 안 되는 상태 방지).
 *  - RefreshLockManager로 같은 시점에 여러 트리거(자정/20분전/알람울림/앱재개)가
 *    겹쳐도 한 번만 실제로 수행되게 막음.
 */
object AlarmRefreshEngine {
    private const val TAG = "AlarmRefreshEngine"
    private const val DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"
    private const val DAYS_AHEAD = 10

    private data class ScheduleData(
        val isRegular: Boolean,
        val pattern: List<String>,
        val todayIndex: Int,
        val startDateMillis: Long,
        val assignedDates: Map<String, String>
    )

    private data class DesiredAlarm(
        val dateStr: String,
        val time: String,
        val shiftType: String,
        val alarmTypeId: Int,
        val timestamp: Long
    ) {
        // ⭐ CRITICAL FIX: 날짜 "문자열"이 아니라 실제 시각(timestamp)으로 매칭해야 함.
        // Dart 쪽(onboarding/달력 팝업/설정)은 DateTime.toIso8601String()으로 date를 저장하는데
        // 이건 밀리초까지 포함해서 "...T10:00:00.000" 형태로 남음. Kotlin 엔진이 새로 계산하는
        // 문자열은 밀리초가 없는 "...T10:00:00" 형태라, 문자열로 비교하면 Dart에서 만든 알람은
        // 절대 일치하지 않아서 매번 "다른 알람"으로 오인되어 전부 삭제 후 재생성되고
        // (이력엔 전부 superseded로 찍힘) 재부팅 등으로 엔진이 한 번 돌 때마다 반복됐음.
        fun key() = "$timestamp|$shiftType|$alarmTypeId"
    }

    private data class ExistingAlarm(
        val id: Int,
        val dateStr: String,
        val time: String,
        val shiftType: String,
        val alarmTypeId: Int,
        val timestamp: Long
    ) {
        fun key() = "$timestamp|$shiftType|$alarmTypeId"
    }

    fun refresh(context: Context) {
        // ⭐ owner를 호출마다 고유하게(UUID) 생성해야 함. 예전엔 "AlarmRefreshEngine"
        // 고정 문자열을 owner로 썼는데, RefreshLockManager.tryAcquire의 거부 조건이
        // "currentOwner != owner"라서 이 함수의 모든 호출이 항상 같은 owner를 쓰면
        // 절대 서로를 다른 소유자로 인식 못 해 락이 사실상 아무 것도 막지 못했음
        // (동시에 두 번 호출돼도 둘 다 그냥 통과 → 서로 다른 스냅샷으로 diff 계산 가능).
        val owner = "AlarmRefreshEngine-${UUID.randomUUID()}"
        if (!RefreshLockManager.tryAcquire(context, owner)) {
            Log.d(TAG, "⏭️ 다른 프로세스가 갱신 중 - 스킵")
            return
        }
        try {
            doRefresh(context)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 갱신 실패", e)
        } finally {
            RefreshLockManager.release(context, owner)
        }
    }

    private fun doRefresh(context: Context) {
        val dbHelper = DatabaseHelper.getInstance(context)
        // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 (DatabaseHelper.kt 상세 주석 참고) -
        // 이 시점엔 스케줄도 없는 게 정상이라 "스케줄 없음"과 동일하게 처리.
        val db = dbHelper.getWritableDatabaseWithRetry()
        if (db == null) {
            Log.d(TAG, "⚠️ DB 파일 없음 - 갱신 중단")
            return
        }

        try {
            val schedule = readSchedule(db)
            if (schedule == null) {
                Log.d(TAG, "⚠️ 스케줄 없음 - 갱신 중단")
                return
            }

            if (!schedule.isRegular) {
                Log.d(TAG, "⏭️ 불규칙 스케줄 - 기존 알람 재등록만 수행")
                reRegisterExistingAlarms(context, db)
                markRefreshed(context)
                notifyFlutter(context)
                return
            }

            val templates = readTemplates(db)
            if (templates.isEmpty()) {
                Log.d(TAG, "⚠️ 템플릿 없음 - 갱신 중단")
                return
            }

            val desired = computeDesiredAlarms(schedule, templates)
            val existing = readExistingFixedAlarms(db)
            val existingByKey = existing.associateBy { it.key() }
            val desiredKeys = desired.map { it.key() }.toSet()

            val toAdd = desired.filter { it.key() !in existingByKey.keys }
            val toRemove = existing.filter { it.key() !in desiredKeys }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            db.beginTransaction()
            try {
                for (item in toRemove) {
                    cancelNativeAlarm(context, alarmManager, item.id)
                    insertHistory(db, item.id, item.dateStr, item.time, item.shiftType, "superseded")
                    db.delete("alarms", "id = ?", arrayOf(item.id.toString()))
                }

                for (item in toAdd) {
                    val values = ContentValues().apply {
                        put("time", item.time)
                        put("date", item.dateStr)
                        put("type", "fixed")
                        put("alarm_type_id", item.alarmTypeId)
                        put("shift_type", item.shiftType)
                    }
                    val rowId = db.insert("alarms", null, values)
                    if (rowId == -1L || rowId > Int.MAX_VALUE) {
                        Log.e(TAG, "❌ DB 삽입 실패/오버플로우: $item")
                        continue
                    }
                    val alarmId = rowId.toInt()
                    insertCreationLog(db, alarmId, item.dateStr, item.time, item.shiftType, item.alarmTypeId, "auto")
                    scheduleNativeAlarm(context, alarmManager, alarmId, item.timestamp, item.shiftType)
                }

                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }

            // ⭐ CRITICAL: diff에서 "안 바뀐" 알람도 OS AlarmManager에 반드시 다시 등록함.
            // DB row가 그대로라고 해서 OS 알람도 여전히 살아있다는 보장이 없음 —
            // 재부팅하면 DB는 그대로인데 AlarmManager 등록은 전부 날아감. 예전 "전체 삭제 후
            // 재생성" 방식은 매번 전부 다시 등록했기 때문에 이 문제가 가려져 있었는데,
            // diff 방식으로 바꾸면서 "새로 추가된 것만" 등록하면 재부팅 후 아직 refresh가
            // 안 도는 알람들이 DB엔 있지만 실제로는 안 울리는 유령이 될 수 있었음.
            // AlarmManager 등록 자체는 DB를 안 건드리는 가벼운 작업이라 매번 다시 걸어도 무해함.
            var rearmedCount = 0
            var rearmFailures = 0
            for (item in desired) {
                val existingId = existingByKey[item.key()]?.id ?: continue  // toAdd는 위에서 이미 등록함
                try {
                    scheduleNativeAlarm(context, alarmManager, existingId, item.timestamp, item.shiftType)
                    rearmedCount++
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 기존 알람 재등록 실패: id=$existingId", e)
                    rearmFailures++
                }
            }

            // ⭐ 재등록이 하나라도 실패했으면 "오늘 갱신 완료"로 표시하지 않음.
            // markRefreshed()를 무조건 호출하면, 권한이 일시적으로 막혀서 재등록이
            // 전부 실패해도 "오늘은 이미 갱신함" 플래그가 찍혀서 dateChanged 기반
            // 재시도가 다음 날까지(최대 24시간) 막혀버림 - 그동안 실제로는 OS에
            // 재등록 안 된 알람이 방치됨. 실패가 있으면 플래그를 남기지 않아서
            // 다음 트리거(20분 뒤, 알람 울림, 앱 실행 등) 때 바로 재시도되게 함.
            if (rearmFailures == 0) {
                markRefreshed(context)
            } else {
                Log.e(TAG, "⚠️ 재등록 실패 ${rearmFailures}건 - '오늘 갱신 완료' 표시 안 함 (다음 트리거에 재시도)")
            }
            notifyFlutter(context)

            Log.d(TAG, "✅ diff 갱신 완료: +${toAdd.size} -${toRemove.size} 재등록=$rearmedCount")
        } finally {
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고)
        }
    }

    private fun readSchedule(db: SQLiteDatabase): ScheduleData? {
        db.query("shift_schedule", null, null, null, null, null, null, "1").use { cursor ->
            if (!cursor.moveToFirst()) return null

            val isRegular = cursor.getInt(cursor.getColumnIndexOrThrow("is_regular")) == 1
            val patternStr = cursor.getString(cursor.getColumnIndexOrThrow("pattern"))
            val todayIndex = cursor.getInt(cursor.getColumnIndexOrThrow("today_index"))
            val startDateStr = cursor.getString(cursor.getColumnIndexOrThrow("start_date"))
            val assignedDatesStr = cursor.getString(cursor.getColumnIndexOrThrow("assigned_dates"))

            if (!isRegular) {
                return ScheduleData(false, emptyList(), 0, 0L, parseAssignedDates(assignedDatesStr))
            }

            if (patternStr.isNullOrEmpty() || startDateStr.isNullOrEmpty()) {
                Log.d(TAG, "⚠️ Pattern/startDate null/empty - 불규칙 스케줄로 간주")
                return ScheduleData(false, emptyList(), 0, 0L, parseAssignedDates(assignedDatesStr))
            }

            val parsedStart = try {
                SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).parse(startDateStr)
            } catch (e: Exception) {
                Log.e(TAG, "❌ startDate 파싱 실패: $startDateStr", e)
                return null
            } ?: return null

            val startCal = Calendar.getInstance().apply {
                time = parsedStart
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            return ScheduleData(
                isRegular = true,
                pattern = patternStr.split(","),
                todayIndex = todayIndex,
                startDateMillis = startCal.timeInMillis,
                assignedDates = parseAssignedDates(assignedDatesStr)
            )
        }
    }

    // ⭐ 달력 팝업에서 날짜별로 수동 지정한 예외(휴무 등)를 반영 (기존엔 Native 갱신이 이걸 무시했음)
    private fun parseAssignedDates(json: String?): Map<String, String> {
        if (json.isNullOrEmpty()) return emptyMap()
        return try {
            val obj = JSONObject(json)
            val map = mutableMapOf<String, String>()
            obj.keys().forEach { key -> map[key] = obj.getString(key) }
            map
        } catch (e: Exception) {
            Log.e(TAG, "❌ assignedDates 파싱 실패", e)
            emptyMap()
        }
    }

    private fun readTemplates(db: SQLiteDatabase): Map<String, List<Pair<String, Int>>> {
        val templates = mutableMapOf<String, MutableList<Pair<String, Int>>>()
        db.query("shift_alarm_templates", null, null, null, null, null, null).use { cursor ->
            while (cursor.moveToNext()) {
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type"))
                val time = cursor.getString(cursor.getColumnIndexOrThrow("time"))
                val alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id"))
                templates.getOrPut(shiftType) { mutableListOf() }.add(Pair(time, alarmTypeId))
            }
        }
        return templates
    }

    private fun readExistingFixedAlarms(db: SQLiteDatabase): List<ExistingAlarm> {
        val result = mutableListOf<ExistingAlarm>()
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        db.query("alarms", null, "type = ? AND date > ?", arrayOf("fixed", now), null, null, null).use { cursor ->
            while (cursor.moveToNext()) {
                val dateStr = cursor.getString(cursor.getColumnIndexOrThrow("date")) ?: continue
                val timestamp = parseStoredDate(dateStr) ?: continue
                result.add(
                    ExistingAlarm(
                        id = cursor.getInt(cursor.getColumnIndexOrThrow("id")),
                        dateStr = dateStr,
                        time = cursor.getString(cursor.getColumnIndexOrThrow("time")) ?: continue,
                        shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "",
                        alarmTypeId = cursor.getInt(cursor.getColumnIndexOrThrow("alarm_type_id")),
                        timestamp = timestamp
                    )
                )
            }
        }
        return result
    }

    // ⭐ 순수 연/월/일만으로 계산하는 Julian Day Number - 시간대/서머타임과 완전히
    // 무관해서, 두 날짜 사이의 "진짜 날짜 수 차이"를 항상 정확히 구할 수 있음
    // (밀리초 차이를 24시간으로 나누는 방식은 DST가 있는 지역에서 하루가 23/25시간인
    // 날을 지나면 틀어짐). Calendar.MONTH는 0-based라 +1 필요.
    private fun julianDayNumber(cal: Calendar): Int {
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val day = cal.get(Calendar.DAY_OF_MONTH)
        val a = (14 - month) / 12
        val y = year + 4800 - a
        val m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    // ⭐ Dart(밀리초 포함 "...T10:00:00.000")와 Kotlin(밀리초 없음 "...T10:00:00") 두 형식을
    // 전부 허용해서 파싱함. SimpleDateFormat.parse()는 패턴과 일치하는 접두부만 읽고 뒤에
    // 남는 문자(.000)는 무시하므로 하나의 포맷터로 두 형식 다 안전하게 처리 가능.
    private fun parseStoredDate(dateStr: String): Long? {
        return try {
            SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).parse(dateStr)?.time
        } catch (e: Exception) {
            Log.e(TAG, "❌ 저장된 날짜 파싱 실패: $dateStr", e)
            null
        }
    }

    private fun computeDesiredAlarms(
        schedule: ScheduleData,
        templates: Map<String, List<Pair<String, Int>>>
    ): List<DesiredAlarm> {
        if (!schedule.isRegular) return emptyList()

        val result = mutableListOf<DesiredAlarm>()
        val today = Calendar.getInstance()
        val now = System.currentTimeMillis()
        val dayKeyFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val fullFormat = SimpleDateFormat(DATE_FORMAT, Locale.getDefault())

        for (i in 0 until DAYS_AHEAD) {
            val targetDate = Calendar.getInstance().apply {
                timeInMillis = today.timeInMillis
                add(Calendar.DAY_OF_MONTH, i)
            }
            val dayKey = dayKeyFormat.format(targetDate.time)

            // ⭐ 수동 지정 예외가 있으면 우선 적용 (달력 팝업에서 지정한 값)
            val shiftType = schedule.assignedDates[dayKey] ?: run {
                if (schedule.pattern.isEmpty()) return@run "미설정"
                // ⭐ DST 안전한 일수 계산: 밀리초 차이를 86400000(24시간)으로 나누면,
                // 시작일과 대상일 사이에 서머타임 전환일(하루가 23/25시간)이 껴있는
                // 나라/시간대에서는 daysDiff가 정수가 아니게 되어 .toInt() 절삭 시
                // 패턴 인덱스가 하루씩 밀릴 수 있음. 순수 연/월/일 기반 Julian Day
                // Number로 계산하면 시간대/DST와 완전히 무관하게 항상 정확함.
                val startCal = Calendar.getInstance().apply { timeInMillis = schedule.startDateMillis }
                val daysDiff = julianDayNumber(targetDate) - julianDayNumber(startCal)
                val idx = ((schedule.todayIndex + daysDiff) % schedule.pattern.size + schedule.pattern.size) % schedule.pattern.size
                schedule.pattern[idx]
            }

            if (shiftType == "미설정") continue

            val shiftTemplates = templates[shiftType] ?: continue
            for ((time, alarmTypeId) in shiftTemplates) {
                val timeParts = time.split(":")
                if (timeParts.size < 2) continue
                val alarmCal = Calendar.getInstance().apply {
                    timeInMillis = targetDate.timeInMillis
                    set(Calendar.HOUR_OF_DAY, timeParts[0].toInt())
                    set(Calendar.MINUTE, timeParts[1].toInt())
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }

                // ⭐ CRITICAL FIX: readExistingFixedAlarms()는 "date > now"로 조회하는데
                // 여기는 "now - 60초"까지 봐줬음 - 그래서 방금(60초 이내) 울린/지나간
                // 알람이 desired엔 있는데 existing엔 없는 상태가 돼서 toAdd로 오인되고,
                // 과거 timestamp로 재삽입+재예약(scheduleNativeAlarm)되어 즉시 다시
                // 울려버릴 수 있었음. 방금 끄기/스누즈한 알람이 finishUp()의
                // checkAndTriggerRefresh() 호출로 인해 몇 초 뒤 부활하는 경로였음.
                // existing과 완전히 같은 기준(> now)으로 맞춤.
                if (alarmCal.timeInMillis <= now) continue

                result.add(
                    DesiredAlarm(
                        dateStr = fullFormat.format(alarmCal.time),
                        time = time,
                        shiftType = shiftType,
                        alarmTypeId = alarmTypeId,
                        timestamp = alarmCal.timeInMillis
                    )
                )
            }
        }
        return result
    }

    private fun cancelNativeAlarm(context: Context, alarmManager: AlarmManager, alarmId: Int) {
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$alarmId")
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, alarmId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }

    private fun scheduleNativeAlarm(context: Context, alarmManager: AlarmManager, alarmId: Int, timestamp: Long, shiftType: String) {
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

    private fun insertHistory(db: SQLiteDatabase, alarmId: Int, dateStr: String, time: String, shiftType: String, dismissType: String) {
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        val values = ContentValues().apply {
            put("alarm_id", alarmId)
            put("scheduled_time", time)
            put("scheduled_date", dateStr)
            put("actual_ring_time", now)
            put("dismiss_type", dismissType)
            put("snooze_count", 0)
            put("shift_type", shiftType)
            put("created_at", now)
        }
        db.insert("alarm_history", null, values)
    }

    private fun insertCreationLog(db: SQLiteDatabase, alarmId: Int, dateStr: String, time: String, shiftType: String, alarmTypeId: Int, source: String) {
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        val values = ContentValues().apply {
            put("alarm_id", alarmId)
            put("scheduled_date", dateStr)
            put("scheduled_time", time)
            put("shift_type", shiftType)
            put("alarm_type_id", alarmTypeId)
            put("source", source)
            put("created_at", now)
        }
        db.insert("alarm_creation_log", null, values)
    }

    // ⭐ 불규칙 스케줄: DB에 있는 모든 미래 알람을 Native AlarmManager에 재등록
    private fun reRegisterExistingAlarms(context: Context, db: SQLiteDatabase) {
        val now = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        var count = 0

        db.query("alarms", null, "date > ?", arrayOf(now), null, null, "date ASC").use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                val dateStr = cursor.getString(cursor.getColumnIndexOrThrow("date"))
                val shiftType = cursor.getString(cursor.getColumnIndexOrThrow("shift_type")) ?: "알람"
                val timestamp = try {
                    SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).parse(dateStr)?.time
                } catch (e: Exception) {
                    null
                }
                if (timestamp != null && timestamp > System.currentTimeMillis()) {
                    scheduleNativeAlarm(context, alarmManager, id, timestamp, shiftType)
                    count++
                }
            }
        }
        Log.d(TAG, "✅ 불규칙 스케줄 알람 ${count}개 재등록 완료")
    }

    // ⭐ alarm_creation_log는 여기서 정리 안 함 (의도적).
    // "생성됐다는 사실 자체는 버그로 삭제되더라도 항상 남아있어야 한다"는 요구사항이라
    // alarm_history(끄기/스누즈 등 결과 이력, 10일 지나면 정리됨)와 달리 자동 삭제하지 않음.
    private fun markRefreshed(context: Context) {
        try {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }
            val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
            prefs.edit().putLong("last_alarm_refresh", System.currentTimeMillis()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "갱신 표시 실패", e)
        }
    }

    private fun notifyFlutter(context: Context) {
        try {
            val intent = Intent("com.hwani1103.shiftbell.FLUTTER_REFRESH")
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Flutter 알림 실패", e)
        }
    }
}
