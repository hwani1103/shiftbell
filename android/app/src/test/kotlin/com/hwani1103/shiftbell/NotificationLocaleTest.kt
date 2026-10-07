package com.hwani1103.shiftbell

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import androidx.core.app.NotificationCompat
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NotificationLocaleTest {
    private fun context(tag: String): Context {
        val app = ApplicationProvider.getApplicationContext<Context>()
        return app.createConfigurationContext(Configuration(app.resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) })
    }

    @Test fun `four notification kinds translate while preserving user content and intents`() {
        val ko = context("ko")
        val tap = PendingIntent.getActivity(ko, 41, Intent(ko, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        for (tag in listOf("pt-BR", "de", "en", "hi")) for (kind in listOf("guard", "snooze", "restore", "ring")) {
            val target = context(tag)
            val old = NotificationCompat.Builder(ko, "test")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("사용자 근무명")
                .setContentText("사용자 메모").setContentIntent(tap).setDeleteIntent(tap)
                .setFullScreenIntent(tap, true).setOngoing(true).setWhen(12345)
                .addExtras(NotificationLocale.metadata(ko, kind, "07:05", 7, 2))
                .addAction(0, "5분 후", tap).addAction(0, "끄기", tap).build()
            val fresh = NotificationLocale.translated(target, old)!!
            assertEquals(old.channelId, fresh.channelId)
            assertEquals(old.contentIntent, fresh.contentIntent)
            assertEquals(old.deleteIntent, fresh.deleteIntent)
            assertEquals(old.`when`, fresh.`when`)
            assertEquals(old.flags and Notification.FLAG_ONGOING_EVENT, fresh.flags and Notification.FLAG_ONGOING_EVENT)
            assertNull(fresh.fullScreenIntent)
            assertNull(NotificationLocale.translated(target, fresh))
            when (kind) {
                "guard" -> assertEquals(target.getString(R.string.notif_guard_title, "07:05"), fresh.extras.getString(Notification.EXTRA_TITLE))
                "snooze" -> assertEquals(target.getString(R.string.notif_snoozed_title, "07:05"), fresh.extras.getString(Notification.EXTRA_TITLE))
                "restore" -> {
                    assertEquals(target.getString(R.string.notif_restore_title), fresh.extras.getString(Notification.EXTRA_TITLE))
                    assertEquals(target.getString(R.string.notif_restore_text), fresh.extras.getString(Notification.EXTRA_BIG_TEXT))
                }
                "ring" -> {
                    assertEquals("사용자 근무명", fresh.extras.getString(Notification.EXTRA_TITLE))
                    assertEquals(target.getString(R.string.notif_ringing_content), fresh.extras.getString(Notification.EXTRA_TEXT))
                    assertEquals(target.getString(R.string.notif_action_snooze), fresh.actions[0].title)
                    assertEquals(target.getString(R.string.notif_action_dismiss), fresh.actions[1].title)
                    assertEquals(old.actions[0].actionIntent, fresh.actions[0].actionIntent)
                    assertEquals(old.actions[1].actionIntent, fresh.actions[1].actionIntent)
                }
            }
            if (kind == "guard" || kind == "snooze") assertEquals("사용자 메모", fresh.extras.getString(Notification.EXTRA_TEXT))
        }
    }

    @Test fun `locale refresh does not create channels or notifications or unblock an existing channel`() {
        val c = context("de")
        val manager = c.getSystemService(NotificationManager::class.java)
        manager.cancelAll()
        NotificationLocale.refresh(c)
        assertTrue(manager.activeNotifications.isEmpty())
        assertTrue(manager.notificationChannels.isEmpty())
        manager.createNotificationChannel(NotificationChannel("shiftbell_result_v3", "기록", NotificationManager.IMPORTANCE_NONE))
        NotificationLocale.refresh(c)
        val channel = manager.getNotificationChannel("shiftbell_result_v3")
        assertEquals(NotificationManager.IMPORTANCE_NONE, channel.importance)
        assertEquals(c.getString(R.string.channel_alarm_result), channel.name)
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test fun `ring refresh preserves its round and cannot revive dismissed or ended controls`() {
        val ko = context("ko")
        val de = context("de")
        val manager = ko.getSystemService(NotificationManager::class.java)
        RingingAlarmTracker.resetMemoryForTest()
        val ring = RingingAlarmTracker.startRing(ko, 7)
        NotificationHelper.postInitialRing(ko, 7, ring.round, "My shift", 3)
        val original = shadowOf(manager).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
        NotificationLocale.refresh(de)
        assertNotNull(shadowOf(manager).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }.fullScreenIntent)
        NotificationHelper.markRingPresented(ko, ring)
        val fresh = shadowOf(manager).allNotifications.first { it.extras.getString("shiftbell.copy.kind") == "ring" }
        assertEquals(de.getString(R.string.notif_action_dismiss), fresh.actions[1].title)
        assertEquals(original.actions[1].actionIntent, fresh.actions[1].actionIntent)
        assertEquals(ring, RingingAlarmTracker.current(ko))
        assertTrue(shadowOf(fresh.fullScreenIntent).isCanceled)
        NotificationHelper.cancelRingControls(ko, ring.alarmId, ring.round)
        NotificationLocale.refresh(context("hi"))
        assertTrue(manager.activeNotifications.isEmpty())
        RingingAlarmTracker.endIfCurrent(ko, 7, ring.round)
        var ran = false
        assertFalse(RingingAlarmTracker.runIfCurrent(ko, 7, ring.round) { ran = true })
        assertFalse(ran)
    }
}
