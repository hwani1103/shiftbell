// android/app/src/test/kotlin/com/hwani1103/shiftbell/G6CrossReviewTest.kt
//
// 출시전 교차 검토(docs/release_audit/g6/codex_prerelease_diff_review.md) 반영분 회귀 테스트
//  - X-12 회차 없는 옛 제어 Intent는 옛 버전이 남긴 같은 ID의 활성 울림(LEGACY_ROUND)에만 매핑, 새 회차에는 매핑 안 함
//  - X-03 저장값에서 읽어 온 활성 울림은 "이 프로세스의 살아 있는 울림"이 아님(복원 뒤 재시작 대기 판단)
//  - X-04 종료 관문 통과 ~ 끄기/스누즈 DB 반영 완료 사이의 알람 ID를 복원 이월 대상으로 보고, 각 전이마다 epoch 증가
//  - X-04 재생 설정 스냅샷이 이미 있으면 "확보됨"(true) - 저장 실패만 false
package com.hwani1103.shiftbell

import android.content.Context
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class G6CrossReviewTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        RingingAlarmTracker.resetMemoryForTest()
        context = ApplicationProvider.getApplicationContext()
        dp("alarm_state").edit().clear().commit()
        dp("restore_state").edit().clear().commit()
    }

    private fun dp(name: String) = (
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
    ).getSharedPreferences(name, Context.MODE_PRIVATE)

    @Test
    fun legacyIntentWithoutRoundMapsOnlyToLegacyActiveRingOfSameId() {
        // 1.0.22가 울리는 중에 업데이트됨: ID만 저장돼 있음(회차 없음)
        dp("alarm_state").edit().putInt("currently_ringing_alarm_id", 5).commit()

        assertEquals(RingingAlarmTracker.LEGACY_ROUND,
            RingingAlarmTracker.normalizeRound(context, 5, RingingAlarmTracker.NO_ROUND))
        assertEquals("다른 ID에는 매핑 안 함", RingingAlarmTracker.NO_ROUND,
            RingingAlarmTracker.normalizeRound(context, 6, RingingAlarmTracker.NO_ROUND))
        assertFalse("저장값에서 읽은 울림은 이 프로세스의 살아 있는 울림이 아님", RingingAlarmTracker.isLiveRing(context))
        assertTrue("옛 제어 알림의 끄기가 옛 울림을 끝낼 수 있음",
            RingingAlarmTracker.endIfCurrent(context, 5, RingingAlarmTracker.normalizeRound(context, 5, RingingAlarmTracker.NO_ROUND)))
        assertNull(RingingAlarmTracker.current(context))
    }

    @Test
    fun intentWithoutRoundNeverMapsToNewRound() {
        val ring = RingingAlarmTracker.startRing(context, 7)

        assertEquals(RingingAlarmTracker.NO_ROUND,
            RingingAlarmTracker.normalizeRound(context, 7, RingingAlarmTracker.NO_ROUND))
        assertTrue(RingingAlarmTracker.isLiveRing(context))
        assertFalse(RingingAlarmTracker.endIfCurrent(context, 7, RingingAlarmTracker.NO_ROUND))
        assertTrue(RingingAlarmTracker.endIfCurrent(context, 7, ring.round))
        assertFalse(RingingAlarmTracker.isLiveRing(context))
    }

    @Test
    fun carryStateKeepsEndingIdUntilTransitionFinishes() {
        val before = RingingAlarmTracker.carryState(context).epoch
        val ring = RingingAlarmTracker.startRing(context, 9)
        val ringing = RingingAlarmTracker.carryState(context)
        assertEquals(9, ringing.active?.alarmId)
        assertTrue("울림 시작마다 epoch 증가", ringing.epoch > before)

        assertTrue(RingingAlarmTracker.endIfCurrent(context, 9, ring.round))  // 스누즈 버튼: 관문 통과, DB 반영 전
        val ending = RingingAlarmTracker.carryState(context)
        assertNull(ending.active)
        assertEquals(setOf(9), ending.endingIds)
        assertTrue(ending.epoch > ringing.epoch)

        RingingAlarmTracker.finishTransition(9)  // 스누즈 DB 반영 끝
        val done = RingingAlarmTracker.carryState(context)
        assertTrue(done.endingIds.isEmpty())
        assertTrue(done.epoch > ending.epoch)
    }

    @Test
    fun ringSnapshotSaveReportsSecuredWhenAlreadyPresent() {
        val first = RestoreGate.RingSnapshot("alarmbell1", 0.5f, 2, 3)
        assertTrue(RestoreGate.saveRingSnapshotIfAbsent(context, 11, first))
        assertTrue("이미 있으면 확보된 것으로 봄", RestoreGate.saveRingSnapshotIfAbsent(context, 11, first.copy(volume = 0.9f)))
        assertEquals("첫 스냅샷(복원 전 값)을 덮어쓰지 않음", 0.5f, RestoreGate.ringSnapshot(context, 11)!!.volume, 0.001f)
    }
}
