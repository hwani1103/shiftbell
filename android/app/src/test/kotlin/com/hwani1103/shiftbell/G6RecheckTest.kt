// android/app/src/test/kotlin/com/hwani1103/shiftbell/G6RecheckTest.kt
//
// 출시 적합성 재검토(docs/release_audit/g6/recheck_2026_09_15/release_readiness_review.md) 반영분 회귀 테스트
//  - AUD-02 복원 뒤 재시작의 프로세스 종료는 이 프로세스에 살아 있는 울림이 없을 때만 실행(확인과 실행을 같은 lock 안에서)
//  - AUD-03 울림 지속시간은 복원 전 설정 스냅샷이 DB보다 우선(오버레이도 같은 함수 사용)
//  - AUD-06 미리듣기와 실제 알람이 시스템 알람 볼륨을 같이 잡아도 마지막 주체가 놓을 때만 원래 볼륨으로 복원
package com.hwani1103.shiftbell

import android.content.Context
import android.media.AudioManager
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class G6RecheckTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        RingingAlarmTracker.resetMemoryForTest()
        AlarmStreamVolume.resetForTest()
        context = ApplicationProvider.getApplicationContext()
        dp("alarm_state").edit().clear().commit()
        dp("restore_state").edit().clear().commit()
    }

    private fun dp(name: String) = (
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
    ).getSharedPreferences(name, Context.MODE_PRIVATE)

    // ── AUD-02 ─────────────────────────────────────────────

    @Test
    fun restartRunsOnlyWhenNoLiveRingInThisProcess() {
        var exits = 0
        assertTrue(RingingAlarmTracker.runIfNoLiveRing(context) { exits++ })
        assertEquals(1, exits)

        // 재시작 요청을 받아들인 뒤 ~ 종료 직전 사이에 새 알람이 울리기 시작함
        val ring = RingingAlarmTracker.startRing(context, 42)
        assertFalse("울리는 중에는 종료하지 않음", RingingAlarmTracker.runIfNoLiveRing(context) { exits++ })
        assertEquals(1, exits)

        // 끄기·스누즈·자동 종료로 울림이 끝나면 재시도에서 종료
        assertTrue(RingingAlarmTracker.endIfCurrent(context, 42, ring.round))
        assertTrue(RingingAlarmTracker.runIfNoLiveRing(context) { exits++ })
        assertEquals(2, exits)
    }

    @Test
    fun activeRingLoadedFromPreviousProcessDoesNotBlockRestart() {
        // 이전 프로세스가 남긴 활성 울림 기록(소리는 이미 멈춤) - 재시작을 영원히 막으면 안 됨
        dp("alarm_state").edit().putInt("currently_ringing_alarm_id", 5).putLong("currently_ringing_round", 3L).commit()
        var exits = 0
        assertTrue(RingingAlarmTracker.runIfNoLiveRing(context) { exits++ })
        assertEquals(1, exits)
    }

    // ── AUD-03 ─────────────────────────────────────────────

    @Test
    fun ringDurationPrefersRestoreSnapshotOverDb() {
        assertEquals("스냅샷·DB 둘 다 없으면 기본 3분", 3, CustomAlarmReceiver.ringDurationMinutes(context, 77))

        assertTrue(RestoreGate.saveRingSnapshotIfAbsent(
            context, 77, RestoreGate.RingSnapshot("alarmbell1", 0.7f, 2, 10)
        ))
        assertEquals("스누즈 대기 중 복원: 복원 전 지속시간(10분) 유지", 10, CustomAlarmReceiver.ringDurationMinutes(context, 77))
    }

    // ── AUD-06 ─────────────────────────────────────────────

    private val audio get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private fun alarmVolume() = audio.getStreamVolume(AudioManager.STREAM_ALARM)
    private fun half() = (audio.getStreamMaxVolume(AudioManager.STREAM_ALARM) / 2).coerceAtLeast(1)

    @Test
    fun previewEndingDuringRealAlarmDoesNotRestoreUntilAlarmEnds() {
        audio.setStreamVolume(AudioManager.STREAM_ALARM, 0, 0)

        AlarmStreamVolume.acquire(context, AlarmStreamVolume.HOLDER_PREVIEW)  // 미리듣기 50%
        assertEquals(half(), alarmVolume())
        AlarmStreamVolume.acquire(context, AlarmStreamVolume.HOLDER_ALARM)    // 그 사이 실제 알람 도착

        AlarmStreamVolume.release(context, AlarmStreamVolume.HOLDER_PREVIEW)  // 미리듣기 종료
        assertEquals("실제 알람이 울리는 동안 무음으로 되돌리지 않음", half(), alarmVolume())

        AlarmStreamVolume.release(context, AlarmStreamVolume.HOLDER_ALARM)    // 실제 알람 종료
        assertEquals("사용자의 원래 볼륨(0)으로 복원 - 50%가 남지 않음", 0, alarmVolume())
    }

    @Test
    fun overlappingAlarmAcquireKeepsFirstOriginalVolume() {
        audio.setStreamVolume(AudioManager.STREAM_ALARM, 1, 0)

        AlarmStreamVolume.acquire(context, AlarmStreamVolume.HOLDER_ALARM)
        AlarmStreamVolume.acquire(context, AlarmStreamVolume.HOLDER_ALARM)  // 겹쳐 울리는 알람 - 50%를 원래 값으로 덮어쓰면 안 됨
        AlarmStreamVolume.release(context, AlarmStreamVolume.HOLDER_PREVIEW) // 잡지 않은 주체의 해제는 무시
        assertEquals(half(), alarmVolume())

        AlarmStreamVolume.release(context, AlarmStreamVolume.HOLDER_ALARM)
        assertEquals(1, alarmVolume())
    }
}
