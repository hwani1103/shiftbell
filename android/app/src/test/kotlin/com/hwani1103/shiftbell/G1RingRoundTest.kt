// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1RingRoundTest.kt
//
// 출시전 감사 G1 첫 묶음 재현/회귀 테스트 (docs/release_audit/g1/handoff.md)
//  - #3  울림 회차 토큰(RingingAlarmTracker) + 회차별 네이티브 종료 예약(AlarmActionReceiver.ACTION_RING_TIMEOUT)
//  - #14 앱에서 다른 알람을 삭제해도 울리는 알람을 멈추지 않음(AlarmActionHelper.isAlarmRinging/stopRingingAlarm)
//  - #23 MediaPlayer 준비 실패 시 해제(AlarmPlayer.startLoopingPlayer)
//
// 화면(AlarmActivity/AlarmOverlayService)의 홈 이동·잠금·Doze 지속시간은 여기서 못 봄 → 실기기 S4.
// DB는 AlarmRefreshEngineH2Test와 같은 최소 v24 픽스처를 헬퍼 연결로 연다(그 파일 주석 참고).
package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowMediaPlayer
import org.robolectric.shadows.util.DataSource

@RunWith(RobolectricTestRunner::class)
class G1RingRoundTest {

    private lateinit var context: Context
    private lateinit var dbHelper: DatabaseHelper

    @Before
    fun setUp() {
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
        context = ApplicationProvider.getApplicationContext()

        val deviceContext = context.createDeviceProtectedStorageContext()
        // 오늘 이미 갱신한 것으로 둬서 dismiss/수신 경로의 AlarmRefreshUtil이 비동기 갱신으로 alarms를 바꾸지 않게 함
        deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit()
            .putLong("last_alarm_refresh", System.currentTimeMillis()).commit()

        val dbFile = deviceContext.getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) java.io.File(dbFile.path + suffix).delete()
        dbFile.parentFile?.mkdirs()
        java.io.File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(dbFile, overwrite = true)
        dbHelper = DatabaseHelper.getInstance(context)
        insertAlarm(7)
        insertAlarm(8)
    }

    @After
    fun tearDown() {
        RingingAlarmTracker.resetMemoryForTest()
        DatabaseHelper.resetInstanceForTest()
    }

    private fun insertAlarm(id: Int) {
        dbHelper.writableDatabase.insert("alarms", null, ContentValues().apply {
            put("id", id)
            put("time", "07:00")
            put("date", "2026-09-14T07:00:00")
            put("type", "fixed")
            put("alarm_type_id", 1)
            put("shift_type", "주간")
            put("day_offset", 0)
        })
    }

    private fun alarmRows(id: Int): Int =
        dbHelper.writableDatabase.rawQuery("SELECT COUNT(*) FROM alarms WHERE id = ?", arrayOf(id.toString())).use {
            it.moveToFirst(); it.getInt(0)
        }

    private fun history(id: Int): List<String> =
        dbHelper.writableDatabase.rawQuery(
            "SELECT dismiss_type FROM alarm_history WHERE alarm_id = ? ORDER BY id", arrayOf(id.toString())
        ).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }

    private fun ringTimeouts(): List<Intent> {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return shadowOf(am).scheduledAlarms
            .mapNotNull { it.operation?.let { pi -> shadowOf(pi).savedIntent } }
            .filter { it.action == AlarmActionReceiver.ACTION_RING_TIMEOUT }
    }

    private fun timeoutIntent(alarmId: Int, round: Long) =
        Intent(context, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_RING_TIMEOUT
            putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
        }

    private fun alarmIntent(id: Int) = Intent(context, CustomAlarmReceiver::class.java).apply {
        putExtra(CustomAlarmReceiver.EXTRA_ID, id)
        putExtra(CustomAlarmReceiver.EXTRA_LABEL, "주간")
    }

    // ───────────────────────────── #3 회차 토큰

    @Test
    fun `#3 회차는 폐기 후에도 계속 증가하고 지난 회차 종료 요청은 새 회차를 끄지 못한다`() {
        val first = RingingAlarmTracker.startRing(context, 7)
        assertTrue(RingingAlarmTracker.endIfCurrent(context, 7, first.round))  // 스누즈로 첫 울림 종료
        val second = RingingAlarmTracker.startRing(context, 7)                 // 스누즈 후 같은 ID로 재울림

        assertTrue("회차 번호 재사용 금지", second.round > first.round)
        assertFalse("첫 회차의 늦은 종료 신호", RingingAlarmTracker.endIfCurrent(context, 7, first.round))
        assertFalse("다른 ID", RingingAlarmTracker.endIfCurrent(context, 8, second.round))
        assertEquals(second, RingingAlarmTracker.current(context))
    }

    @Test
    fun `#3 프로세스 재시작 뒤에도 저장된 회차로 이어가고 이전 버전의 ID만 있는 값은 회차 0으로 읽는다`() {
        val first = RingingAlarmTracker.startRing(context, 7)
        RingingAlarmTracker.resetMemoryForTest()
        assertEquals(first, RingingAlarmTracker.current(context))
        assertTrue(RingingAlarmTracker.startRing(context, 7).round > first.round)

        context.createDeviceProtectedStorageContext().getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
            .edit().clear().putInt("currently_ringing_alarm_id", 3).commit()
        RingingAlarmTracker.resetMemoryForTest()
        assertEquals(RingingAlarmTracker.ActiveRing(3, RingingAlarmTracker.LEGACY_ROUND), RingingAlarmTracker.current(context))
        assertEquals(1L, RingingAlarmTracker.startRing(context, 4).round)
    }

    @Test
    fun `#3 commit이 계속 실패해도 ID만 비교하지 않고 메모리 회차로 판정한다`() {
        RingingAlarmTracker.commitOverride = { false }
        val first = RingingAlarmTracker.startRing(context, 7)
        val prefs = context.createDeviceProtectedStorageContext().getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        assertFalse("주입한 실패로 실제 저장은 안 됐어야 함", prefs.contains("currently_ringing_alarm_id"))

        assertTrue(RingingAlarmTracker.endIfCurrent(context, 7, first.round))
        val second = RingingAlarmTracker.startRing(context, 7)
        assertFalse(RingingAlarmTracker.endIfCurrent(context, 7, first.round))
        assertEquals(second, RingingAlarmTracker.current(context))
    }

    // ───────────────────────────── #3 네이티브 종료 예약

    @Test
    fun `#3 종료 예약은 지난 회차면 무시하고 현재 회차만 timeout 이력 1건으로 끝낸다`() {
        val first = RingingAlarmTracker.startRing(context, 7)
        AlarmActionHelper.scheduleRingTimeout(context, first, 3)
        assertTrue(AlarmActionHelper.claimRingEnd(context, 7, first.round))  // 스누즈 등으로 끝남
        assertTrue("끝난 회차의 종료 예약은 취소돼야 함", ringTimeouts().isEmpty())

        val second = RingingAlarmTracker.startRing(context, 7)
        AlarmActionHelper.scheduleRingTimeout(context, second, 3)
        val scheduled = ringTimeouts()
        assertEquals(1, scheduled.size)
        assertEquals(second.round, scheduled[0].getLongExtra(AlarmActionReceiver.EXTRA_RING_ROUND, -99))

        // 지난 회차의 종료 예약(취소가 늦었거나 이미 발송된 것)이 도착
        AlarmActionReceiver().onReceive(context, timeoutIntent(7, first.round))
        assertEquals(1, alarmRows(7))
        assertEquals(emptyList<String>(), history(7))
        assertEquals(second, RingingAlarmTracker.current(context))

        AlarmActionReceiver().onReceive(context, timeoutIntent(7, second.round))
        assertEquals(0, alarmRows(7))
        assertEquals(listOf("timeout"), history(7))
        assertNull(RingingAlarmTracker.current(context))
        assertTrue(ringTimeouts().isEmpty())

        // 화면 타이머 등 같은 회차의 두 번째 종료 신호 - 이력 중복 없음
        AlarmActionReceiver().onReceive(context, timeoutIntent(7, second.round))
        assertEquals(listOf("timeout"), history(7))
    }

    @Test
    fun `#3 회차 정보 없는 알림 끄기 요청은 울리는 알람을 끄지 않는다`() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        AlarmActionReceiver().onReceive(context, Intent(context, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_DISMISS_FROM_NOTIFICATION
            putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, 7)
        })
        assertEquals(ring, RingingAlarmTracker.current(context))
        assertEquals(1, alarmRows(7))
    }

    @Test
    fun `#3 수신 - 울리는 순간 회차 종료가 예약되고 같은 알람 중복 수신이면 이전 회차 예약을 거둬들인다`() {
        CustomAlarmReceiver().onReceive(context, alarmIntent(7))
        val first = RingingAlarmTracker.current(context)!!
        assertEquals(listOf(first.round), ringTimeouts().map { it.getLongExtra(AlarmActionReceiver.EXTRA_RING_ROUND, -99) })

        CustomAlarmReceiver().onReceive(context, alarmIntent(7))  // 재부팅 경로의 0.5초 간격 중복 수신
        val second = RingingAlarmTracker.current(context)!!
        assertEquals(7, second.alarmId)
        assertTrue(second.round > first.round)
        assertEquals(listOf(second.round), ringTimeouts().map { it.getLongExtra(AlarmActionReceiver.EXTRA_RING_ROUND, -99) })
        assertEquals("중복 수신은 인계가 아님 - 행/이력 유지", 1, alarmRows(7))
        assertEquals(emptyList<String>(), history(7))
    }

    @Test
    fun `#3 수신 - 다른 알람이 도착하면 이전 회차를 관문으로 끝내 인계 이력 1건과 새 회차 예약만 남긴다`() {
        CustomAlarmReceiver().onReceive(context, alarmIntent(7))
        CustomAlarmReceiver().onReceive(context, alarmIntent(8))

        assertEquals(0, alarmRows(7))
        assertEquals(listOf("superseded_by_next_alarm"), history(7))
        val current = RingingAlarmTracker.current(context)!!
        assertEquals(8, current.alarmId)
        assertEquals(listOf(8), ringTimeouts().map { it.getIntExtra(AlarmActionReceiver.EXTRA_ALARM_ID, -1) })
    }

    // ───────────────────────────── #14 앱에서 삭제

    @Test
    fun `#14 다른 알람을 삭제하면 울리는 알람은 그대로 - 같은 알람일 때만 울림 종료`() {
        // 진동·무음 알람도 재생기 상태와 무관하게 활성 회차로 판정(여기선 재생기를 아예 안 씀)
        val ring = RingingAlarmTracker.startRing(context, 7)
        AlarmActionHelper.scheduleRingTimeout(context, ring, 3)

        assertFalse(AlarmActionHelper.isAlarmRinging(context, 8))
        assertFalse(AlarmActionHelper.stopRingingAlarm(context, 8))
        assertEquals(ring, RingingAlarmTracker.current(context))
        assertEquals(1, ringTimeouts().size)

        assertTrue(AlarmActionHelper.isAlarmRinging(context, 7))
        assertTrue(AlarmActionHelper.stopRingingAlarm(context, 7))
        assertNull(RingingAlarmTracker.current(context))
        assertTrue(ringTimeouts().isEmpty())
        assertEquals("DB 행/이력은 Dart deleteAlarm 담당", 1, alarmRows(7))
    }

    // ───────────────────────────── #23 MediaPlayer

    @Test
    fun `#23 재생 준비가 실패한 MediaPlayer는 해제된다`() {
        val created = mutableListOf<MediaPlayer>()
        ShadowMediaPlayer.setCreateListener { player, _ -> created.add(player) }

        // 미디어 정보를 등록하지 않은 데이터 소스 → Robolectric MediaPlayer가 setDataSource에서 예외
        AlarmPlayer(context).playAlarmWithSettings("default", 0.7f, 0)

        assertEquals(1, created.size)
        assertEquals(ShadowMediaPlayer.State.END, shadowOf(created[0]).state)
    }

    @Test
    fun `#23 재생에 성공한 MediaPlayer는 유지되다가 stopAlarm에서 해제된다`() {
        val created = mutableListOf<MediaPlayer>()
        ShadowMediaPlayer.setCreateListener { player, _ -> created.add(player) }
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ShadowMediaPlayer.addMediaInfo(DataSource.toDataSource(context, uri), ShadowMediaPlayer.MediaInfo(60_000, 0))

        val player = AlarmPlayer(context)
        player.playAlarmWithSettings("default", 0.7f, 0)
        assertEquals(1, created.size)
        assertEquals(ShadowMediaPlayer.State.STARTED, shadowOf(created[0]).state)

        player.stopAlarm()
        assertEquals(ShadowMediaPlayer.State.END, shadowOf(created[0]).state)
    }
}
