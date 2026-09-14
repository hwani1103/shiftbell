// android/app/src/test/kotlin/com/hwani1103/shiftbell/G1ScheduleResultTest.kt
//
// 출시전 감사 G1 #13 - 일정 알림 예약 실패가 성공으로 삼켜지지 않는다(ScheduleNotificationScheduler.schedule 반환값).
// MainActivity MethodChannel 연결(result.success(bool) / scheduleNativeAlarm 실패 → result.error)은
// Activity라 여기서 못 봄 → Dart 쪽 테스트(test/release_audit/g1)가 채널 결과별 동작을 확인.
package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.doThrow
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class G1ScheduleResultTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val alarmManager get() = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    @Test
    fun `#13 예약에 성공하면 true를 돌려주고 실제로 예약된다`() {
        val ok = ScheduleNotificationScheduler.schedule(
            context, 11, System.currentTimeMillis() + 60_000L, "2026-09-14", 600, "회의", 30
        )
        assertTrue(ok)
        assertEquals(1, shadowOf(alarmManager).scheduledAlarms.size)
    }

    @Test
    fun `#13 정확한 알람 권한이 없어 OS가 거부하면 false를 돌려준다`() {
        // 실기기 Android 12+는 권한이 꺼져 있으면 setExactAndAllowWhileIdle이 SecurityException을 던짐.
        // Robolectric ShadowAlarmManager.setCanScheduleExactAlarms(false)는 예외를 안 던져서(2026-09-14 실행 확인)
        // 그 예외를 던지는 AlarmManager를 Context에 끼워 넣음.
        val deniedAlarmManager = mock<AlarmManager>()
        doThrow(SecurityException("exact alarm denied"))
            .whenever(deniedAlarmManager).setExactAndAllowWhileIdle(any<Int>(), any<Long>(), any<PendingIntent>())
        val deniedContext = object : ContextWrapper(context) {
            override fun getSystemService(name: String): Any? =
                if (name == Context.ALARM_SERVICE) deniedAlarmManager else super.getSystemService(name)
        }

        val ok = ScheduleNotificationScheduler.schedule(
            deniedContext, 12, System.currentTimeMillis() + 60_000L, "2026-09-14", 600, "회의", 30
        )
        assertFalse(ok)
    }
}
