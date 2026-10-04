package com.hwani1103.shiftbell

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class CoverAlarmNotificationTest {
    @Test fun quietCoverKeepsActionsAndUnfoldRestoresOriginalChannelWithoutLaunchingAgain() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        RingingAlarmTracker.resetMemoryForTest()
        val ring = RingingAlarmTracker.startRing(context, 901)
        val manager = context.getSystemService(NotificationManager::class.java)
        NotificationHelper.showRingControlNotification(context, 901, ring.round, "주간", 3)
        val initial = shadowOf(manager).getNotification(NotificationHelper.RING_CONTROL_ID)
        assertNotNull(initial.fullScreenIntent)
        NotificationHelper.showRingControlNotification(context, 901, ring.round, "주간", 3, coverVisible = true)
        val quiet = shadowOf(manager).getNotification(NotificationHelper.RING_CONTROL_ID)
        assertEquals(NotificationManager.IMPORTANCE_LOW, manager.getNotificationChannel(quiet.channelId).importance)
        assertNull(quiet.fullScreenIntent)
        assertEquals(2, quiet.actions.size)
        assertNotNull(quiet.contentIntent)
        NotificationHelper.showRingControlNotification(context, 901, ring.round, "주간", 3, launchFullScreen = false)
        val restored = shadowOf(manager).getNotification(NotificationHelper.RING_CONTROL_ID)
        assertEquals(initial.channelId, restored.channelId)
        assertEquals(2, restored.actions.size)
        assertNull(restored.fullScreenIntent)
    }

    @Test fun staleCoverCannotReplaceNewRingNotification() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        RingingAlarmTracker.resetMemoryForTest()
        val old = RingingAlarmTracker.startRing(context, 901)
        val current = RingingAlarmTracker.startRing(context, 902)
        NotificationHelper.showRingControlNotification(context, 902, current.round, "New", 3)
        NotificationHelper.showRingControlNotification(context, 901, old.round, "Old", 3, coverVisible = true)
        val notification = shadowOf(context.getSystemService(NotificationManager::class.java))
            .getNotification(NotificationHelper.RING_CONTROL_ID)
        assertEquals("New", notification.extras.getString("android.title"))
    }
}
