package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class DebugAlarmDeliveryProbeTest {
    @Test fun `probe identities and cancellation leave real alarms alone`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val existing = PendingIntent.getBroadcast(context, 77,
            Intent(context, CustomAlarmReceiver::class.java), PendingIntent.FLAG_IMMUTABLE)
        manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 600_000, existing)
        val receiver = DebugAlarmDeliveryProbe()
        for (mode in listOf("alarm_clock", "allow_idle")) {
            receiver.onReceive(context, Intent().putExtra("op", "schedule")
                .putExtra("mode", mode).putExtra("delay_ms", 90_000L))
        }
        assertEquals(3, shadowOf(manager).scheduledAlarms.size)
        val probes = shadowOf(manager).scheduledAlarms.filter { it.operation != existing }
        assertEquals(2, probes.map { shadowOf(it.operation).savedIntent.data }.toSet().size)
        receiver.onReceive(context, Intent().putExtra("op", "cancel"))
        assertEquals(listOf(existing), shadowOf(manager).scheduledAlarms.map { it.operation })
    }

    @Test fun `invalid mode and unsafe delay do not schedule alarms`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val receiver = DebugAlarmDeliveryProbe()
        receiver.onReceive(context, Intent().putExtra("op", "schedule").putExtra("mode", "bad"))
        receiver.onReceive(context, Intent().putExtra("op", "schedule")
            .putExtra("mode", "alarm_clock").putExtra("delay_ms", 1L))
        assertTrue(shadowOf(manager).scheduledAlarms.isEmpty())
    }
}
