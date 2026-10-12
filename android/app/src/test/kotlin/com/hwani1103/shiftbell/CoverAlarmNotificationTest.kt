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
        NotificationHelper.postInitialRing(context, 901, ring.round, "주간", 3)
        val initial = shadowOf(manager).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
        assertNotNull(initial.fullScreenIntent)
        assertEquals(android.app.Notification.GROUP_ALERT_ALL, initial.groupAlertBehavior)
        NotificationHelper.ensureRingControls(context, 901, ring.round, "주간", 3, NotificationHelper.RingNoticeReason.COVER_ENTER)
        val quiet = shadowOf(manager).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
        assertEquals(NotificationManager.IMPORTANCE_LOW, manager.getNotificationChannel(quiet.channelId).importance)
        assertNull(quiet.fullScreenIntent)
        assertTrue(shadowOf(initial.fullScreenIntent).isCanceled)
        assertEquals(2, quiet.actions.size)
        assertNotNull(quiet.contentIntent)
        RingSnoozeController.adjust(context, ring, 1)
        val selected = manager.activeNotifications.single { it.id == NotificationHelper.RING_CONTROL_ID }.notification
        assertNull(selected.fullScreenIntent)
        assertEquals(quiet.channelId, selected.channelId)
        assertEquals(10, selected.extras.getInt(RingControlNotification.MINUTES))
        NotificationHelper.ensureRingControls(context, 901, ring.round, "주간", 3, NotificationHelper.RingNoticeReason.COVER_EXIT)
        val restored = shadowOf(manager).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
        assertEquals(initial.channelId, restored.channelId)
        assertEquals(2, restored.actions.size)
        assertTrue(shadowOf(restored.fullScreenIntent).isCanceled)
        assertEquals(android.app.Notification.GROUP_ALERT_SUMMARY, restored.groupAlertBehavior)
        RingSnoozeController.adjust(context, ring, 1)
        val adjusted = manager.activeNotifications.single { it.id == NotificationHelper.RING_CONTROL_ID }.notification
        assertEquals(restored.groupAlertBehavior, adjusted.groupAlertBehavior)
        assertEquals(restored.channelId, adjusted.channelId)
    }

    @Test fun staleCoverCannotReplaceNewRingNotification() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        RingingAlarmTracker.resetMemoryForTest()
        val old = RingingAlarmTracker.startRing(context, 901)
        val current = RingingAlarmTracker.startRing(context, 902)
        NotificationHelper.postInitialRing(context, 902, current.round, "New", 3)
        NotificationHelper.ensureRingControls(context, 901, old.round, "Old", 3, NotificationHelper.RingNoticeReason.COVER_ENTER)
        val notification = shadowOf(context.getSystemService(NotificationManager::class.java))
            .allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
        assertEquals("New", notification.extras.getString("android.title"))
        assertEquals(current.alarmId, notification.extras.getInt("shiftbell.copy.alarm"))
        assertEquals(current.round, notification.extras.getLong("shiftbell.copy.round"))
        val expanded = notification.bigContentView.apply(context, android.widget.FrameLayout(context))
        assertEquals("New", expanded.findViewById<android.widget.TextView>(R.id.ringNoticeTitle).text.toString())
    }
}
