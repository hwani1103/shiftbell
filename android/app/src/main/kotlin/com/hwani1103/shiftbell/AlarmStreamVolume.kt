package com.hwani1103.shiftbell

import android.content.Context
import android.media.AudioManager
import android.util.Log

/**
 * ⭐ 2026-09-15 (출시 적합성 재검토 AUD-06) - 시스템 알람 볼륨(STREAM_ALARM)을 임시로 바꾸고 되돌리는 일을 한 곳에서 관리.
 *
 * 예전엔 실제 알람(AlarmPlayer)과 설정 화면 미리듣기(MainActivity)가 각자 "원래 볼륨"을 저장하고 각자 복원했음.
 * 예: 시스템 알람 볼륨 0 → 미리듣기가 50%로 올림 → 그 사이 실제 알람 도착(50%를 원래 값으로 기억) → 미리듣기 종료가 0으로
 * 되돌려 실제 알람이 무음 → 실제 알람 종료가 50%를 "복원"해 사용자 설정까지 바뀜.
 *
 * 이제 사용 주체(holder)마다 [acquire]/[release]하고, **첫 주체가 잡을 때만** 원래 볼륨을 저장하고
 * **마지막 주체가 놓을 때만** 복원함. 같은 주체의 중복 acquire(겹쳐 울리는 알람)는 원래 값을 덮어쓰지 않음.
 * 프로세스가 강제로 죽으면 복원되지 않는 한계는 그대로(onDestroy·finally가 안 불림).
 */
object AlarmStreamVolume {
    private const val TAG = "AlarmStreamVolume"
    const val HOLDER_ALARM = "alarm"
    const val HOLDER_PREVIEW = "preview"

    private val lock = Any()
    private val holders = HashSet<String>()
    private var originalVolume = -1

    /** [holder]로 알람 스트림을 잡고 볼륨을 최대의 50%(최소 1단계)로 맞춤. */
    fun acquire(context: Context, holder: String) = synchronized(lock) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (holders.isEmpty()) {
            originalVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            Log.d(TAG, "📊 원래 시스템 알람 볼륨 저장: $originalVolume (by $holder)")
        } else {
            Log.d(TAG, "📊 이미 저장된 원래 볼륨 유지: $originalVolume (보유=$holders, 추가=$holder)")
        }
        holders.add(holder)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        // 정수 나눗셈이라 최대 1단계 기기에서 0(무음)이 되지 않게 최소 1단계 보장(2026-09-04)
        val halfVolume = (maxVolume / 2).coerceAtLeast(1)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, halfVolume, 0)
        Log.d(TAG, "🔊 시스템 알람 볼륨 임시 변경: $halfVolume (by $holder)")
    }

    /** [holder]를 놓음. 남은 주체가 없을 때만 원래 볼륨으로 복원. 잡지 않은 주체의 release는 아무것도 안 함. */
    fun release(context: Context, holder: String) = synchronized(lock) {
        if (!holders.remove(holder)) return@synchronized
        if (holders.isNotEmpty()) {
            Log.d(TAG, "⏸️ $holder 해제 - 다른 사용 중($holders)이라 볼륨 유지")
            return@synchronized
        }
        if (originalVolume == -1) return@synchronized
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, originalVolume, 0)
            Log.d(TAG, "🔄 시스템 알람 볼륨 복원: $originalVolume (by $holder)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 볼륨 복원 실패", e)
        } finally {
            originalVolume = -1
        }
    }

    /** 테스트 전용 - 프로세스 재시작처럼 메모리 상태를 버림. */
    internal fun resetForTest() = synchronized(lock) {
        holders.clear()
        originalVolume = -1
    }
}
