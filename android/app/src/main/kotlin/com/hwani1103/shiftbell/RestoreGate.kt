package com.hwani1103.shiftbell

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/**
 * ⭐ 2026-09-14 (출시전 감사 G4 #19/#9) - 백업 복원 잠금과 진행 중 알람 재생 설정 스냅샷.
 *
 * 잠금 판정: 복원을 시작한 Dart가 무작위 토큰을 Device Protected prefs와 이 객체의 메모리 양쪽에 기록한다.
 *  - 두 값이 같으면 "살아 있는 복원" → 백그라운드 writer(갱신 엔진·재시도·일정 재예약·수면 감지·수면 위젯)는 쓰기를 미룬다.
 *  - prefs에만 있으면 프로세스가 재시작된 것(복원 작업은 이미 죽음) → 잠금을 풀고 현재 DB 기준으로 평소대로 동작,
 *    "복원이 완료되지 않았어요" 알림을 한 번 게시. 단계 기록·작업 사본(Dart 소유 파일)은 건드리지 않음 - 앱을 열면 이어서 처리.
 *  - 시간 경과만으로 살아 있는 잠금을 무시하지 않는다. 앱은 단일 프로세스(Manifest에 android:process 없음)라는 전제 -
 *    프로세스를 나누면 다시 설계할 것.
 * 복원 owner 자신이 부르는 최종 OS 재조정은 토큰으로 통과시킨다(자기 잠금에 막히는 교착 방지).
 *
 * 알람 재생·끄기·스누즈·타임아웃은 절대 막지 않는다.
 *
 * 재생 설정 스냅샷: 복원이 alarm_types를 백업 내용으로 바꾸면 진행 중(울림/스누즈) 알람의 alarm_type_id가 다른 소리·길이를
 * 가리키거나 없어질 수 있다. DB 교체 직전에 그 알람 ID별 현재 설정을 저장하고(이미 있으면 덮어쓰지 않음 - 첫 스냅샷이 복원 전 값),
 * 재생·지속시간 조회가 스냅샷을 우선 사용한다. 끄기·타임아웃에서 지우고, 행이 없어진 스냅샷은 정리 시 지운다.
 */
object RestoreGate {
    private const val TAG = "RestoreGate"
    private const val PREFS_NAME = "restore_state"
    private const val KEY_TOKEN = "restore_lock_token"
    private const val KEY_INTERRUPTED = "restore_interrupted"
    private const val KEY_DEFERRED = "restore_deferred_writers"
    private const val SNAPSHOT_PREFIX = "ring_snapshot_"
    private const val NOTIFY_CHANNEL_ID = "shiftbell_restore"
    private const val NOTIFY_ID = 7790

    @Volatile
    private var memoryToken: String? = null
    private val lock = Any()

    data class RingSnapshot(val soundFile: String, val volume: Float, val vibrationStrength: Int, val durationMinutes: Int)

    private fun prefs(context: Context) = (
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
    ).getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 복원 시작. 살아 있는 다른 복원이 있으면 false. 죽은 잠금은 새 토큰으로 교체. */
    fun acquire(context: Context, token: String): Boolean = synchronized(lock) {
        val p = prefs(context)
        val current = p.getString(KEY_TOKEN, null)
        if (current != null && current == memoryToken && current != token) {
            Log.w(TAG, "⛔ 이미 진행 중인 복원이 있음")
            return false
        }
        if (!p.edit().putString(KEY_TOKEN, token).remove(KEY_INTERRUPTED).commit()) {
            Log.e(TAG, "❌ 복원 잠금 기록 실패")
            return false
        }
        memoryToken = token
        Log.d(TAG, "🔒 복원 잠금 획득")
        true
    }

    /** 복원 종료(성공·중단 모두). 토큰이 다르면 아무것도 안 함. */
    fun release(context: Context, token: String): Boolean = synchronized(lock) {
        val p = prefs(context)
        if (p.getString(KEY_TOKEN, null) != token && memoryToken != token) return false
        memoryToken = null
        val ok = p.edit().remove(KEY_TOKEN).remove(KEY_DEFERRED).commit()
        Log.d(TAG, "🔓 복원 잠금 해제(commit=$ok)")
        ok
    }

    fun isOwner(context: Context, token: String?): Boolean = synchronized(lock) {
        token != null && token == memoryToken && prefs(context).getString(KEY_TOKEN, null) == token
    }

    /**
     * 백그라운드 writer용 판정. true면 이번 쓰기를 건너뛰어야 함(복원 owner가 끝에서 전체 재조정함).
     * [ownerToken]이 살아 있는 복원 토큰이면 통과. 죽은 잠금이면 풀고 false.
     */
    fun shouldDefer(context: Context, writer: String, ownerToken: String? = null): Boolean = synchronized(lock) {
        val p = prefs(context)
        val prefsToken = p.getString(KEY_TOKEN, null) ?: return false
        if (ownerToken != null && ownerToken == prefsToken && ownerToken == memoryToken) return false
        if (prefsToken == memoryToken) {
            val deferred = p.getStringSet(KEY_DEFERRED, emptySet())!!.toMutableSet()
            if (deferred.add(writer)) p.edit().putStringSet(KEY_DEFERRED, deferred).apply()
            Log.d(TAG, "⏸️ 복원 중 - $writer 쓰기 연기")
            return true
        }
        // 프로세스 재시작으로 owner가 사라진 잠금 - 차단을 풀고 사용자가 앱에서 마무리하도록 안내
        Log.w(TAG, "⚠️ 중단된 복원 잠금 발견($writer) - 잠금 해제, 현재 DB 기준으로 진행")
        p.edit().remove(KEY_TOKEN).remove(KEY_DEFERRED).putBoolean(KEY_INTERRUPTED, true).commit()
        memoryToken = null
        postInterruptedNotification(context)
        return false
    }

    /** 살아 있는 복원 잠금이 있는지(Dart 자동백업 등 판정용). 죽은 잠금은 이 호출로 정리됨. */
    fun isLocked(context: Context): Boolean = shouldDefer(context, "query")

    /** 앱 시작 시: 중단 알림 플래그를 읽고 지움. */
    fun consumeInterrupted(context: Context): Boolean {
        // 앱 프로세스가 새로 뜬 시점이라 메모리 토큰이 없으면 prefs 토큰은 죽은 잠금 - 여기서도 정리
        shouldDefer(context, "app_start")
        val p = prefs(context)
        val flagged = p.getBoolean(KEY_INTERRUPTED, false)
        if (flagged) p.edit().remove(KEY_INTERRUPTED).apply()
        return flagged
    }

    private fun postInterruptedNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(NOTIFY_CHANNEL_ID, "백업 복원 안내", NotificationManager.IMPORTANCE_DEFAULT)
                )
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val contentIntent = launch?.let {
                PendingIntent.getActivity(context, NOTIFY_ID, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            val notification = NotificationCompat.Builder(context, NOTIFY_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("백업 복원이 완료되지 않았어요")
                .setContentText("알람은 지금 데이터 기준으로 동작해요. 앱을 열어 복원을 마무리해 주세요.")
                .setStyle(NotificationCompat.BigTextStyle().bigText("알람은 지금 데이터 기준으로 동작해요. 앱을 열어 복원을 마무리해 주세요."))
                .setAutoCancel(true)
                .apply { if (contentIntent != null) setContentIntent(contentIntent) }
                .build()
            nm.notify(NOTIFY_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "복원 중단 알림 게시 실패", e)
        }
    }

    // ── 재생 설정 스냅샷 ──────────────────────────────────────────────

    /** 스냅샷이 확보됐으면 true(이미 있었거나 방금 저장). 저장 실패만 false - 호출부는 복원을 실패로 처리해야 함(교차 검토 X-04). */
    fun saveRingSnapshotIfAbsent(context: Context, alarmId: Int, snapshot: RingSnapshot): Boolean {
        val p = prefs(context)
        val key = "$SNAPSHOT_PREFIX$alarmId"
        if (p.contains(key)) return true
        val json = JSONObject()
            .put("sound_file", snapshot.soundFile)
            .put("volume", snapshot.volume.toDouble())
            .put("vibration_strength", snapshot.vibrationStrength)
            .put("duration", snapshot.durationMinutes)
        return p.edit().putString(key, json.toString()).commit()
    }

    fun ringSnapshot(context: Context, alarmId: Int): RingSnapshot? = try {
        prefs(context).getString("$SNAPSHOT_PREFIX$alarmId", null)?.let {
            val o = JSONObject(it)
            RingSnapshot(
                o.getString("sound_file"),
                o.getDouble("volume").toFloat(),
                o.getInt("vibration_strength"),
                o.getInt("duration")
            )
        }
    } catch (e: Exception) {
        Log.e(TAG, "재생 설정 스냅샷 읽기 실패: id=$alarmId", e)
        null
    }

    fun clearRingSnapshot(context: Context, alarmId: Int) {
        val p = prefs(context)
        val key = "$SNAPSHOT_PREFIX$alarmId"
        if (p.contains(key)) p.edit().remove(key).apply()
    }

    /** [liveIds](DB에 행이 남아 있거나 지금 울리는 알람)에 없는 스냅샷 삭제. */
    fun cleanupSnapshots(context: Context, liveIds: Set<Int>) {
        val p = prefs(context)
        val stale = p.all.keys.filter { key ->
            key.startsWith(SNAPSHOT_PREFIX) && key.removePrefix(SNAPSHOT_PREFIX).toIntOrNull()?.let { it !in liveIds } ?: true
        }
        if (stale.isNotEmpty()) {
            p.edit().apply { stale.forEach { remove(it) } }.apply()
            Log.d(TAG, "🧹 재생 설정 스냅샷 정리: $stale")
        }
    }
}
