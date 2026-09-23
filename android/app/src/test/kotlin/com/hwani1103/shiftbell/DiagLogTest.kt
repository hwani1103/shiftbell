package com.hwani1103.shiftbell

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 1.0.24 C - 진단 기록: 한 줄 형식, 두 파일 순환(총량 상한), 시간순 읽기. */
@RunWith(RobolectricTestRunner::class)
class DiagLogTest {
    private lateinit var context: Context
    private var t = 1_790_000_000_000L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        DiagLog.files(context).let { (a, b) -> a.delete(); b.delete() }
        DiagLog.clock = { t }
    }

    @After
    fun tearDown() {
        DiagLog.clock = { System.currentTimeMillis() }
    }

    @Test
    fun `한 줄 형식 - 줄바꿈과 구분자는 공백으로`() {
        val line = DiagLog.format(t, "ALARM_FIRED", listOf("id" to 7, "msg" to "a\nb|c", "n" to null))
        assertTrue(line, line.endsWith(" | ALARM_FIRED | id=7 msg=a b c n=null"))
        assertFalse(line.contains('\n'))
    }

    @Test
    fun `두 파일을 번갈아 써서 총량이 상한을 넘지 않고 최근 기록은 남는다`() {
        val filler = "x".repeat(900)
        repeat(3000) { i ->
            t += 1000
            DiagLog.log(context, "EV", "i" to i, "pad" to filler)
        }
        val (a, b) = DiagLog.files(context)
        assertTrue(a.length() + b.length() <= 2 * DiagLog.MAX_FILE_BYTES + 2048)
        val all = DiagLog.readAll(context)
        assertTrue("가장 최근 기록 유지", all.contains("i=2999 "))
        assertFalse("가장 오래된 기록은 밀려남", all.contains("i=0 "))
        // 시간순: 앞쪽 줄의 i가 뒤쪽 줄보다 작아야 함
        val ids = Regex("i=(\\d+) ").findAll(all).map { it.groupValues[1].toInt() }.toList()
        assertEquals(ids.sorted(), ids)
    }
}
