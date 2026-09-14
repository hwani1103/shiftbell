// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1ScheduleNotifyTest.kt
//
// 출시전 감사 G1 #5 / #10 / V6 (docs/release_audit/g1/handoff.md)
//  - #5 일정 알림 수신 시 DB 재판정(행·notify_enabled·탭 사용·예정 시각 정확 비교), DB 내용 표시, 옛 시각 예약은 재예약
//  - #5 탭 숨김 상태는 재부팅 재예약·신규 예약 안 함, 앱 시작 동기화
//  - #10 시간대 변경 시 Guard가 일정 알림을 DB 기준으로 다시 걸고 지난 일정의 옛 예약은 지움
//  - V6 앱 업데이트·정확한 알람 권한 재허용 수신 시 기상 알람 실패 목록·일정 알림 재조정
// Manifest intent-filter(BOOT_COMPLETED/MY_PACKAGE_REPLACED/권한 변경)는 연결 요청 - 여기선 onReceive를 직접 호출.
package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class G1ScheduleNotifyTest {

    private lateinit var context: Context
    private lateinit var dbHelper: DatabaseHelper

    @Before
    fun setUp() {
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
        context = ApplicationProvider.getApplicationContext()
        val deviceContext = context.createDeviceProtectedStorageContext()
        deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit()
            .clear().putLong("last_alarm_refresh", System.currentTimeMillis()).commit()
        val dbFile = deviceContext.getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) File(dbFile.path + suffix).delete()
        dbFile.parentFile?.mkdirs()
        File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(dbFile, overwrite = true)
        dbHelper = DatabaseHelper.getInstance(context)
    }

    @After
    fun tearDown() {
        RingingAlarmTracker.resetMemoryForTest()
        DatabaseHelper.resetInstanceForTest()
    }

    private fun dayKey(daysFromToday: Int): String = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        .format(Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, daysFromToday) }.time)

    private fun insertSchedule(id: Int, date: String, start: Int, content: String, notify: Boolean = true, offset: Int = 0) {
        dbHelper.writableDatabase.insert("date_schedules", null, ContentValues().apply {
            put("id", id)
            put("date", date)
            put("content", content)
            put("start_minutes", start)
            put("duration_minutes", 30)
            put("notify_enabled", if (notify) 1 else 0)
            put("notify_offset_minutes", offset)
            put("created_at", "2026-09-14T00:00:00")
        })
    }

    private fun trigger(date: String, start: Int, offset: Int = 0) =
        ScheduleNotificationScheduler.triggerMillisFor(date, start, offset)!!

    private fun receiveIntent(id: Int, expectedAt: Long?, oldContent: String = "옛 내용") =
        Intent(context, ScheduleNotificationReceiver::class.java).apply {
            putExtra(ScheduleNotificationReceiver.EXTRA_ID, id)
            putExtra(ScheduleNotificationReceiver.EXTRA_DATE, "2000-01-01")
            putExtra(ScheduleNotificationReceiver.EXTRA_START_MINUTES, 1)
            putExtra(ScheduleNotificationReceiver.EXTRA_CONTENT, oldContent)
            if (expectedAt != null) putExtra(ScheduleNotificationScheduler.EXTRA_EXPECTED_AT, expectedAt)
        }

    private fun shown(id: Int): Notification? {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return shadowOf(nm).getNotification(id + ScheduleNotificationScheduler.REQUEST_CODE_OFFSET)
    }

    private fun scheduleTimes(id: Int): List<Long> {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return shadowOf(am).scheduledAlarms
            .filter { it.operation?.let { pi -> shadowOf(pi).savedIntent.data?.toString() } == "shiftbell://schedule_notify/$id" }
            .map { it.triggerAtMs }
    }

    private fun wakeTimes(id: Int): List<Long> {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return shadowOf(am).scheduledAlarms
            .filter { it.operation?.let { pi -> shadowOf(pi).savedIntent.data?.toString() } == "shiftbell://alarm/$id" }
            .map { it.triggerAtMs }
    }

    // ───────────────────────────── #5 수신 판정

    @Test
    fun `#5 예정 시각이 DB와 같으면 Intent의 옛 내용이 아니라 DB 내용으로 표시한다`() {
        val date = dayKey(0)
        insertSchedule(1, date, 60, "새 내용")

        ScheduleNotificationReceiver().onReceive(context, receiveIntent(1, trigger(date, 60)))

        val n = shown(1)!!
        assertEquals("새 내용", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
    }

    @Test
    fun `#5 행이 없거나 알림이 꺼졌거나 탭을 숨겼으면 표시하지 않는다`() {
        val date = dayKey(0)
        ScheduleNotificationReceiver().onReceive(context, receiveIntent(1, trigger(date, 60)))  // 행 없음
        assertNull(shown(1))

        insertSchedule(2, date, 60, "알림 끔", notify = false)
        ScheduleNotificationReceiver().onReceive(context, receiveIntent(2, trigger(date, 60)))
        assertNull(shown(2))

        insertSchedule(3, date, 60, "탭 숨김")
        ScheduleNotificationScheduler.setTabEnabled(context, false)
        ScheduleNotificationReceiver().onReceive(context, receiveIntent(3, trigger(date, 60)))
        assertNull(shown(3))
    }

    @Test
    fun `#5 같은 일정의 시각을 바꾼 뒤 옛 예약이 오면 표시하지 않고 새 시각으로 다시 예약한다`() {
        val date = dayKey(2)
        insertSchedule(4, date, 600, "시각 변경됨")

        ScheduleNotificationReceiver().onReceive(context, receiveIntent(4, trigger(date, 540)))

        assertNull(shown(4))
        assertEquals(listOf(trigger(date, 600)), scheduleTimes(4))
    }

    @Test
    fun `T11-02 예정 시각 extra가 없는 옛 예약은 DB 트리거가 지났어도 표시하지 않는다`() {
        val date = dayKey(-1)
        insertSchedule(40, date, 480, "변경 뒤 DB 내용")

        ScheduleNotificationReceiver().onReceive(context, receiveIntent(40, null))

        // 수정 전 기대 결과: FAIL - legacy 경로가 trigger <= now만 보고 stale 예약을 표시함.
        // 수정 후 기대 결과: PASS - 예약 시각을 DB와 정확히 대조할 수 없으므로 fail-closed.
        assertNull(shown(40))
    }

    // ───────────────────────────── #5 탭 숨김·동기화

    @Test
    fun `#5 탭을 숨긴 상태면 재부팅 재예약과 신규 예약이 아무것도 걸지 않는다`() {
        val date = dayKey(2)
        insertSchedule(5, date, 600, "숨김")
        ScheduleNotificationScheduler.setTabEnabled(context, false)

        ScheduleNotificationScheduler.rescheduleAllFromDb(context)
        DirectBootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertTrue(ScheduleNotificationScheduler.schedule(context, 5, trigger(date, 600), date, 600, "숨김", 30))

        assertTrue(scheduleTimes(5).isEmpty())
    }

    @Test
    fun `#5 앱 시작 동기화 - 값이 바뀔 때만 예약을 거두거나 되살린다`() {
        val date = dayKey(2)
        insertSchedule(6, date, 600, "동기화")
        ScheduleNotificationScheduler.rescheduleAllFromDb(context)
        assertEquals(1, scheduleTimes(6).size)

        ScheduleNotificationScheduler.syncTabEnabled(context, false)
        assertTrue(scheduleTimes(6).isEmpty())

        ScheduleNotificationScheduler.syncTabEnabled(context, true)
        assertEquals(listOf(trigger(date, 600)), scheduleTimes(6))
    }

    // ───────────────────────────── #10 시간대 변경

    @Test
    fun `#10 시간대 변경 수신 시 일정 알림을 DB 기준으로 다시 걸고 지난 일정의 옛 예약은 지운다`() {
        val future = dayKey(2)
        val past = dayKey(-2)
        insertSchedule(7, future, 600, "미래")
        insertSchedule(8, past, 600, "지난 일정")
        // 옛 시간대에서 걸어둔 예약이 남아 있다고 가정
        ScheduleNotificationScheduler.schedule(context, 7, trigger(future, 600) - 3_600_000L, future, 600, "미래", 30)
        ScheduleNotificationScheduler.schedule(context, 8, System.currentTimeMillis() + 3_600_000L, past, 600, "지난 일정", 30)

        AlarmGuardReceiver().onReceive(context, Intent(Intent.ACTION_TIMEZONE_CHANGED))

        assertEquals(listOf(trigger(future, 600)), scheduleTimes(7))
        assertTrue("지난 일정의 옛 예약은 지워져야 함", scheduleTimes(8).isEmpty())
    }

    // ───────────────────────────── V6

    private fun seedFailedWakeAlarm(id: Int): Long {
        val t = System.currentTimeMillis() + 3 * 3_600_000L
        val at = t - t % 1000
        dbHelper.writableDatabase.insert("alarms", null, ContentValues().apply {
            put("id", id)
            put("time", "07:00")
            put("date", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(java.util.Date(at)))
            put("type", "custom")
            put("alarm_type_id", 1)
            put("day_offset", 0)
        })
        AlarmWakeScheduler.recordFailure(context, id)
        return at
    }

    @Test
    fun `V6 앱 업데이트 수신 시 기상 알람 실패 목록과 일정 알림을 다시 맞춘다`() {
        val at = seedFailedWakeAlarm(21)
        val date = dayKey(2)
        insertSchedule(9, date, 600, "업데이트 후")

        DirectBootReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        assertEquals(listOf(at), wakeTimes(21))
        assertTrue(AlarmWakeScheduler.failedIds(context).isEmpty())
        assertEquals(listOf(trigger(date, 600)), scheduleTimes(9))
    }

    @Test
    fun `V6 정확한 알람 권한 상태 변경 - 허용이 아니면 재조정하지 않고 허용이면 같은 재조정을 한다`() {
        val at = seedFailedWakeAlarm(22)
        val date = dayKey(2)
        insertSchedule(10, date, 600, "권한 재허용")
        val permissionChanged = Intent(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)

        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        DirectBootReceiver().onReceive(context, permissionChanged)
        assertTrue("권한이 없으면 재조정 안 함", wakeTimes(22).isEmpty())
        assertEquals(setOf(22), AlarmWakeScheduler.failedIds(context))

        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        DirectBootReceiver().onReceive(context, permissionChanged)

        assertEquals(listOf(at), wakeTimes(22))
        assertEquals(listOf(trigger(date, 600)), scheduleTimes(10))
    }
}
