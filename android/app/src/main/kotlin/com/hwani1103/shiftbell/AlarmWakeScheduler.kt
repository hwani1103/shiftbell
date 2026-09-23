package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * ⭐ 2026-09-14 (출시전 감사 #16/#27/#20, G1) - 기상 알람(CustomAlarmReceiver)의 OS 예약·취소를 전부 여기로 모음.
 *
 * 예전 문제:
 *  - 예약 코드가 6곳(AlarmRefreshEngine·MainActivity·AlarmActionHelper·AlarmGuardReceiver·DirectBootReceiver·
 *    엔진 불규칙 재등록)에 복제돼 있었고, DirectBootReceiver만 Intent에 setPackage()를 넣어서 PendingIntent가
 *    달라졌음(Intent.filterEquals는 package도 비교) → 재부팅 후 같은 알람이 두 번 예약돼 0.5초 간격으로 두 번
 *    울렸고, 다른 경로의 취소도 그 예약을 못 지웠음(g1/handoff.md 착수 전 메모).
 *  - 엔진·스누즈·끄기가 DB 트랜잭션 도중/전에 OS를 건드려서, DB가 롤백되거나 그 사이 다른 쪽이 행을 바꾸면
 *    OS 예약과 DB가 어긋났음(#16/#27).
 *
 * 규칙(contracts.md §2 "OS 반영 재확인"):
 *  - DB를 먼저 커밋하고, OS 반영 직전에 행을 다시 읽는다.
 *    예약 = 행이 있고 DB 예정 시각이 이 작업의 시각과 같을 때만 / 취소 = 행이 없으면 항상, 있으면 DB 시각으로 재예약.
 *  - 모든 예약 Intent에 예정 시각(초 단위로 정규화한 ms)을 담고, 울릴 때 DB 행 시각과 정확히 비교한다
 *    ([decideOnReceive], 1분 같은 허용 오차 없음).
 *  - OS 반영이 실패하면 알람 ID를 Device Protected prefs에 기록하고 엔진 시작·Guard·앱 재개에서 DB 기준으로 재시도.
 *  - 예약 API는 setAlarmClock(#20) - 절전(Doze)에서도 제시간 전달이 가장 강한 API. showIntent는 앱 화면.
 *    정확한 알람 권한이 없어 거부되면 비정확 예약으로라도 걸어두고 실패로 보고함(#13 안내 + 재시도).
 * 일정 알림(ScheduleNotificationScheduler)·수면 감지·자동 종료 예약은 이 정책 대상이 아님.
 */
object AlarmWakeScheduler {
    private const val TAG = "AlarmWakeScheduler"
    private const val DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"
    private const val PREFS_NAME = "alarm_state"
    private const val KEY_FAILED_IDS = "os_sync_failed_alarm_ids"
    private const val SHOW_INTENT_REQUEST_CODE = 7700

    /** 예약 시점의 예정 시각(초 단위로 정규화한 epoch ms) */
    const val EXTRA_EXPECTED_AT = "expectedAtMillis"

    enum class Outcome { SCHEDULED, CANCELLED, SKIPPED_STALE, FAILED }
    enum class ReceiveDecision { RING, SKIP_NO_ROW, SKIP_RESCHEDULED }

    data class WakeRow(val id: Int, val timestamp: Long, val label: String)

    /** exists=false: 행 없음 / exists=true, row=null: 행은 있지만 날짜를 못 읽음 */
    private data class Lookup(val exists: Boolean, val row: WakeRow?)

    /** DB 날짜 문자열이 초까지만 담으므로 예약 시각도 초 단위로 맞춤 */
    fun normalize(timestamp: Long): Long = timestamp - Math.floorMod(timestamp, 1000L)

    private fun baseIntent(context: Context, id: Int) = Intent(context, CustomAlarmReceiver::class.java).apply {
        data = android.net.Uri.parse("shiftbell://alarm/$id")
    }

    private fun alarmManager(context: Context) = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun showIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context, SHOW_INTENT_REQUEST_CODE,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("openTab", 0)
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // 이 수정 이전 DirectBootReceiver가 남긴 setPackage() 변형 예약 - 앱 업데이트 뒤에도 OS에 남아 있을 수 있어
    // 같은 ID를 예약·취소할 때마다 함께 지움
    private fun cancelLegacyVariant(context: Context, id: Int) {
        try {
            val legacy = baseIntent(context, id).apply { setPackage(context.packageName) }
            val pi = PendingIntent.getBroadcast(
                context, id, legacy, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: return
            alarmManager(context).cancel(pi)
            pi.cancel()
            Log.w(TAG, "🧹 옛 재부팅 경로 중복 예약 제거: id=$id")
        } catch (e: Exception) {
            Log.w(TAG, "옛 중복 예약 확인 실패: id=$id", e)
        }
    }

    /** 재확인 없이 OS에 예약. 실패하면 예외를 던짐. 보통은 [scheduleIfCurrent]를 쓸 것. */
    fun scheduleRaw(context: Context, id: Int, timestamp: Long, label: String) {
        val at = normalize(timestamp)
        cancelLegacyVariant(context, id)
        val intent = baseIntent(context, id).apply {
            putExtra(CustomAlarmReceiver.EXTRA_ID, id)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, "loud")
            putExtra(EXTRA_EXPECTED_AT, at)
        }
        val operation = PendingIntent.getBroadcast(
            context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = alarmManager(context)
        try {
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(at, showIntent(context)), operation)
        } catch (e: SecurityException) {
            // 정확한 알람 권한이 꺼진 경우 - 늦더라도 울리게 비정확 예약을 걸어두고, 실패로 보고해 안내·재시도
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, at, operation)
                }
                Log.w(TAG, "⚠️ 정확한 예약 거부 - 비정확 예약으로 대체: id=$id")
            } catch (fallbackError: Exception) {
                Log.e(TAG, "❌ 비정확 대체 예약도 실패: id=$id", fallbackError)
            }
            throw e
        }
    }

    /** 재확인 없이 OS 예약 취소(없으면 아무 일 없음). 보통은 [cancelIfGone]을 쓸 것. */
    fun cancelRaw(context: Context, id: Int) {
        cancelLegacyVariant(context, id)
        val pi = PendingIntent.getBroadcast(
            context, id, baseIntent(context, id), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        alarmManager(context).cancel(pi)
        pi.cancel()
    }

    internal fun parse(dateStr: String): Long? = try {
        SimpleDateFormat(DATE_FORMAT, Locale.US).parse(dateStr)?.time
    } catch (e: Exception) {
        Log.e(TAG, "❌ 알람 날짜 파싱 실패: $dateStr", e)
        null
    }

    private fun lookup(db: SQLiteDatabase, id: Int): Lookup {
        db.query("alarms", arrayOf("date", "shift_type"), "id = ?", arrayOf(id.toString()), null, null, null).use { c ->
            if (!c.moveToFirst()) return Lookup(false, null)
            val timestamp = c.getString(0)?.let { parse(it) } ?: return Lookup(true, null)
            return Lookup(true, WakeRow(id, timestamp, c.getString(1) ?: "알람"))
        }
    }

    /**
     * 예약 반영(커밋 뒤 호출). 행이 없거나 DB 예정 시각이 [timestamp]와 다르면 버림(SKIPPED_STALE - 더 최신 작업이
     * 따로 반영함). DB가 없거나 읽기·파싱에 실패하면 수신 시 [decideOnReceive]가 다시 판정할 수 있도록 예약은
     * 진행하고, DB 기준 재확인을 위해 실패 ID도 남김.
     */
    fun scheduleIfCurrent(
        context: Context,
        db: SQLiteDatabase?,
        id: Int,
        timestamp: Long,
        label: String,
        scheduleFn: (Context, Int, Long, String) -> Unit = { c, i, t, l -> scheduleRaw(c, i, t, l) }
    ): Outcome {
        if (db == null) {
            Log.w(TAG, "예약 전 행 확인 불가(DB 없음) - 우선 예약 후 재확인: id=$id")
            return scheduleUnverified(context, id, timestamp, label, scheduleFn)
        }
        val found = try {
            lookup(db, id)
        } catch (e: Exception) {
            Log.e(TAG, "예약 전 행 확인 실패 - 우선 예약 후 재확인: id=$id", e)
            return scheduleUnverified(context, id, timestamp, label, scheduleFn)
        }
        if (!found.exists) {
            Log.d(TAG, "⏭️ 예약 버림(행 없음): id=$id")
            clearFailure(context, id)
            DiagLog.log(context, "SCHEDULE_SKIP", "id" to id, "why" to "no_row")
            return Outcome.SKIPPED_STALE
        }
        val row = found.row
        if (row == null) {
            Log.e(TAG, "예약 전 행 시각 확인 실패 - 우선 예약 후 재확인: id=$id")
            return scheduleUnverified(context, id, timestamp, label, scheduleFn)
        }
        if (row.timestamp != normalize(timestamp)) {
            Log.d(TAG, "⏭️ 예약 버림(DB 시각 변경됨): id=$id 작업=$timestamp DB=${row.timestamp}")
            return Outcome.SKIPPED_STALE
        }
        return try {
            scheduleFn(context, id, timestamp, label)
            clearFailure(context, id)
            DiagLog.log(context, "SCHEDULE_OK", "id" to id, "at" to DiagLog.format(normalize(timestamp), "", emptyList()).substringBefore(" |"))
            Outcome.SCHEDULED
        } catch (e: Exception) {
            Log.e(TAG, "❌ 기상 알람 OS 예약 실패(재시도 목록에 기록): id=$id", e)
            recordFailure(context, id)
            DiagLog.log(context, "SCHEDULE_FAIL", "id" to id,
                "reason" to (if (e is SecurityException) "exact_alarm_permission" else e.javaClass.simpleName))
            Outcome.FAILED
        }
    }

    /** DB 상태를 확인하지 못한 경우 알람 누락을 피하되, 다음 트리거에서 DB 기준 재검증하도록 실패 ID를 유지한다. */
    private fun scheduleUnverified(
        context: Context,
        id: Int,
        timestamp: Long,
        label: String,
        scheduleFn: (Context, Int, Long, String) -> Unit
    ): Outcome = try {
        scheduleFn(context, id, timestamp, label)
        recordFailure(context, id)
        DiagLog.log(context, "SCHEDULE_OK", "id" to id, "verified" to false)
        Outcome.SCHEDULED
    } catch (e: Exception) {
        Log.e(TAG, "❌ 미확인 기상 알람 OS 예약 실패: id=$id", e)
        recordFailure(context, id)
        DiagLog.log(context, "SCHEDULE_FAIL", "id" to id, "verified" to false,
            "reason" to (if (e is SecurityException) "exact_alarm_permission" else e.javaClass.simpleName))
        Outcome.FAILED
    }

    /**
     * 취소 반영(커밋 뒤 호출). 먼저 DB를 확인하고, 행이 남아 있고 미래면(같은 ID를 스누즈가 다시 쓰는 경우 등)
     * 기존 예약을 지우지 않은 채 DB 시각으로 교체 예약함. DB 확인 실패 시 현재 OS 예약을 보존하고 재시도에 남김.
     */
    fun cancelIfGone(context: Context, db: SQLiteDatabase?, id: Int): Outcome {
        if (db == null) {
            Log.e(TAG, "취소 전 행 확인 불가(DB 없음): id=$id")
            recordFailure(context, id)
            return Outcome.FAILED
        }
        val found = try {
            lookup(db, id)
        } catch (e: Exception) {
            Log.e(TAG, "취소 전 행 확인 실패 - 현재 예약 보존: id=$id", e)
            recordFailure(context, id)
            return Outcome.FAILED
        }
        val row = found.row
        if (found.exists && row == null) {
            Log.e(TAG, "취소 전 행 시각 확인 실패 - 현재 예약 보존: id=$id")
            recordFailure(context, id)
            return Outcome.FAILED
        }
        if (row != null && row.timestamp > System.currentTimeMillis()) {
            Log.d(TAG, "🔁 취소 대상 행이 아직 유효 - 현재 예약을 DB 시각으로 교체: id=$id")
            return scheduleIfCurrent(context, db, id, row.timestamp, row.label)
        }
        try {
            cancelRaw(context, id)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 기상 알람 OS 취소 실패(재시도 목록에 기록): id=$id", e)
            recordFailure(context, id)
            return Outcome.FAILED
        }
        clearFailure(context, id)
        DiagLog.log(context, "CANCEL", "id" to id)
        return Outcome.CANCELLED
    }

    /**
     * 울릴 때 판정(#27). 행 없음 → 안 울림 / 예정 시각 일치 → 울림 / 불일치 + DB 미래 → 안 울리고 DB 시각으로
     * 재예약(옛 예약이 늦게 반영된 경우 - 앞당겨 울리지 않음) / 불일치 + DB 과거 → 울림(놓친 알람은 늦게라도) /
     * 예정 시각 없음(수정 이전 예약)·날짜 파싱 실패·DB 접근 불가 → 울림(fail-open).
     */
    fun decideOnReceive(context: Context, id: Int, expectedAt: Long?): ReceiveDecision {
        val db = try {
            DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
        } catch (e: Exception) {
            Log.e(TAG, "수신 판정 DB 열기 실패 - 울림", e)
            null
        } ?: return ReceiveDecision.RING
        val found = try {
            lookup(db, id)
        } catch (e: Exception) {
            Log.e(TAG, "수신 판정 행 조회 실패 - 울림: id=$id", e)
            return ReceiveDecision.RING
        }
        if (!found.exists) return ReceiveDecision.SKIP_NO_ROW
        val row = found.row ?: return ReceiveDecision.RING
        if (expectedAt == null || row.timestamp == expectedAt) return ReceiveDecision.RING
        if (row.timestamp > System.currentTimeMillis()) {
            scheduleIfCurrent(context, db, id, row.timestamp, row.label)
            return ReceiveDecision.SKIP_RESCHEDULED
        }
        return ReceiveDecision.RING
    }

    private fun prefs(context: Context) = (
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
    ).getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun failedIds(context: Context): Set<Int> =
        prefs(context).getStringSet(KEY_FAILED_IDS, emptySet())!!.mapNotNull { it.toIntOrNull() }.toSet()

    @Synchronized
    fun recordFailure(context: Context, id: Int) {
        val p = prefs(context)
        val set = HashSet(p.getStringSet(KEY_FAILED_IDS, emptySet())!!)
        if (set.add(id.toString())) p.edit().putStringSet(KEY_FAILED_IDS, set).commit()
    }

    @Synchronized
    internal fun clearFailure(context: Context, id: Int) {
        val p = prefs(context)
        val current = p.getStringSet(KEY_FAILED_IDS, emptySet())!!
        if (id.toString() !in current) return
        p.edit().putStringSet(KEY_FAILED_IDS, HashSet(current).apply { remove(id.toString()) }).commit()
    }

    /** 기록된 OS 반영 실패를 DB 기준으로 재시도(엔진 시작·Guard·앱 재개). 성공하거나 할 일이 없어진 ID는 목록에서 지움. */
    fun retryFailed(context: Context) {
        // ⭐ G4 #19 - 복원 중엔 옛/중간 DB로 OS를 바꾸지 않음(복원 owner가 최종 재조정)
        if (RestoreGate.shouldDefer(context, "retryFailed")) return
        val ids = failedIds(context)
        if (ids.isEmpty()) return
        val db = try {
            DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
        } catch (e: Exception) {
            null
        } ?: return
        Log.d(TAG, "🔁 OS 반영 실패 재시도: $ids")
        for (id in ids) {
            val found = try {
                lookup(db, id)
            } catch (e: Exception) {
                Log.e(TAG, "재시도 행 조회 실패: id=$id", e)
                continue
            }
            val row = found.row
            when {
                !found.exists -> cancelIfGone(context, db, id)
                row != null && row.timestamp > System.currentTimeMillis() ->
                    scheduleIfCurrent(context, db, id, row.timestamp, row.label)
                else -> clearFailure(context, id)  // 이미 지난 시각·날짜 손상 - 다시 걸 것이 없음
            }
        }
    }
}
