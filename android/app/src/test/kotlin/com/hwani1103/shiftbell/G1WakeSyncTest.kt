// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1WakeSyncTest.kt
//
// 출시전 감사 G1 #16/#27 - 기상 알람 DB/OS 반영 순서와 경합 (docs/release_audit/g1/handoff.md)
//  - 수신 시 예정 시각 정확 대조(CustomAlarmReceiver → AlarmWakeScheduler.decideOnReceive)
//  - 반영 직전 재확인(예약: 행+시각 일치일 때만 / 취소: 행 없으면 항상, 있으면 DB 시각 재예약)
//  - OS 반영 실패 기록과 DB 기준 재시도
//  - 재부팅 경로(DirectBootReceiver)도 같은 PendingIntent라 같은 알람이 두 번 예약되지 않음
// 엔진 트랜잭션(읽기가 잠금 안, OS는 커밋 뒤)은 AlarmRefreshEngineH2Test.
// 수신 이벤트 자체의 지연·누락, Doze·하트비트 지연은 여기서 못 봄 → 실기기 S8·S13.
package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class G1WakeSyncTest {

    private lateinit var context: Context
    private lateinit var dbHelper: DatabaseHelper
    private val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())

    /** 초 단위로 맞춘 now 기준 시각 (DB 문자열이 초까지만 담으므로) */
    private fun at(offsetMillis: Long): Long {
        val t = System.currentTimeMillis() + offsetMillis
        return t - t % 1000
    }

    @Before
    fun setUp() {
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
        context = ApplicationProvider.getApplicationContext()
        val deviceContext = context.createDeviceProtectedStorageContext()
        deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit()
            .putLong("last_alarm_refresh", System.currentTimeMillis()).commit()
        val dbFile = deviceContext.getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) java.io.File(dbFile.path + suffix).delete()
        dbFile.parentFile?.mkdirs()
        java.io.File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(dbFile, overwrite = true)
        dbHelper = DatabaseHelper.getInstance(context)
    }

    @After
    fun tearDown() {
        RingingAlarmTracker.resetMemoryForTest()
        DatabaseHelper.resetInstanceForTest()
    }

    private fun insertAlarm(id: Int, timestamp: Long) {
        dbHelper.writableDatabase.insert("alarms", null, ContentValues().apply {
            put("id", id)
            put("time", SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp)))
            put("date", format.format(Date(timestamp)))
            put("type", "fixed")
            put("alarm_type_id", 1)
            put("shift_type", "주간")
            put("day_offset", 0)
        })
    }

    /** 이 알람 ID로 OS에 걸린 기상 알람들의 울림 시각 */
    private fun wakeTimes(id: Int): List<Long> {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return shadowOf(am).scheduledAlarms
            .filter { alarm ->
                val intent = alarm.operation?.let { shadowOf(it).savedIntent }
                intent?.component?.className == CustomAlarmReceiver::class.java.name &&
                    intent.data?.toString() == "shiftbell://alarm/$id"
            }
            .map { it.triggerAtMs }
    }

    private fun receive(id: Int, expectedAt: Long?) {
        CustomAlarmReceiver().onReceive(context, Intent(context, CustomAlarmReceiver::class.java).apply {
            putExtra(CustomAlarmReceiver.EXTRA_ID, id)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, "주간")
            if (expectedAt != null) putExtra(AlarmWakeScheduler.EXTRA_EXPECTED_AT, expectedAt)
        })
    }

    // ───────────────────────────── 수신 시 예정 시각 대조

    @Test
    fun `#27 수신 - DB에 행이 없으면 울리지 않는다`() {
        receive(99, at(0))
        assertNull(RingingAlarmTracker.current(context))
    }

    @Test
    fun `#27 수신 - 예정 시각이 DB 행과 같으면 울린다`() {
        val t = at(-1_000)
        insertAlarm(7, t)
        receive(7, t)
        assertEquals(7, RingingAlarmTracker.current(context)?.alarmId)
    }

    @Test
    fun `#27 수신 - 옛 예약이 늦게 도착했고 DB 시각이 미래면 울리지 않고 DB 시각으로 재예약한다`() {
        val dbTime = at(2 * 3_600_000L)
        insertAlarm(7, dbTime)
        receive(7, at(-60_000))  // 사용자가 알람 시각을 바꾸기 전의 옛 예약
        assertNull("앞당겨 울리면 안 됨", RingingAlarmTracker.current(context))
        assertEquals(listOf(dbTime), wakeTimes(7))
    }

    @Test
    fun `#27 수신 - 예정 시각이 달라도 DB 시각이 이미 지났으면 늦게라도 울린다`() {
        insertAlarm(7, at(-5 * 60_000L))
        receive(7, at(-10 * 60_000L))
        assertEquals(7, RingingAlarmTracker.current(context)?.alarmId)
    }

    @Test
    fun `#27 수신 - 예정 시각 extra가 없는 수정 이전 예약은 행이 있으면 울린다`() {
        insertAlarm(7, at(2 * 3_600_000L))
        receive(7, null)
        assertEquals(7, RingingAlarmTracker.current(context)?.alarmId)
    }

    // ───────────────────────────── 반영 직전 재확인

    @Test
    fun `#27 예약 재확인 - 행이 없거나 시각이 바뀌었으면 버리고 같을 때만 예약한다`() {
        val t = at(3_600_000L)
        insertAlarm(7, t)
        val db = dbHelper.writableDatabase

        assertEquals(AlarmWakeScheduler.Outcome.SKIPPED_STALE, AlarmWakeScheduler.scheduleIfCurrent(context, db, 99, t, "주간"))
        assertEquals(AlarmWakeScheduler.Outcome.SKIPPED_STALE, AlarmWakeScheduler.scheduleIfCurrent(context, db, 7, t + 60_000, "주간"))
        assertTrue(wakeTimes(7).isEmpty())

        assertEquals(AlarmWakeScheduler.Outcome.SCHEDULED, AlarmWakeScheduler.scheduleIfCurrent(context, db, 7, t, "주간"))
        assertEquals(listOf(t), wakeTimes(7))
    }

    @Test
    fun `#27 취소 재확인 - 행이 없으면 항상 취소하고 행이 남아 있으면 DB 시각으로 재예약한다`() {
        val db = dbHelper.writableDatabase
        AlarmWakeScheduler.scheduleRaw(context, 99, at(3_600_000L), "주간")
        assertEquals(AlarmWakeScheduler.Outcome.CANCELLED, AlarmWakeScheduler.cancelIfGone(context, db, 99))
        assertTrue(wakeTimes(99).isEmpty())

        val dbTime = at(2 * 3_600_000L)
        insertAlarm(7, dbTime)  // 같은 ID를 스누즈가 다시 쓰는 경우 등
        AlarmWakeScheduler.scheduleRaw(context, 7, at(3_600_000L), "주간")
        assertEquals(AlarmWakeScheduler.Outcome.SCHEDULED, AlarmWakeScheduler.cancelIfGone(context, db, 7))
        assertEquals(listOf(dbTime), wakeTimes(7))
    }

    // ───────────────────────────── 실패 기록·재시도

    @Test
    fun `#27 OS 예약 실패는 기록되고 다음 재시도에서 DB 기준으로 예약된 뒤 기록이 지워진다`() {
        val t = at(3_600_000L)
        insertAlarm(7, t)
        val db = dbHelper.writableDatabase

        val outcome = AlarmWakeScheduler.scheduleIfCurrent(context, db, 7, t, "주간") { _, _, _, _ ->
            throw SecurityException("exact alarm denied")
        }
        assertEquals(AlarmWakeScheduler.Outcome.FAILED, outcome)
        assertEquals(setOf(7), AlarmWakeScheduler.failedIds(context))
        assertTrue(wakeTimes(7).isEmpty())

        AlarmWakeScheduler.retryFailed(context)
        assertEquals(listOf(t), wakeTimes(7))
        assertTrue(AlarmWakeScheduler.failedIds(context).isEmpty())
    }

    // ───────────────────────────── 예약 경로 동일성

    @Test
    fun `#27 재부팅 경로와 다른 경로가 같은 알람을 예약해도 OS 예약은 하나다(재부팅 중복 수신 재현)`() {
        val t = at(3_600_000L)
        insertAlarm(7, t)

        // 엔진·MainActivity·Guard가 쓰는 경로로 먼저 예약된 상태에서 재부팅 경로가 같은 알람을 다시 예약
        // (수정 전 DirectBootReceiver는 setPackage()가 들어간 다른 PendingIntent를 만들어 예약이 2개가 됐음)
        AlarmWakeScheduler.scheduleRaw(context, 7, t, "주간")
        DirectBootReceiver().onReceive(context, Intent(Intent.ACTION_LOCKED_BOOT_COMPLETED))
        assertNotNull("재부팅 경로가 가장 가까운 알람을 예약했어야 함", wakeTimes(7).firstOrNull())
        assertEquals(listOf(t), wakeTimes(7))
    }
}
