package com.hwani1103.shiftbell

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
class SnoozeDefaultsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val prefs get() = context.createDeviceProtectedStorageContext().getSharedPreferences("snooze_defaults",0)
    @Before fun setup() {
        prefs.edit().clear().commit()
        context.createDeviceProtectedStorageContext().getSharedPreferences("alarm_state",0).edit().clear().commit()
        RingingAlarmTracker.resetMemoryForTest(); SnoozeDefaults.commitOverride = null
    }
    @After fun cleanup() { prefs.edit().clear().commit(); SnoozeDefaults.commitOverride = null; RingingAlarmTracker.resetMemoryForTest() }
    @Test fun defaultsPersistAndEveryNewRoundUsesThemWhileLocalAdjustmentDoesNotSave() {
        assertEquals(5,SnoozeDefaults.read(context))
        for (minutes in listOf(5,10,15)) {
            assertTrue(RingSnoozeController.setDefault(context,minutes))
            val ring = RingingAlarmTracker.startRing(context,7)
            assertEquals(minutes,RingingAlarmTracker.selectionForLiveRing(context,ring)!!.minutes)
            repeat(6) { RingSnoozeController.adjust(context,ring,1) }
            assertEquals(30,RingingAlarmTracker.selectionForLiveRing(context,ring)!!.minutes)
            assertEquals(minutes,SnoozeDefaults.read(context))
            RingingAlarmTracker.resetMemoryForTest()
            assertFalse(RingingAlarmTracker.isLiveRing(context))
            val next = RingingAlarmTracker.startRing(context,7)
            assertEquals(minutes,RingingAlarmTracker.selectionForLiveRing(context,next)!!.minutes)
        }
    }
    @Test fun settingUpdatesObserversAndRevisionWithoutChangingDeadlineOrRing() {
        val ring = RingingAlarmTracker.startRing(context,7)
        RingTimeoutController.start(context,ring,3)
        val before = RingTimeoutController.remaining(ring)
        val seen = mutableListOf<Int>()
        val subscription = RingSnoozeController.observe(ring) { seen.add(it.minutes) }
        assertTrue(RingSnoozeController.setDefault(context,15))
        assertEquals(listOf(15),seen)
        assertEquals(before,RingTimeoutController.remaining(ring))
        assertEquals(ring,RingingAlarmTracker.current(context))
        assertEquals(1L,RingingAlarmTracker.selectionForLiveRing(context,ring)!!.revision)
        RingSnoozeController.adjust(context,ring,-1)
        assertEquals(listOf(15,10),seen)
        assertEquals(15,SnoozeDefaults.read(context))
        subscription.close()
    }
    @Test fun failureDoesNotUpdateLiveSelectionAndCorruptStoredValueFallsBack() {
        prefs.edit().putString("default_minutes","bad").commit()
        assertEquals(5,SnoozeDefaults.read(context))
        assertTrue(RingSnoozeController.setDefault(context,10))
        val ring = RingingAlarmTracker.startRing(context,7)
        SnoozeDefaults.commitOverride = { it.apply(); false }
        assertFalse(RingSnoozeController.setDefault(context,15))
        assertEquals(10,SnoozeDefaults.read(context))
        assertEquals(10,RingingAlarmTracker.selectionForLiveRing(context,ring)!!.minutes)
        assertThrows(IllegalArgumentException::class.java) { RingSnoozeController.setDefault(context,20) }
    }
    @Test fun savingAfterProcessLossDoesNotReviveOldRing() {
        val ring = RingingAlarmTracker.startRing(context,7)
        RingingAlarmTracker.resetMemoryForTest()
        assertTrue(RingSnoozeController.setDefault(context,15))
        assertNull(RingingAlarmTracker.selectionForLiveRing(context,ring))
        assertFalse(RingingAlarmTracker.isLiveRing(context))
    }
}
