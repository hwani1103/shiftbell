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
 *
 * ⭐ 2026-09-14 (출시전 교차 검토 X-04/X-06)
 *  - 이월 대상 = 지금 울리는 알람 + 종료 관문은 지났지만 끄기/스누즈 DB 반영이 아직인 알람 + 최근 1시간 이후의 스누즈 행
 *    (스누즈 시각이 막 지나 수신 직전인 행도 교체로 지워지지 않게). 울림 상태 epoch를 같이 돌려주고, Dart가 DB 교체
 *    트랜잭션 끝에서 다시 비교해 달라졌으면 롤백 후 재시도.
 *  - 재생 설정 스냅샷 저장 실패는 복원 실패로 올림.
 *  - 최종 재조정에서 갱신 엔진이 실제로 끝까지 돌지 못했거나(잠금 경합·예외) 일정 알림 재예약이 실패하면 예외 → Dart는
 *    복원을 "미완료"로 남기고 사용자에게 이어서 완료를 묻는다. 정확한 알람 권한 거부 같은 개별 예약 실패는 비정확 예약 +
 *    재시도 목록으로 이미 처리되므로 미완료로 보지 않고 건수만 돌려줌.
 */
object RestoreOs {
    private const val TAG = "RestoreOs"
    private const val DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"
    private const val SNOOZE_CARRY_LOOKBACK_MS = 60 * 60 * 1000L
    private const val REFRESH_ATTEMPTS = 5
    private const val REFRESH_RETRY_DELAY_MS = 1_000L

    private fun requireOwner(context: Context, token: String?) {
        check(RestoreGate.isOwner(context, token)) { "restore owner token mismatch" }
    }

    private fun dbString(millis: Long): String = SimpleDateFormat(DATE_FORMAT, Locale.US).format(Date(millis))

    /**
     * 이 기기에서 진행 중인 알람의 ID와 울림 상태 epoch. 그 알람들의 현재 재생 설정 스냅샷도 저장
     * (이미 있으면 덮어쓰지 않음 - 재시도에서도 복원 전 값 유지).
     */
    fun prepareCarryOver(context: Context, token: String?): Map<String, Any?> {
        requireOwner(context, token)
        val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
            ?: throw IllegalStateException("DB not ready")
        val state = RingingAlarmTracker.carryState(context)
        val activeRingId = state.active?.alarmId
        val carryIds = linkedSetOf<Int>()
        db.rawQuery(
            "SELECT id FROM alarms WHERE type = 'snoozed' AND date > ?",
            arrayOf(dbString(System.currentTimeMillis() - SNOOZE_CARRY_LOOKBACK_MS))
        ).use { c -> while (c.moveToNext()) carryIds.add(c.getInt(0)) }
        activeRingId?.let { carryIds.add(it) }
        carryIds.addAll(state.endingIds)

        for (id in carryIds) {
            db.rawQuery(
                "SELECT t.sound_file, t.volume, t.vibration_strength, t.duration FROM alarms a " +
                    "JOIN alarm_types t ON t.id = a.alarm_type_id WHERE a.id = ?",
                arrayOf(id.toString())
            ).use { c ->
                if (c.moveToFirst()) {
                    val saved = RestoreGate.saveRingSnapshotIfAbsent(
                        context, id,
                        RestoreGate.RingSnapshot(
                            soundFile = c.getString(0),
                            volume = c.getFloat(1),
                            vibrationStrength = if (c.isNull(2)) 2 else c.getInt(2),
                            durationMinutes = if (c.isNull(3)) 10 else c.getInt(3)
                        )
                    )
                    check(saved) { "ring snapshot save failed: id=$id" }
                }
            }
        }
        Log.d(TAG, "🧳 진행 중 알람 이월 대상: $carryIds (울림=$activeRingId, 종료 처리 중=${state.endingIds}, epoch=${state.epoch})")
        return mapOf("activeRingId" to activeRingId, "carryIds" to carryIds.toList(), "epoch" to state.epoch)
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
     * 갱신 엔진·일정 재예약이 끝까지 돌지 못하면 예외. 반환값의 wakeFailures = 재시도 목록으로 넘어간 개별 예약 실패 수.
     */
    fun reconcileOs(context: Context, token: String?, scheduleTabEnabled: Boolean): Map<String, Any?> {
        requireOwner(context, token)
        var refreshed = false
        for (attempt in 1..REFRESH_ATTEMPTS) {
            if (AlarmRefreshEngine.refresh(context, token)) {
                refreshed = true
                break
            }
            Log.w(TAG, "⚠️ 복원 재조정 - 갱신 엔진 미완료(시도 $attempt/$REFRESH_ATTEMPTS)")
            if (attempt < REFRESH_ATTEMPTS) Thread.sleep(REFRESH_RETRY_DELAY_MS)
        }
        check(refreshed) { "alarm refresh did not complete" }

        val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry()
            ?: throw IllegalStateException("DB not ready")
        var scheduled = 0
        var failures = 0
        db.rawQuery(
            "SELECT id, date, shift_type FROM alarms WHERE type IN ('custom', 'snoozed') AND date > ?",
            arrayOf(dbString(System.currentTimeMillis()))
        ).use { c ->
            while (c.moveToNext()) {
                val id = c.getInt(0)
                val timestamp = AlarmWakeScheduler.parse(c.getString(1) ?: continue) ?: continue
                val label = c.getString(2) ?: "알람"
                if (AlarmWakeScheduler.scheduleIfCurrent(context, db, id, timestamp, label) ==
                    AlarmWakeScheduler.Outcome.FAILED) failures++ else scheduled++
            }
        }

        ScheduleNotificationScheduler.setTabEnabled(context, scheduleTabEnabled)
        check(ScheduleNotificationScheduler.rescheduleAllFromDb(context, token)) { "schedule notification reschedule failed" }
        Log.d(TAG, "✅ 복원 OS 재조정 완료: custom·snoozed ${scheduled}건(실패 ${failures}건), 일정 탭=$scheduleTabEnabled")
        return mapOf("wakeFailures" to failures)
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
