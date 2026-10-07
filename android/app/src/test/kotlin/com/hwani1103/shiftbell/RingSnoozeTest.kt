package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.LooperMode
import java.io.File
import java.time.Duration
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
class RingSnoozeTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val device get() = context.createDeviceProtectedStorageContext()
    private val db get() = DatabaseHelper.getInstance(context).writableDatabase
    @Before fun setup() {
        DatabaseHelper.resetInstanceForTest(); RingingAlarmTracker.resetMemoryForTest()
        device.getSharedPreferences("alarm_state", 0).edit().clear()
            .putLong("last_alarm_refresh", System.currentTimeMillis())
            .putInt(AlarmRefreshEngine.KEY_REFRESH_POLICY_VERSION, AlarmRefreshEngine.REFRESH_POLICY_VERSION).commit()
        device.getSharedPreferences("snooze_feedback", 0).edit().clear().commit()
        val file = device.getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) File(file.path + suffix).delete()
        file.parentFile?.mkdirs()
        File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(file, overwrite = true)
        db.insertOrThrow("alarms", null, ContentValues().apply {
            put("id", 7); put("time", "09:00"); put("date", AlarmInstant.format(System.currentTimeMillis()))
            put("type", "fixed"); put("alarm_type_id", 1); put("shift_type", "Day"); put("day_offset", 0)
        })
    }
    @After fun cleanup() { DatabaseHelper.resetInstanceForTest(); RingingAlarmTracker.resetMemoryForTest() }
    private fun notification() = shadowOf(context.getSystemService(NotificationManager::class.java)).getNotification(NotificationHelper.ringTag(RingingAlarmTracker.current(context)!!), 7777)
    private fun historyCount() = db.rawQuery("SELECT COUNT(*) FROM alarm_history WHERE alarm_id=7", null).use { it.moveToFirst(); it.getInt(0) }

    @Test fun presentedFsiCapabilityIsRevokedButBodyTapStillOpensAndNextRoundHasDifferentOsKey() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        NotificationHelper.postInitialRing(context, 7, ring.round, "Shift", 3)
        val fsi = notification().fullScreenIntent
        val body = notification().contentIntent
        assertNotEquals(fsi, body)
        NotificationHelper.markRingPresented(context, ring)
        assertThrows(android.app.PendingIntent.CanceledException::class.java) { fsi.send() }
        body.send()
        assertEquals(ring.round, shadowOf(context as android.app.Application).nextStartedActivity.getLongExtra(AlarmActionReceiver.EXTRA_RING_ROUND, -1))
        val previousTag = NotificationHelper.ringTag(ring)
        val next = RingingAlarmTracker.startRing(context, 7)
        NotificationHelper.postInitialRing(context, 7, next.round, "Shift again", 3)
        assertNotEquals(previousTag, NotificationHelper.ringTag(next))
        assertFalse(shadowOf(notification().fullScreenIntent).isCanceled)
        NotificationHelper.cancelRingControls(context, ring.alarmId, ring.round)
        assertNotNull(notification())
        NotificationHelper.resetMemoryForTest()
        NotificationHelper.cancelRingControls(context, next.alarmId, next.round)
        assertNull(notification()) // persisted tag survives loss of the in-memory publication
        assertFalse(device.getSharedPreferences("ring_notice", 0).contains("tag"))
    }

    @Test fun selectionChangesNoReservationsNoDeadlineNoRestoreEpochAndClamps() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        AlarmActionHelper.scheduleRingTimeout(context, ring, 3)
        val alarms = shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.toList()
        val deadline = RingTimeoutController.remaining(ring)
        val carry = RingingAlarmTracker.carryState(context)
        val seen = mutableListOf<Int>()
        val observer = RingSnoozeController.observe(ring) { seen.add(it.minutes) }
        repeat(8) { RingSnoozeController.adjust(context, ring, 1) }
        assertEquals(listOf(10,15,20,25,30), seen)
        assertEquals(30, RingingAlarmTracker.selectionForLiveRing(context, ring)!!.minutes)
        repeat(8) { RingSnoozeController.adjust(context, ring, -1) }
        assertEquals(5, RingingAlarmTracker.selectionForLiveRing(context, ring)!!.minutes)
        assertNull(RingSnoozeController.adjust(context, ring, 2))
        assertEquals(deadline, RingTimeoutController.remaining(ring))
        assertEquals(carry, RingingAlarmTracker.carryState(context))
        assertEquals(alarms, shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.toList())
        assertEquals(0, historyCount())
        observer.close()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(3))
        assertNull(RingingAlarmTracker.current(context))
    }

    @Test fun persistedSelectionDoesNotReviveDeadProcessAndNewRoundStartsAtFive() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        repeat(3) { RingSnoozeController.adjust(context, ring, 1) }
        assertEquals(20, device.getSharedPreferences("alarm_state", 0).getInt("ring_snooze_minutes", -1))
        RingingAlarmTracker.resetMemoryForTest()
        assertEquals(ring, RingingAlarmTracker.current(context))
        assertNull(RingingAlarmTracker.selectionForLiveRing(context, ring))
        val fresh = RingingAlarmTracker.startRing(context, 7)
        assertTrue(fresh.round > ring.round)
        assertEquals(5, RingingAlarmTracker.selectionForLiveRing(context, fresh)!!.minutes)
        assertNull(RingSnoozeController.adjust(context, ring, 1))
    }

    @Test fun displayedOldMinutesExecuteExactlyOnceAtCapturedTimeAndCeilSeconds() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        repeat(2) { RingSnoozeController.adjust(context, ring, 1) }
        val fifteen = RingingAlarmTracker.selectionForLiveRing(context, ring)!!
        val accepted = AlarmWakeScheduler.normalize(System.currentTimeMillis()) + 450L
        val click = RingSnoozeController.Click(fifteen, accepted, android.os.SystemClock.elapsedRealtime())
        repeat(3) { RingSnoozeController.adjust(context, ring, 1) }
        val epoch = RingingAlarmTracker.carryState(context).epoch
        val result = RingSnoozeController.execute(context, click) as SnoozeExecution.Scheduled
        val target = accepted + 15 * 60_000L + 550L
        assertEquals(target, result.targetAt)
        db.rawQuery("SELECT date, type FROM alarms WHERE id=7", null).use {
            assertTrue(it.moveToFirst()); assertEquals(target, AlarmWakeScheduler.parse(it.getString(0))); assertEquals("snoozed", it.getString(1))
        }
        assertEquals(epoch + 2, RingingAlarmTracker.carryState(context).epoch)
        assertTrue(RingingAlarmTracker.carryState(context).endingIds.isEmpty())
        assertEquals(SnoozeExecution.IgnoredStale, RingSnoozeController.execute(context, click))
        assertEquals(1, historyCount())
        val wake = shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms.filter {
            it.operation?.let { pi -> shadowOf(pi).savedIntent.dataString } == "shiftbell://alarm/7"
        }
        assertEquals(listOf(target), wake.map { it.triggerAtMs })
    }

    @Test fun notificationUpdatesKeepClassificationAndRevokedFsiWhileOldButtonKeepsItsMinutes() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        NotificationHelper.postInitialRing(context, 7, ring.round, "My shift", 3)
        val initial = notification()
        assertNotNull(initial.fullScreenIntent)
        assertEquals(android.app.Notification.GROUP_ALERT_ALL, initial.groupAlertBehavior)
        assertNotNull(initial.bigContentView)
        val old = initial.actions[0].actionIntent
        repeat(2) { RingSnoozeController.adjust(context, ring, 1) }
        val updated = notification()
        assertEquals("+15m", updated.actions[0].title.toString())
        assertEquals(initial.`when`, updated.`when`)
        assertEquals(initial.channelId, updated.channelId)
        assertEquals(initial.fullScreenIntent, updated.fullScreenIntent); assertTrue(shadowOf(updated.fullScreenIntent).isCanceled); assertEquals(initial.groupAlertBehavior, updated.groupAlertBehavior); assertNull(updated.sound); assertNull(updated.vibrate)
        assertEquals(5, shadowOf(old).savedIntent.getIntExtra(RingControlNotification.MINUTES, -1))
        assertNotEquals(old, updated.actions[0].actionIntent)
        val oldPlus = RingControlNotification.intent(context, RingingAlarmTracker.SnoozeSelection(ring, 5, 0), 1)
        repeat(2) { AlarmActionReceiver().onReceive(context, oldPlus) }
        assertEquals(25, RingingAlarmTracker.selectionForLiveRing(context, ring)!!.minutes)
        NotificationHelper.cancelRingControls(context, ring.alarmId, ring.round)
        RingSnoozeController.adjust(context, ring, 1)
        assertNull(notification()) // A number refresh cannot resurrect a removed notification.
    }

    @Test fun mismatchedProtocolAndStaleRoundCannotStopNextAlarm() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        val input = RingControlNotification.intent(context, RingingAlarmTracker.SnoozeSelection(ring, 15, 2))
        AlarmActionReceiver().onReceive(context, Intent(input).putExtra(RingControlNotification.MINUTES, 30))
        assertEquals(ring, RingingAlarmTracker.current(context))
        AlarmActionReceiver().onReceive(context, Intent(input).putExtra(RingControlNotification.PROTOCOL, 1))
        assertEquals(ring, RingingAlarmTracker.current(context))
        val next = RingingAlarmTracker.startRing(context, 8)
        AlarmActionReceiver().onReceive(context, input)
        assertEquals(next, RingingAlarmTracker.current(context)); assertEquals(0, historyCount())
    }

    @Test fun transactionFailureEndsRingButNeverShowsSuccessOrLeavesPartialHistory() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        db.execSQL("CREATE TRIGGER fail_snooze BEFORE INSERT ON alarm_history BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        val result = RingSnoozeController.execute(context, RingSnoozeController.click(RingingAlarmTracker.selectionForLiveRing(context, ring)!!))
        assertTrue(result is SnoozeExecution.DbFailed)
        assertNull(RingingAlarmTracker.current(context)); assertEquals(0, historyCount())
        assertEquals("db", device.getSharedPreferences("snooze_feedback", 0).getString("code", null))
        db.rawQuery("SELECT type FROM alarms WHERE id=7", null).use { it.moveToFirst(); assertEquals("fixed", it.getString(0)) }
        SnoozeFeedback.consume(context)
        assertFalse(device.getSharedPreferences("snooze_feedback", 0).contains("code"))
    }

    @Test fun localeRefreshRetainsSelectedValueAndBinding() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        NotificationHelper.postInitialRing(context, 7, ring.round, "User title", 3)
        repeat(5) { RingSnoozeController.adjust(context, ring, 1) }
        val token = notification().actions[0].actionIntent
        for (tag in listOf("ko", "en", "de", "pt-BR", "hi")) {
            val translated = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) })
            NotificationLocale.refresh(translated)
            val fresh = notification()
            assertEquals("+30m", fresh.actions[0].title.toString())
            assertEquals(token, fresh.actions[0].actionIntent)
            assertNotNull(fresh.bigContentView); assertTrue(shadowOf(fresh.fullScreenIntent).isCanceled)
            assertEquals(SnoozeText.selection(translated, 30), fresh.extras.getString("android.text"))
        }
    }

    @Test fun osFailureAndSupersededCommitAreNeverReportedAsScheduled() {
        val target = RingSnoozeController.targetAt(System.currentTimeMillis(), 30)
        val failed = AlarmActionHelper.snoozeAt(context, 7, target,
            scheduleFn = { _, _, _, _ -> throw SecurityException("test denied") })
        assertTrue(failed is SnoozeExecution.OsFailed)
        assertEquals(1, historyCount()) // The DB commit survives an OS failure.
        val superseded = AlarmActionHelper.snoozeAt(context, 7, target + 60_000,
            beforeSchedule = { db.delete("alarms", "id=7", null) })
        assertTrue(superseded is SnoozeExecution.Superseded)
    }

    @Test fun eachAllowedDurationUsesTheCapturedInstantAcrossYearBoundary() {
        val accepted = java.time.Instant.parse("2026-12-31T23:59:59.999Z").toEpochMilli()
        for (minutes in listOf(5,10,15,20,25,30)) {
            val target = RingSnoozeController.targetAt(accepted, minutes)
            assertEquals(accepted + minutes * 60_000L + 1, target)
            assertEquals(target, AlarmWakeScheduler.parse(AlarmInstant.format(target)))
        }
    }

    @Test @org.robolectric.annotation.Config(sdk = [24])
    fun preChannelAndroidKeepsInitialFsiAndQuietSelection() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        NotificationHelper.postInitialRing(context, 7, ring.round, "Day", 3)
        assertNotNull(notification().fullScreenIntent)
        assertNull(notification().sound); assertNull(notification().vibrate)
        RingSnoozeController.adjust(context, ring, 1)
        assertTrue(shadowOf(notification().fullScreenIntent).isCanceled)
        assertEquals("+10m", notification().actions[0].title.toString())
    }

    @Test fun unverifiedOsAcceptanceIsDistinctFromConfirmedSchedule() {
        val target = RingSnoozeController.targetAt(System.currentTimeMillis(), 10)
        val result = AlarmActionHelper.snoozeAt(context, 7, target,
            scheduleFn = { _, _, _, _ -> },
            beforeSchedule = { db.execSQL("UPDATE alarms SET date='unreadable' WHERE id=7") })
        assertTrue(result is SnoozeExecution.Unverified)
    }

    @Test fun delayedOldCoverExitCannotReplaceNewCoverAndHomeNeverRelaunchesFsi() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        NotificationHelper.postInitialRing(context, 7, ring.round, "Day", 3)
        val whenPosted = notification().`when`
        val oldOwner = Any(); val newOwner = Any()
        NotificationHelper.ensureRingControls(context, 7, ring.round, "Day", 3, NotificationHelper.RingNoticeReason.COVER_ENTER, oldOwner)
        NotificationHelper.ensureRingControls(context, 7, ring.round, "Day", 3, NotificationHelper.RingNoticeReason.COVER_ENTER, newOwner)
        NotificationHelper.ensureRingControls(context, 7, ring.round, "Day", 3, NotificationHelper.RingNoticeReason.COVER_EXIT, oldOwner)
        assertEquals("shiftbell_cover_controls", notification().channelId)
        NotificationHelper.ensureRingControls(context, 7, ring.round, "Day", 3, NotificationHelper.RingNoticeReason.COVER_EXIT, newOwner)
        NotificationHelper.ensureRingControls(context, 7, ring.round, "Day", 3, NotificationHelper.RingNoticeReason.USER_LEAVE)
        assertTrue(shadowOf(notification().fullScreenIntent).isCanceled)
        assertEquals(whenPosted, notification().`when`)
        NotificationHelper.postInitialRing(context, 7, ring.round, "Day", 3)
        assertTrue(shadowOf(notification().fullScreenIntent).isCanceled) // A second START cannot restore FSI.
    }

    @Test fun stopFailureStillAttemptsUiCleanupAndFinishesTransitionOnce() {
        val ring = RingingAlarmTracker.startRing(context, 7)
        val epoch = RingingAlarmTracker.carryState(context).epoch
        var closed = 0
        RingSnoozeController.stopForTest = { throw IllegalStateException("test stop failure") }
        RingSnoozeController.closeForTest = { _, _ -> closed++; true }
        val result = RingSnoozeController.execute(context, RingSnoozeController.click(RingingAlarmTracker.selectionForLiveRing(context, ring)!!))
        assertTrue(result is SnoozeExecution.ExecutionFailed)
        assertEquals(1, closed)
        assertEquals(epoch + 2, RingingAlarmTracker.carryState(context).epoch)
        assertTrue(RingingAlarmTracker.carryState(context).endingIds.isEmpty())
        assertEquals(0, historyCount())
        assertEquals("execution", device.getSharedPreferences("snooze_feedback", 0).getString("code", null))
    }
}
