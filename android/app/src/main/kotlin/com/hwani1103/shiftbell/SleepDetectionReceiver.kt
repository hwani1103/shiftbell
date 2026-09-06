package com.hwani1103.shiftbell

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ⭐ 실제 수면 기록/자동 추정("C번 요구사항") - [SleepDetectionScheduler]가 예약한
 * 20분 간격 알람을 받아 "화면이 오래 꺼져 있는가"를 판단하고 sleep_records에
 * 후보(PENDING_CONFIRMATION)를 만들거나 종료한다.
 *
 * ⚠️ 상시 화면 감시가 아니라 이 알람이 울릴 때만 [PowerManager.isInteractive]를
 * 스냅샷으로 확인함(수면기록_자동추정_조사.md 2장 ⑤) - 연속 2회 "꺼짐"이 확인돼야
 * 비로소 후보를 만든다(1회만으로는 "방금 껐는지 오래됐는지" 구분이 안 됨).
 *
 * ⚠️ 수동(MANUAL) 진행 중인 기록이 있으면 이 리시버는 아무 것도 하지 않고 즉시
 * 스킵한다 - "사용자가 직접 기록한 수면이 항상 최우선"이라는 원칙(스펙 25장)을
 * 코드 수준에서 보장.
 *
 * ⭐ 2026-09-01 - [checkNow]로 공개해서 "화면이 켜지는 시점을 이미 아는" 다른
 * 트리거(MainActivity.onResume/AlarmGuardReceiver.triggerCheck/DirectBootReceiver)가
 * 20분 알람을 기다리지 않고 즉시 이 판정을 돌릴 수 있게 함. 그전까지는 진행 중이던
 * 자동 감지 후보(end_time IS NULL)가 다음 20분 알람이 울릴 때까지 최대 20분간
 * "OO시부터 수면 중인 것으로 추정됩니다"(진행 중 상태)로 남아있는 문제가 있었음 -
 * 앱을 여는 것 자체가 곧 "화면이 켜졌다"는 신호이므로 그 자리에서 바로 후보를
 * 종료하고 실제 기상 시각 추정 범위("OO시~OO시")를 보여줄 수 있게 함.
 */
class SleepDetectionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        checkNow(context)
    }

    companion object {
        private const val TAG = "SleepDetectionReceiver"
        private const val PREFS_NAME = "sleep_detection_state"
        private const val KEY_FIRST_OFF_SAMPLE_AT = "first_off_sample_at"
        private const val MIN_MINUTES_FOR_MEDIUM_PLUS = 90L
        private const val ISO_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"

        // ⭐ 2026-09-01 후속4 - "메인 수면"으로 인정할 최소 길이(2시간, 순수 UX
        // 판단값 - 근거자료 값 아님). 이보다 짧으면 자동 감지 후보를 폐기한다.
        private const val MIN_MAIN_SLEEP_MINUTES = 120L

        private fun isoFormat(millis: Long): String =
            SimpleDateFormat(ISO_FORMAT, Locale.getDefault()).format(Date(millis))

        private fun parseIso(s: String): Long? = try {
            SimpleDateFormat(ISO_FORMAT, Locale.getDefault()).parse(s)?.time
        } catch (e: Exception) {
            null
        }

        /** 20분 알람 수신 시 + 화면 재개 등 "지금 확인해도 되는" 모든 트리거 지점에서 호출. */
        fun checkNow(context: Context) {
            try {
                handle(context)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 수면 감지 처리 실패", e)
            } finally {
                // ⭐ 어떤 분기를 타든 스스로 다음 체크를 다시 예약 - 감지 루프가 끊기지 않게 함.
                SleepDetectionScheduler.ensureScheduled(context)
            }
        }

        private fun handle(context: Context) {
            val db = DatabaseHelper.getInstance(context).getWritableDatabaseWithRetry() ?: return
            val prefs = devicePrefs(context)
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val isInteractive = powerManager.isInteractive
            val now = System.currentTimeMillis()

            // ⭐ 화면이 켜져 있는 동안은 "꺼짐 스트릭" 추적 자체가 의미 없음 - 항상 리셋.
            if (isInteractive) {
                prefs.edit().remove(KEY_FIRST_OFF_SAMPLE_AT).apply()
            }

            if (hasOngoingManual(db)) {
                Log.d(TAG, "⏭️ 수동 수면 진행 중 - 자동 감지 스킵")
                return
            }

            val ongoing = findOngoingAutoRecord(db)

            if (!isInteractive) {
                if (ongoing != null) {
                    Log.d(TAG, "💤 수면 후보 진행 중(id=${ongoing.first}) - 계속 대기")
                    return
                }

                // ⭐ 2026-09-01 후속4 - "지금이 실제로 수면 추적 창 안인가"를 여기서도
                // 다시 확인한다. checkNow()가 이제 MainActivity.onResume()/
                // AlarmGuardReceiver.triggerCheck() 같은, 창과 무관하게 하루 종일
                // 수시로 발생하는 트리거에서도 불리므로(13-1 참고) - 창 안에서만 도는
                // 20분 주기 알람과 달리 이 함수 자체는 창 밖에서도 호출될 수 있다.
                // 창 게이팅이 없으면 "출근 준비하며 폰을 잠깐 내려놓음" 같은 일상적인
                // 화면 꺼짐/켜짐이 "OO시~OO시 N분 수면"으로 잘못 잡히는 버그가 생김
                // (실제 발견된 사례: 야간 근무일 아침 09:15~09:20의 화면 꺼짐이
                // "5분 수면"으로 오인식됨 - 그 시각은 다음 근무의 수면 추적 창과
                // 전혀 무관한데도 창 확인 없이 후보를 만들어버린 게 원인).
                val window = SleepScheduleResolver.computeWindowForNow(context, now)
                if (window == null || now < window.startMillis || now >= window.endMillis) {
                    // 창 밖 - 화면이 잠깐 꺼진 것뿐인 일상적인 사용으로 보고 추적 시작 안 함.
                    prefs.edit().remove(KEY_FIRST_OFF_SAMPLE_AT).apply()
                    return
                }

                // ⭐ 2026-09-01 후속5 - "이 창은 이미 한 번 썼는가" 확인. 창 하나에서
                // 이미 수면 기록(수동/자동, 확정/대기 무관)이 시작됐다면 그 창의
                // "메인 잠 임무"는 끝난 것으로 보고 같은 창 안에서 또 새 후보를
                // 만들지 않는다 - 안 그러면 아침에 이미 한숨 자고 일어난 뒤, 그
                // 창이 아직(최대 9시간 캡까지) 열려있는 동안 낮에 폰을 잠깐씩
                // 내려놓는 것만으로도 "낮잠"이 자동으로 잡혀버림(자동 감지는
                // 메인 잠 전용이라 이런 경우까지 잡으면 안 됨 - 사용자가 낮잠을
                // 원하면 위젯으로 직접 기록). ⚠️ 창은 매번 새로 계산되므로(예:
                // 야간 근무 다음날 저녁 21시부터 열리는 별개의 창) 오늘 저녁에
                // 또 자는 것까지 막지는 않는다 - 그건 다른 창이라 여기 안 걸림.
                if (hasRecordStartingInWindow(db, window.startMillis, window.endMillis)) {
                    prefs.edit().remove(KEY_FIRST_OFF_SAMPLE_AT).apply()
                    Log.d(TAG, "⏭️ 이 수면 추적 창은 이미 기록이 있음 - 중복 추적 안 함")
                    return
                }

                val firstOffAt = prefs.getLong(KEY_FIRST_OFF_SAMPLE_AT, -1L)
                if (firstOffAt < 0L) {
                    prefs.edit().putLong(KEY_FIRST_OFF_SAMPLE_AT, now).apply()
                    Log.d(TAG, "🌙 첫 꺼짐 샘플 기록 - 다음 체크에서 계속 꺼져있으면 후보 생성")
                    return
                }

                if (hasRecordCovering(db, firstOffAt)) {
                    // ⭐ 스펙 14장 "중복 방지" - 이미 그 시각을 덮는 기록(수동 등)이 있으면
                    // 새 후보를 만들지 않음.
                    prefs.edit().remove(KEY_FIRST_OFF_SAMPLE_AT).apply()
                    return
                }

                val values = ContentValues().apply {
                    put("start_time", isoFormat(firstOffAt))
                    putNull("end_time")
                    put("source", "AUTO_DETECTED")
                    put("status", "PENDING_CONFIRMATION")
                    put("confidence", "MEDIUM")
                    put("created_at", isoFormat(now))
                    put("updated_at", isoFormat(now))
                }
                val id = db.insert("sleep_records", null, values)
                if (id > 0) {
                    Log.d(TAG, "🌙 수면 후보 생성(id=$id, start=${Date(firstOffAt)})")
                }
            } else if (ongoing != null) {
                val (id, startMillis) = ongoing
                val durationMinutes = (now - startMillis) / 60_000L

                // ⭐ 2026-09-01 후속4 - "메인 수면은 최소 2시간 이상"(사용자 요청) -
                // 이보다 짧게 끝나면 애초에 진짜 수면이 아니라 화면이 잠깐 꺼졌다
                // 켜진 것뿐일 가능성이 커서, 기록으로 남기지 않고 버린다(위젯의
                // MIN_MEANINGFUL_MINUTES와 같은 취지지만 자동 감지는 "메인 잠
                // 전용"이라 기준을 훨씬 크게 잡음 - SleepWidgetActionReceiver 참고).
                if (durationMinutes < MIN_MAIN_SLEEP_MINUTES) {
                    db.delete("sleep_records", "id = ?", arrayOf(id.toString()))
                    Log.d(TAG, "🗑️ 메인 수면 최소 길이(2시간) 미만(${durationMinutes}분) - 후보 폐기(id=$id)")
                    return
                }

                val charging = isCharging(context)
                val confidence = computeConfidence(durationMinutes, charging)

                val values = ContentValues().apply {
                    put("end_time", isoFormat(now))
                    put("confidence", confidence)
                    put("updated_at", isoFormat(now))
                }
                db.update("sleep_records", values, "id = ?", arrayOf(id.toString()))
                Log.d(TAG, "☀️ 수면 후보 종료(id=$id, ${durationMinutes}분, 신뢰도=$confidence)")
            }
        }

        private fun devicePrefs(context: Context): SharedPreferences {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.applicationContext.createDeviceProtectedStorageContext()
            } else {
                context.applicationContext
            }
            return deviceContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        private fun hasOngoingManual(db: SQLiteDatabase): Boolean {
            return try {
                db.query(
                    "sleep_records", arrayOf("id"),
                    "source = 'MANUAL' AND end_time IS NULL", null, null, null, null, "1"
                ).use { it.moveToFirst() }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 수동 진행 여부 확인 실패", e)
                false
            }
        }

        private fun findOngoingAutoRecord(db: SQLiteDatabase): Pair<Long, Long>? {
            return try {
                db.query(
                    "sleep_records", arrayOf("id", "start_time"),
                    "source = 'AUTO_DETECTED' AND end_time IS NULL", null, null, null, null, "1"
                ).use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    val id = cursor.getLong(0)
                    val startMillis = parseIso(cursor.getString(1)) ?: return null
                    Pair(id, startMillis)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 진행 중 자동 후보 조회 실패", e)
                null
            }
        }

        private fun hasRecordCovering(db: SQLiteDatabase, atMillis: Long): Boolean {
            val at = isoFormat(atMillis)
            return try {
                db.query(
                    "sleep_records", arrayOf("id"),
                    "start_time <= ? AND (end_time IS NULL OR end_time >= ?)",
                    arrayOf(at, at), null, null, null, "1"
                ).use { it.moveToFirst() }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 겹침 기록 확인 실패", e)
                false
            }
        }

        /** [startMillis, endMillis) 안에 start_time이 있는 sleep_records 행이 이미 있는가
         * (source/status 무관 - 이 창에서 이미 뭔가 기록됐으면 그걸로 충분). */
        private fun hasRecordStartingInWindow(db: SQLiteDatabase, startMillis: Long, endMillis: Long): Boolean {
            return try {
                db.query(
                    "sleep_records", arrayOf("id"),
                    "start_time >= ? AND start_time < ?",
                    arrayOf(isoFormat(startMillis), isoFormat(endMillis)), null, null, null, "1"
                ).use { it.moveToFirst() }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 창 내 기존 기록 확인 실패", e)
                false
            }
        }

        private fun isCharging(context: Context): Boolean {
            return try {
                val status = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    ?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
            } catch (e: Exception) {
                false
            }
        }

        // ⭐ 수면기록_자동추정_조사.md 4장 "신뢰도" 표를 그대로 코드로 옮김 - 룰 기반,
        // 머신러닝 없음(스펙 19장 지시대로). 2026-09-01 - "근무별 평균 취침시각" 앵커
        // 기반 가산점 규칙은 그 입력 기능 자체를 걷어내면서 함께 삭제함.
        private fun computeConfidence(durationMinutes: Long, charging: Boolean): String {
            var score = 1 // 0=LOW, 1=MEDIUM, 2=HIGH
            if (charging) score++
            if (durationMinutes < MIN_MINUTES_FOR_MEDIUM_PLUS) score--
            score = score.coerceIn(0, 2)
            return when (score) {
                0 -> "LOW"
                1 -> "MEDIUM"
                else -> "HIGH"
            }
        }
    }
}
