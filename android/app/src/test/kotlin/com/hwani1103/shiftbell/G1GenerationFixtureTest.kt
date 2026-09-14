// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1GenerationFixtureTest.kt
//
// 출시전 감사 G1 #26(P1)/#31 - Kotlin 생성 계산을 T11a 독립 fixture(test/release_audit/g1/fixtures/
// generation_cases.json, Codex 작성 - contracts §2·v4 #26/#31만 근거, 제품 코드 미참조)와 비교.
// Dart 쪽 같은 fixture 테스트: test/release_audit/g1/g1_generation_fixture_test.dart.
// DB·diff·보호 대상·조회 실패 케이스는 엔진 경로 테스트(G1GenerationEngineTest).
package com.hwani1103.shiftbell

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

// org.json은 JVM 단위 테스트에선 안드로이드 스텁(isReturnDefaultValues=true → null 반환)이라 Robolectric으로 실행
@RunWith(RobolectricTestRunner::class)
class G1GenerationFixtureTest {

    private lateinit var originalTz: TimeZone

    @Before
    fun setUp() {
        originalTz = TimeZone.getDefault()
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(originalTz)
    }

    private fun fixtures(): List<JSONObject> = listOf("generation_cases.json", "review_fixture_additions.json").map {
        JSONObject(File(G0TestSupport.repoRoot, "test/release_audit/g1/fixtures/$it").readText(Charsets.UTF_8))
    }

    private fun slot(timestamp: Long) = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(java.util.Date(timestamp))

    private fun scheduleOf(json: JSONObject): AlarmRefreshEngine.ScheduleData {
        val assigned = json.optJSONObject("assigned_dates")
        val assignedMap = assigned?.keys()?.asSequence()?.associateWith { assigned.getString(it) } ?: emptyMap()
        return if (json.getString("mode") == "regular") {
            val pattern = json.getJSONArray("pattern")
            AlarmRefreshEngine.ScheduleData(
                isRegular = true,
                pattern = (0 until pattern.length()).map { pattern.getString(it) },
                todayIndex = json.getInt("today_index"),
                startDateMillis = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(json.getString("start_date"))!!.time,
                assignedDates = assignedMap
            )
        } else {
            // 제품 readSchedule()의 불규칙 분기와 같은 형태(패턴 없음, 배정일만)
            AlarmRefreshEngine.ScheduleData(false, emptyList(), 0, 0L, assignedMap)
        }
    }

    @Test
    fun `#26 #31 생성 계산이 독립 fixture 기대값과 같다`() {
        var compared = 0
        for (root in fixtures()) {
            TimeZone.setDefault(TimeZone.getTimeZone(root.getString("timezone")))
            val cases = root.getJSONArray("cases")
            for (i in 0 until cases.length()) {
                val case = cases.getJSONObject(i)
                val id = case.getString("id")
                if (case.optString("template_query_result") == "error") continue  // 엔진 경로 테스트에서 확인
                val expectedJson = case.optJSONArray("expected_generation_slots") ?: continue

                val templatesJson = case.getJSONArray("templates")
                val templates = (0 until templatesJson.length()).map { templatesJson.getJSONObject(it) }
                    .groupBy({ it.getString("shift_type") }) {
                        AlarmRefreshEngine.TemplateEntry(it.getString("time"), it.getInt("alarm_type_id"), it.getInt("day_offset"))
                    }
                val overridesJson = case.getJSONArray("overrides")
                val overrides = (0 until overridesJson.length()).map { overridesJson.getJSONObject(it) }.associate {
                    AlarmRefreshEngine.slotKey(it.getString("slot_time"), it.getString("shift_type"), it.getInt("day_offset")) to
                        AlarmRefreshEngine.OverrideEntry(it.getString("action"), if (it.isNull("alarm_type_id")) null else it.getInt("alarm_type_id"))
                }
                val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).parse(case.getString("now"))!!.time

                val actual = AlarmRefreshEngine.computeDesiredAlarms(scheduleOf(case.getJSONObject("schedule")), templates, overrides, now)
                    .map { "${slot(it.timestamp)}|${it.shiftType}|${it.dayOffset}|type=${it.alarmTypeId}" }
                    .sorted()
                val expected = (0 until expectedJson.length()).map { expectedJson.getJSONObject(it) }
                    .map { "${it.getString("slot_time")}|${it.getString("shift_type")}|${it.getInt("day_offset")}|type=${it.getInt("alarm_type_id")}" }
                    .sorted()

                assertEquals("fixture $id", expected, actual)
                compared++
            }
        }
        assertEquals("비교한 케이스 수(기존 5 + T11 보강 2)", 7, compared)
    }
}
