// android/app/src/test/kotlin/com/hwani1103/shiftbell/ScheduleNotificationSchedulerTest.kt
//
// 테스트_계획_2026-09-12.md B-2 대상 #2 — "ScheduleNotificationScheduler.
// triggerMillisFor() - 날짜/시각 경계값(자정, 22시대 알림 등) 계산 정확성".
//
// 이 함수는 Dart schedule_notification_service.dart의 _triggerDateTime()과 반드시
// 같은 계산 결과를 내야 한다(그 파일 상단 주석 참고) - date('YYYY-MM-DD') 자정 +
// startMinutes - offsetMinutes, 전부 기기 로컬 타임존 기준.

package com.hwani1103.shiftbell

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Calendar

@RunWith(RobolectricTestRunner::class)
class ScheduleNotificationSchedulerTest {

    @Test
    fun `먼 미래 일정도 별도 기간 제한 없이 계산한다`() {
        val millis = ScheduleNotificationScheduler.triggerMillisFor("2045-12-31", 23 * 60 + 50, 30)
        assertNotNull(millis)
        val expected = Calendar.getInstance().apply {
            set(2045, Calendar.DECEMBER, 31, 23, 20, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        assertEquals(expected, millis)
    }

    private fun calendarAt(date: String, hour: Int, minute: Int): Calendar =
        Calendar.getInstance().apply {
            val parts = date.split("-").map { it.toInt() }
            set(parts[0], parts[1] - 1, parts[2], hour, minute, 0)
            set(Calendar.MILLISECOND, 0)
        }

    @Test
    fun `정시(오프셋 0)는 startMinutes 그대로 그날 자정 기준으로 계산된다`() {
        // 09:00(=540분) 정시 알림 → 그날 09:00.
        val millis = ScheduleNotificationScheduler.triggerMillisFor("2026-09-13", 9 * 60, 0)
        val expected = calendarAt("2026-09-13", 9, 0).timeInMillis
        assertEquals(expected, millis)
    }

    @Test
    fun `N분 전 오프셋은 자정을 넘어 전날로 정확히 넘어간다(경계값)`() {
        // 00:10(=10분) 일정에 "30분 전" 알림 → 전날 23:40으로 넘어가야 함.
        val millis = ScheduleNotificationScheduler.triggerMillisFor("2026-09-13", 10, 30)
        val expected = calendarAt("2026-09-12", 23, 40).timeInMillis
        assertEquals(expected, millis)
    }

    @Test
    fun `22시대 알림 - 오프셋을 빼도 같은 날 안에서 정상 계산된다`() {
        // 22:30(=1350분)에 "10분 전" → 같은 날 22:20.
        val millis = ScheduleNotificationScheduler.triggerMillisFor("2026-09-13", 22 * 60 + 30, 10)
        val expected = calendarAt("2026-09-13", 22, 20).timeInMillis
        assertEquals(expected, millis)
    }

    @Test
    fun `자정 정각(0분) 일정도 정확히 계산된다`() {
        val millis = ScheduleNotificationScheduler.triggerMillisFor("2026-09-13", 0, 0)
        val expected = calendarAt("2026-09-13", 0, 0).timeInMillis
        assertEquals(expected, millis)
    }

    @Test
    fun `날짜 형식이 잘못되면 예외 없이 null을 반환한다`() {
        val millis = ScheduleNotificationScheduler.triggerMillisFor("이건-날짜가-아님", 0, 0)
        assertNull(millis)
    }
}
