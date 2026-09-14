package com.hwani1103.shiftbell

import android.content.Context
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ⭐ 2026-09-14 (출시전 감사 G4 #9/#19) - 백업 복원 owner(Dart RestoreCoordinator)가 MethodChannel로 부르는 OS 단계.
 * 모든 함수는 살아 있는 복원 토큰([RestoreGate.isOwner])일 때만 실행한다.
 *
 * 단계: prepareCarryOver(진행 중 알람 확인·재생 설정 스냅샷) → clearOs(옛 예약 취소, 진행 중 알람 제외)
 *       → [Dart DB 교체·설정 반영] → reconcileOs(fixed 재계산 + 미래 custom·snoozed 명시 재예약 + 일정 알림 재예약).
 * 갱신 엔진(forceRefresh)만으로는 custom/snoozed가 복구됐다고 보지 않으므로 reconcile에서 직접 다시 건다.
 */
object RestoreOs {
    private const val TAG = "RestoreOs"
    private const val DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"

    private fun requireOwner(context: Context, token: String?) {
        check(RestoreGate.isOwner(context, token)) { "restore owner token mismatch" }
    }

    private fun nowString(): String = SimpleDateFormat(DATE_FORMAT, Locale.US).format(Date())

    /**
     * 이 기기에서 진행 중인 알람(지금 울리는 알람 + 미래 스누즈)의 ID와, 그 알람들의 현재 재생 설정 스냅샷.
     * 스냅샷은 이미 있으면 덮어쓰지 않음(재시도에서도 복원 전 값 유지).
     */
    fun prepareCarryOver(context: Context, token: String?): Map<String, Any?> {
        requireOwner(context, token)
        val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
            ?: throw IllegalStateException("DB not ready")
        val activeRingId = RingingAlarmTracker.current(context)?.alarmId
        val carryIds = linkedSetOf<Int>()
        db.rawQuery(
            "SELECT id FROM alarms WHERE (type = 'snoozed' AND date > ?) OR id = ?",
            arrayOf(nowString(), (activeRingId ?: -1).toString())
        ).use { c -> while (c.moveToNext()) carryIds.add(c.getInt(0)) }

        for (id in carryIds) {
            db.rawQuery(
                "SELECT t.sound_file, t.volume, t.vibration_strength, t.duration FROM alarms a " +
                    "JOIN alarm_types t ON t.id = a.alarm_type_id WHERE a.id = ?",
                arrayOf(id.toString())
            ).use { c ->
                if (c.moveToFirst()) {
                    RestoreGate.saveRingSnapshotIfAbsent(
                        context, id,
                        RestoreGate.RingSnapshot(
                            soundFile = c.getString(0),
                            volume = c.getFloat(1),
                            vibrationStrength = if (c.isNull(2)) 2 else c.getInt(2),
                            durationMinutes = if (c.isNull(3)) 10 else c.getInt(3)
                        )
                    )
                }
            }
        }
        Log.d(TAG, "🧳 진행 중 알람 이월 대상: $carryIds (울림=$activeRingId)")
        return mapOf("activeRingId" to activeRingId, "carryIds" to carryIds.toList())
    }

    /** 옛 기상 알람 예약([keepIds] 제외)과 일정 알림 예약·표시를 모두 취소. DB는 건드리지 않음. */
    fun clearOs(context: Context, token: String?, keepIds: Set<Int>) {
        requireOwner(context, token)
        val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
            ?: throw IllegalStateException("DB not ready")
        val ids = mutableListOf<Int>()
        db.rawQuery("SELECT id FROM alarms", null).use { c -> while (c.moveToNext()) ids.add(c.getInt(0)) }
        var cancelled = 0
        for (id in ids) {
            if (id in keepIds) continue
            AlarmWakeScheduler.cancelRaw(context, id)
            cancelled++
        }
        ScheduleNotificationScheduler.cancelAllFromDb(context)
        Log.d(TAG, "🧹 복원 전 OS 예약 취소: 기상 알람 ${cancelled}건(보존 $keepIds), 일정 알림 전체")
    }

    /**
     * 복원된 DB 기준 최종 OS 재조정. fixed는 갱신 엔진(#26/#31 계산), 미래 custom·snoozed는 명시 재예약,
     * 일정 알림은 복원된 탭 사용 설정([scheduleTabEnabled])으로 재예약 또는 전체 취소.
     */
    fun reconcileOs(context: Context, token: String?, scheduleTabEnabled: Boolean) {
        requireOwner(context, token)
        AlarmRefreshEngine.refresh(context, token)

        val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
            ?: throw IllegalStateException("DB not ready")
        var scheduled = 0
        db.rawQuery(
            "SELECT id, date, shift_type FROM alarms WHERE type IN ('custom', 'snoozed') AND date > ?",
            arrayOf(nowString())
        ).use { c ->
            while (c.moveToNext()) {
                val id = c.getInt(0)
                val timestamp = AlarmWakeScheduler.parse(c.getString(1) ?: continue) ?: continue
                val label = c.getString(2) ?: "알람"
                if (AlarmWakeScheduler.scheduleIfCurrent(context, db, id, timestamp, label) !=
                    AlarmWakeScheduler.Outcome.FAILED) scheduled++
            }
        }

        ScheduleNotificationScheduler.setTabEnabled(context, scheduleTabEnabled)
        ScheduleNotificationScheduler.rescheduleAllFromDb(context, token)
        Log.d(TAG, "✅ 복원 OS 재조정 완료: custom·snoozed ${scheduled}건, 일정 탭=$scheduleTabEnabled")
    }

    /** DB에 행이 없고 지금 울리지도 않는 알람의 재생 설정 스냅샷 정리. 살아 있는 복원 중에는 하지 않음. */
    fun cleanupSnapshots(context: Context) {
        if (RestoreGate.isLocked(context)) return
        try {
            val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry() ?: return
            val live = mutableSetOf<Int>()
            db.rawQuery("SELECT id FROM alarms", null).use { c -> while (c.moveToNext()) live.add(c.getInt(0)) }
            RingingAlarmTracker.current(context)?.alarmId?.let { live.add(it) }
            RestoreGate.cleanupSnapshots(context, live)
        } catch (e: Exception) {
            Log.e(TAG, "재생 설정 스냅샷 정리 실패", e)
        }
    }
}
