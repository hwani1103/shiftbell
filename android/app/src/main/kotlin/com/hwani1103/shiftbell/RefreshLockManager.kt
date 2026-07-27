package com.hwani1103.shiftbell

import android.content.Context
import android.os.Build
import android.util.Log

/**
 * ⭐ Flutter ↔ Native 동시 갱신 방지 락
 *
 * 문제 배경:
 *   - Flutter가 main.dart의 onResume / refreshAlarms 메서드 콜로 갱신 시도
 *   - 동시에 Native(AlarmRefreshReceiver, AlarmGuardReceiver, CustomAlarmReceiver,
 *     AlarmActivity, AlarmOverlayService 등)가 alarm_state의 last_alarm_refresh를
 *     보고 갱신 시도 가능
 *   - 두 프로세스가 동시에 deleteAllAlarms → generate10Days 를 수행하면 race condition으로
 *     알람이 사라지거나 중복 등록될 수 있음
 *
 * 동작:
 *   - Device Protected Storage의 SharedPreferences("alarm_state")에 락 정보 저장
 *   - acquire(owner, ttlMs): 다른 owner가 가진 락이 만료되지 않았으면 false
 *   - release(owner): 본인이 보유한 락만 해제 (다른 owner의 락은 절대 삭제 안 함)
 *   - 만료 시간(TTL)이 지나면 누구든 다시 획득 가능 (데드락 방지)
 */
object RefreshLockManager {
    private const val TAG = "RefreshLock"
    private const val PREFS_NAME = "alarm_state"
    private const val KEY_OWNER = "refresh_lock_owner"
    private const val KEY_UNTIL = "refresh_lock_until"

    private fun prefs(context: Context) = run {
        val ctx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    @Synchronized
    fun tryAcquire(context: Context, owner: String, ttlMs: Long = 30_000L): Boolean {
        val p = prefs(context)
        val now = System.currentTimeMillis()
        val currentOwner = p.getString(KEY_OWNER, null)
        val currentUntil = p.getLong(KEY_UNTIL, 0L)

        // 만료되지 않은 다른 owner의 락 → 획득 실패
        if (currentOwner != null && currentOwner != owner && currentUntil > now) {
            Log.d(TAG, "⏭️ 락 점유 중: owner=$currentOwner (만료 ${currentUntil - now}ms 후)")
            return false
        }

        // 빈 락이거나 동일 owner이거나 만료된 락 → 획득
        p.edit()
            .putString(KEY_OWNER, owner)
            .putLong(KEY_UNTIL, now + ttlMs)
            .apply()
        Log.d(TAG, "🔒 락 획득: owner=$owner (TTL ${ttlMs}ms)")
        return true
    }

    @Synchronized
    fun release(context: Context, owner: String) {
        val p = prefs(context)
        val currentOwner = p.getString(KEY_OWNER, null)
        if (currentOwner != owner) {
            Log.d(TAG, "⚠️ 락 해제 스킵: 본인($owner) ≠ 보유자($currentOwner)")
            return
        }
        p.edit()
            .remove(KEY_OWNER)
            .remove(KEY_UNTIL)
            .apply()
        Log.d(TAG, "🔓 락 해제: owner=$owner")
    }

    /// 강제 정리 (재부팅 직후 등 디버그용)
    @Synchronized
    fun forceClear(context: Context) {
        prefs(context).edit()
            .remove(KEY_OWNER)
            .remove(KEY_UNTIL)
            .apply()
        Log.d(TAG, "🧹 락 강제 초기화")
    }
}
