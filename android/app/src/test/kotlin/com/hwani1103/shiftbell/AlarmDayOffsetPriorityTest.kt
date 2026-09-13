// android/app/src/test/kotlin/com/hwani1103/shiftbell/AlarmDayOffsetPriorityTest.kt
//
// 테스트_계획_2026-09-12.md B-2 대상 #3 — "day_offset 알람 우선순위 계산(당일>전날
// 기여>다음날 기여) 로직". AlarmRefreshEngine.computeDesiredAlarms()는 순수 계산
// (Calendar/SimpleDateFormat만 사용, Android 프레임워크 의존 없음)이라 Robolectric 없이
// 평범한 JUnit4 테스트로도 충분히 검증 가능함 - 실행이 훨씬 빠름.
//
// 이 우선순위는 Dart alarm_generation_service.dart의 computeDesiredFixedAlarmsForDate()와
// 반드시 동일하게 유지되어야 한다(AlarmRefreshEngine.kt 상단 주석 참고) - 어긋나면
// diff 갱신이 서로를 "다른 알람"으로 오판해 불필요하게 지웠다 다시 만든다.

package com.hwani1103.shiftbell

import org.junit.Assert.assertEquals
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class AlarmDayOffsetPriorityTest {

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())

    private fun midnightToday(): Calendar = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    @Test
    fun `같은 시각에 당일 알람과 전날 기여 알람이 겹치면 당일이 우선한다`() {
        // 패턴: 주간-야간 반복, todayIndex=1 → 내일(daysDiff=1)이 index0="주간",
        // 모레(daysDiff=2)가 index1="야간"이 되도록 배치.
        //   D=내일: sameDayShift="주간"(당일, offset 0)
        //           dayBeforeContributor=resolveShiftType(D+1=모레)="야간"(offset -1 기여)
        // 둘 다 "07:00" 템플릿을 가지고 있으면, 우선순위(당일>전날 기여)에 따라
        // "주간"의 당일(offset 0) 알람만 살아남아야 한다.
        val startDate = midnightToday()
        val schedule = AlarmRefreshEngine.ScheduleData(
            isRegular = true,
            pattern = listOf("주간", "야간"),
            todayIndex = 1,
            startDateMillis = startDate.timeInMillis,
            assignedDates = emptyMap()
        )
        val templates = mapOf(
            "주간" to listOf(AlarmRefreshEngine.TemplateEntry(time = "07:00", alarmTypeId = 1, dayOffset = 0)),
            "야간" to listOf(AlarmRefreshEngine.TemplateEntry(time = "07:00", alarmTypeId = 2, dayOffset = -1)),
        )

        val desired = AlarmRefreshEngine.computeDesiredAlarms(schedule, templates)

        // 내일(daysDiff=1) 날짜 문자열을 정확히 같은 방식으로 재계산해 필터링.
        val tomorrow = Calendar.getInstance().apply {
            timeInMillis = startDate.timeInMillis
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 7)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val tomorrowDateStr = dateFormat.format(tomorrow.time)

        val atSevenAmTomorrow = desired.filter { it.dateStr == tomorrowDateStr }
        assertEquals("07:00에는 정확히 하나의 알람만 살아남아야 함(당일이 전날 기여를 이김)", 1, atSevenAmTomorrow.size)
        val winner = atSevenAmTomorrow.first()
        assertEquals("주간", winner.shiftType)
        assertEquals(0, winner.dayOffset)
        assertEquals(1, winner.alarmTypeId)
    }

    @Test
    fun `시각이 겹치지 않으면 당일과 전날 기여 알람이 둘 다 생성된다`() {
        val startDate = midnightToday()
        val schedule = AlarmRefreshEngine.ScheduleData(
            isRegular = true,
            pattern = listOf("주간", "야간"),
            todayIndex = 1,
            startDateMillis = startDate.timeInMillis,
            assignedDates = emptyMap()
        )
        val templates = mapOf(
            "주간" to listOf(AlarmRefreshEngine.TemplateEntry(time = "07:00", alarmTypeId = 1, dayOffset = 0)),
            // 겹치지 않는 시각(18:00)의 "전날" 기여 - 야간 근무 전날 저녁 알람의 전형적 예.
            "야간" to listOf(AlarmRefreshEngine.TemplateEntry(time = "18:00", alarmTypeId = 2, dayOffset = -1)),
        )

        val desired = AlarmRefreshEngine.computeDesiredAlarms(schedule, templates)
        val tomorrowDatePrefix = dateFormat.format(
            Calendar.getInstance().apply {
                timeInMillis = startDate.timeInMillis
                add(Calendar.DAY_OF_MONTH, 1)
            }.time
        ).substring(0, 10)

        val tomorrowAlarms = desired.filter { it.dateStr.startsWith(tomorrowDatePrefix) }
        assertEquals("겹치지 않으면 당일+전날 기여 둘 다 살아남아야 함", 2, tomorrowAlarms.size)
        assertEquals(setOf("07:00", "18:00"), tomorrowAlarms.map { it.time }.toSet())
        assertEquals(setOf(0, -1), tomorrowAlarms.map { it.dayOffset }.toSet())
    }

    @Test
    fun `미설정(패턴 없음) 근무는 알람을 만들지 않는다`() {
        val startDate = midnightToday()
        val schedule = AlarmRefreshEngine.ScheduleData(
            isRegular = true,
            pattern = listOf("휴무", "휴무"),
            todayIndex = 0,
            startDateMillis = startDate.timeInMillis,
            assignedDates = emptyMap()
        )
        val templates = mapOf(
            "주간" to listOf(AlarmRefreshEngine.TemplateEntry(time = "07:00", alarmTypeId = 1, dayOffset = 0)),
        )
        val desired = AlarmRefreshEngine.computeDesiredAlarms(schedule, templates)
        assertEquals("패턴에 없는 근무명의 템플릿은 절대 알람으로 안 만들어짐", 0, desired.size)
    }
}
