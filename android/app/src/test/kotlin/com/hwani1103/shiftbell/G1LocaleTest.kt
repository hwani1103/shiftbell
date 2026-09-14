// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1LocaleTest.kt
//
// 출시전 감사 G1 #17 - DB 날짜 문자열이 기기 로케일과 무관해야 함.
// 태국어(불기 달력 → 연도 2569), 페르시아어·아랍어(해당 문자권 숫자) 기기에서
//  - 생성 계산이 배정일 조회·저장 문자열·슬롯 모두 ASCII 그레고리력으로 같은 결과를 내는지(T11a fixture)
//  - 스누즈가 저장하는 날짜 문자열과 수신 시 파싱이 어긋나지 않는지
// 사용자 표시용 형식(20분 전 알림의 시각 등)은 대상 아님.
package com.hwani1103.shiftbell

import android.content.ContentValues
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
class G1LocaleTest {

    private lateinit var originalLocale: Locale
    private lateinit var originalTz: TimeZone
    private val locales = listOf(
        Locale.forLanguageTag("th-TH-u-ca-buddhist"),
        Locale.forLanguageTag("fa-IR"),
        Locale.forLanguageTag("ar-EG"),
    )
    private val asciiDateTime = Regex("""^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$""")

    @Before
    fun setUp() {
        originalLocale = Locale.getDefault()
        originalTz = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"))
    }

    @After
    fun tearDown() {
        Locale.setDefault(originalLocale)
        TimeZone.setDefault(originalTz)
        RingingAlarmTracker.resetMemoryForTest()
        DatabaseHelper.resetInstanceForTest()
    }

    @Test
    fun `#17 기기 로케일과 무관하게 불규칙 배정일 조회와 생성 문자열이 fixture와 같다`() {
        val root = JSONObject(File(G0TestSupport.repoRoot, "test/release_audit/g1/fixtures/generation_cases.json").readText(Charsets.UTF_8))
        val cases = root.getJSONArray("cases")
        val case = (0 until cases.length()).map { cases.getJSONObject(it) }.first { it.getString("id") == "IRREGULAR_OUTSIDE_ASSIGNMENT_CONTRIBUTION" }
        val assigned = case.getJSONObject("schedule").getJSONObject("assigned_dates")
        val schedule = AlarmRefreshEngine.ScheduleData(false, emptyList(), 0, 0L,
            assigned.keys().asSequence().associateWith { assigned.getString(it) })
        val tArr = case.getJSONArray("templates")
        val templates = (0 until tArr.length()).map { tArr.getJSONObject(it) }.groupBy({ it.getString("shift_type") }) {
            AlarmRefreshEngine.TemplateEntry(it.getString("time"), it.getInt("alarm_type_id"), it.getInt("day_offset"))
        }
        val eArr = case.getJSONArray("expected_generation_slots")
        val expected = (0 until eArr.length()).map { eArr.getJSONObject(it) }
            .map { "${it.getString("slot_time")}|${it.getString("shift_type")}|${it.getInt("day_offset")}" }.sorted()

        for (locale in locales) {
            Locale.setDefault(Locale.US)
            val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).parse(case.getString("now"))!!.time
            Locale.setDefault(locale)

            val desired = AlarmRefreshEngine.computeDesiredAlarms(schedule, templates, emptyMap(), now)

            desired.forEach { assertTrue("$locale 저장 문자열이 ASCII 그레고리력이어야 함: ${it.dateStr}", asciiDateTime.matches(it.dateStr)) }
            assertEquals("$locale", expected, desired.map { "${it.dateStr}|${it.shiftType}|${it.dayOffset}" }.sorted())
        }
    }

    @Test
    fun `#17 스누즈가 저장한 날짜와 수신 판정 파싱이 기기 로케일과 무관하다`() {
        val context: Context = ApplicationProvider.getApplicationContext()
        for (locale in locales) {
            Locale.setDefault(Locale.US)
            DatabaseHelper.resetInstanceForTest()
            RingingAlarmTracker.resetMemoryForTest()
            val deviceContext = context.createDeviceProtectedStorageContext()
            deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).edit()
                .clear().putLong("last_alarm_refresh", System.currentTimeMillis()).commit()
            val dbFile = deviceContext.getDatabasePath("shiftbell.db")
            for (suffix in listOf("", "-wal", "-shm", "-journal")) File(dbFile.path + suffix).delete()
            dbFile.parentFile?.mkdirs()
            File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(dbFile, overwrite = true)
            val dbHelper = DatabaseHelper.getInstance(context)
            dbHelper.writableDatabase.insert("alarms", null, ContentValues().apply {
                put("id", 7); put("time", "07:00"); put("date", "2026-09-14T07:00:00"); put("type", "fixed")
                put("alarm_type_id", 1); put("shift_type", "주간"); put("day_offset", 0)
            })

            Locale.setDefault(locale)
            assertTrue(AlarmActionHelper.snooze(context, 7, 5) != null)

            val stored = dbHelper.writableDatabase.rawQuery("SELECT date, time FROM alarms WHERE id = 7", null).use {
                it.moveToFirst(); it.getString(0) to it.getString(1)
            }
            assertTrue("$locale 스누즈 저장 날짜: ${stored.first}", asciiDateTime.matches(stored.first))
            assertEquals("$locale 그레고리력 연도", Calendar.getInstance(Locale.US).get(Calendar.YEAR).toString(), stored.first.substring(0, 4))
            assertTrue("$locale 스누즈 저장 시각: ${stored.second}", Regex("""^\d{2}:\d{2}$""").matches(stored.second))

            Locale.setDefault(Locale.US)
            val expectedAt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).parse(stored.first)!!.time
            Locale.setDefault(locale)
            assertEquals("$locale 수신 판정", AlarmWakeScheduler.ReceiveDecision.RING,
                AlarmWakeScheduler.decideOnReceive(context, 7, expectedAt))
        }
    }
}
