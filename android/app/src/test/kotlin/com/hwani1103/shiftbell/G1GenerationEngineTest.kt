// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1GenerationEngineTest.kt
//
// 출시전 감사 G1 #26(P1)/#31/D11 - AlarmRefreshEngine.doRefresh()를 실제 DB(최소 v24 픽스처 + repair로 생긴
// alarm_overrides) 위에서 T11a fixture(test/release_audit/g1/fixtures/*.json) 케이스로 실행:
// 템플릿 0개 정리 + custom·snoozed·울리는 알람 보호 / 템플릿 조회 실패 전파·무변경 / 멱등 / 불규칙 창 밖 배정 기여 /
// D11 30일 정리(이력 불변) / P1 정책 버전(성공 뒤 기록·낮으면 강제 갱신 트리거).
// OS 예약은 스텁(scheduleNativeAlarmOverride) - 실제 반영 규칙은 G1WakeSyncTest.
package com.hwani1103.shiftbell

import android.app.Application
import android.content.ContentValues
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class G1GenerationEngineTest {

    private lateinit var context: Context
    private lateinit var dbHelper: DatabaseHelper
    private lateinit var originalTz: TimeZone
    private val noopSchedule: (Context, Int, Long, String) -> Unit = { _, _, _, _ -> }

    @Before
    fun setUp() {
        originalTz = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"))
        DatabaseHelper.resetInstanceForTest()
        RingingAlarmTracker.resetMemoryForTest()
        context = ApplicationProvider.getApplicationContext()
        val deviceContext = context.createDeviceProtectedStorageContext()
        deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit().clear().commit()
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
        TimeZone.setDefault(originalTz)
    }

    private val db get() = dbHelper.writableDatabase
    private fun millis(s: String) = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).parse(s)!!.time

    private fun case(file: String, id: String): JSONObject {
        val cases = JSONObject(File(G0TestSupport.repoRoot, "test/release_audit/g1/fixtures/$file").readText(Charsets.UTF_8))
            .getJSONArray("cases")
        return (0 until cases.length()).map { cases.getJSONObject(it) }.first { it.getString("id") == id }
    }

    private fun seedSchedule(schedule: JSONObject) {
        db.insert("shift_schedule", null, ContentValues().apply {
            if (schedule.getString("mode") == "regular") {
                put("is_regular", 1)
                val p = schedule.getJSONArray("pattern")
                put("pattern", (0 until p.length()).joinToString(",") { p.getString(it) })
                put("today_index", schedule.getInt("today_index"))
                put("start_date", schedule.getString("start_date") + "T00:00:00")
            } else {
                put("is_regular", 0)
            }
            put("assigned_dates", schedule.optJSONObject("assigned_dates")?.toString())
        })
    }

    private fun seedTemplates(case: JSONObject) {
        val arr = case.optJSONArray("templates") ?: return
        for (i in 0 until arr.length()) {
            val t = arr.getJSONObject(i)
            db.insert("shift_alarm_templates", null, ContentValues().apply {
                put("shift_type", t.getString("shift_type"))
                put("time", t.getString("time"))
                put("alarm_type_id", t.getInt("alarm_type_id"))
                put("day_offset", t.getInt("day_offset"))
            })
        }
    }

    private fun seedRows(case: JSONObject) {
        val arr = case.getJSONArray("existing_alarm_rows")
        for (i in 0 until arr.length()) {
            val r = arr.getJSONObject(i)
            db.insert("alarms", null, ContentValues().apply {
                put("id", r.getInt("id"))
                put("time", r.getString("time"))
                put("date", r.getString("slot_time"))
                put("type", r.getString("type"))
                put("alarm_type_id", r.getInt("alarm_type_id"))
                if (r.isNull("shift_type")) putNull("shift_type") else put("shift_type", r.getString("shift_type"))
                put("day_offset", r.getInt("day_offset"))
            })
        }
    }

    private fun seedOverrides(arr: org.json.JSONArray) {
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            db.insert("alarm_overrides", null, ContentValues().apply {
                put("id", o.getInt("id"))
                put("slot_time", o.getString("slot_time"))
                put("shift_type", o.getString("shift_type"))
                put("day_offset", o.getInt("day_offset"))
                put("action", o.getString("action"))
                if (o.isNull("alarm_type_id")) putNull("alarm_type_id") else put("alarm_type_id", o.getInt("alarm_type_id"))
                put("origin_date", o.getString("origin_date"))
                put("origin_shift", o.getString("origin_shift"))
                put("created_at", "2026-09-01T00:00:00")
            })
        }
    }

    private fun ids(table: String): List<Int> = db.rawQuery("SELECT id FROM $table ORDER BY id", null).use { c ->
        buildList { while (c.moveToNext()) add(c.getInt(0)) }
    }

    private fun count(table: String): Int = db.rawQuery("SELECT COUNT(*) FROM $table", null).use { it.moveToFirst(); it.getInt(0) }

    private fun slots(): List<String> =
        db.rawQuery("SELECT date, shift_type, day_offset, alarm_type_id FROM alarms WHERE type = 'fixed' ORDER BY date", null).use { c ->
            buildList { while (c.moveToNext()) add("${c.getString(0)}|${c.getString(1)}|${c.getInt(2)}|type=${c.getInt(3)}") }
        }

    private fun policyVersion() = context.createDeviceProtectedStorageContext()
        .getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        .getInt(AlarmRefreshEngine.KEY_REFRESH_POLICY_VERSION, 0)

    @Test
    fun `#26 템플릿 0개면 옛 fixed만 정리하고 custom·snoozed·울리는 알람은 보존한다`() {
        val c = case("generation_cases.json", "EMPTY_TEMPLATES_CLEAN_FIXED")
        seedSchedule(c.getJSONObject("schedule"))
        seedRows(c)
        RingingAlarmTracker.startRing(context, c.getInt("active_ring_id"))

        AlarmRefreshEngine.doRefresh(context, noopSchedule, millis(c.getString("now")))

        assertEquals(listOf(102, 103, 104), ids("alarms"))
        assertEquals(1, count("alarm_history"))
    }

    @Test
    fun `#26 템플릿 조회 실패는 빈 결과로 바꾸지 않고 전파되며 아무것도 바꾸지 않는다`() {
        val c = case("generation_cases.json", "TEMPLATE_QUERY_ERROR_NO_MUTATION")
        seedSchedule(c.getJSONObject("schedule"))
        seedRows(c)
        db.execSQL("DROP TABLE shift_alarm_templates")  // 조회 실패 주입

        assertThrows(Exception::class.java) {
            AlarmRefreshEngine.doRefresh(context, noopSchedule, millis(c.getString("now")))
        }
        assertEquals(listOf(201), ids("alarms"))
        assertEquals(0, count("alarm_history"))
    }

    @Test
    fun `#26 멱등 - 같은 입력으로 두 번 갱신해도 추가·삭제·이력이 없고 ID가 그대로다`() {
        val c = case("generation_cases.json", "IDEMPOTENT_EXACT_EXISTING")
        seedSchedule(c.getJSONObject("schedule"))
        seedTemplates(c)
        seedRows(c)
        val now = millis(c.getString("now"))

        repeat(2) {
            AlarmRefreshEngine.doRefresh(context, noopSchedule, now)
            assertEquals(listOf(401), ids("alarms"))
            assertEquals(0, count("alarm_history"))
            assertEquals(0, count("alarm_creation_log"))
        }
    }

    @Test
    fun `#26 불규칙 - 창 밖 배정의 창 안 기여까지 엔진이 알람을 만든다`() {
        val c = case("generation_cases.json", "IRREGULAR_OUTSIDE_ASSIGNMENT_CONTRIBUTION")
        seedSchedule(c.getJSONObject("schedule"))
        seedTemplates(c)

        AlarmRefreshEngine.doRefresh(context, noopSchedule, millis(c.getString("now")))

        val expected = c.getJSONArray("expected_generation_slots").let { arr ->
            (0 until arr.length()).map { arr.getJSONObject(it) }
                .map { "${it.getString("slot_time")}|${it.getString("shift_type")}|${it.getInt("day_offset")}|type=${it.getInt("alarm_type_id")}" }
        }.sorted()
        assertEquals(expected, slots().sorted())
    }

    @Test
    fun `#31 엔진 경로에서도 skip·set_type 예외가 적용된다`() {
        val c = case("generation_cases.json", "OVERRIDE_SKIP_AND_SET_TYPE")
        seedSchedule(c.getJSONObject("schedule"))
        seedTemplates(c)
        seedOverrides(c.getJSONArray("overrides"))

        AlarmRefreshEngine.doRefresh(context, noopSchedule, millis(c.getString("now")))

        assertEquals(
            listOf("2026-09-15T07:00:00|DAY|0|type=9", "2026-09-15T08:00:00|DAY|0|type=1"),
            slots()
        )
    }

    @Test
    fun `D11 - 슬롯 시각이 30일 이상 지난 예외만 정리하고 이력 테이블은 건드리지 않는다`() {
        val c = case("state_change_cases.json", "D11_AGE_BOUNDARY")
        seedSchedule(JSONObject("""{"mode":"irregular","assigned_dates":{}}"""))
        seedOverrides(c.getJSONArray("overrides_before"))
        repeat(2) {
            db.execSQL("INSERT INTO alarm_history(alarm_id, dismiss_type, created_at) VALUES (1, 'swiped', '2026-08-01T00:00:00')")
            db.execSQL("INSERT INTO alarm_creation_log(alarm_id, source, created_at) VALUES (1, 'auto', '2026-08-01T00:00:00')")
        }

        AlarmRefreshEngine.doRefresh(context, noopSchedule, millis(c.getString("now")))

        assertEquals(listOf(503, 504), ids("alarm_overrides"))
        assertEquals(2, count("alarm_history"))
        assertEquals(2, count("alarm_creation_log"))
    }

    @Test
    fun `#26 P1 - 정책 버전은 갱신이 성공한 뒤에만 기록되고 낮으면 오늘 갱신했어도 강제 갱신을 트리거한다`() {
        val c = case("generation_cases.json", "IRREGULAR_OUTSIDE_ASSIGNMENT_CONTRIBUTION")
        seedSchedule(c.getJSONObject("schedule"))
        seedTemplates(c)
        val prefs = context.createDeviceProtectedStorageContext().getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        prefs.edit().putLong("last_alarm_refresh", System.currentTimeMillis()).commit()  // 옛 코드가 오늘 이미 갱신함
        val app = context as Application

        shadowOf(app).clearBroadcastIntents()
        AlarmRefreshUtil.checkAndTriggerRefresh(context)
        assertTrue("정책 버전이 낮으면 강제 갱신 요청",
            shadowOf(app).broadcastIntents.any { it.action == "com.hwani1103.shiftbell.REFRESH_ALARMS" })

        AlarmRefreshEngine.doRefresh(context, { _, _, _, _ -> throw SecurityException("denied") }, millis(c.getString("now")))
        assertEquals("OS 반영 실패 - 정책 버전 미기록", 0, policyVersion())

        AlarmRefreshEngine.doRefresh(context, noopSchedule, millis(c.getString("now")))
        if (AlarmWakeScheduler.failedIds(context).isEmpty()) {
            assertEquals(AlarmRefreshEngine.REFRESH_POLICY_VERSION, policyVersion())
            shadowOf(app).clearBroadcastIntents()
            AlarmRefreshUtil.checkAndTriggerRefresh(context)
            assertFalse("기록 뒤에는 오늘 다시 강제 갱신하지 않음",
                shadowOf(app).broadcastIntents.any { it.action == "com.hwani1103.shiftbell.REFRESH_ALARMS" })
        }
    }
}
