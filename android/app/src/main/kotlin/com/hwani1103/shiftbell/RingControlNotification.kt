package com.hwani1103.shiftbell

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

/** Immutable v2 commands: extras alone must never retarget a previously displayed button. */
object RingControlNotification {
    // A non-breaking space blanks only the collapsed snooze-description row.
    const val COLLAPSED_BLANK = "\u00A0"
    const val VERSION = "ringControlVersion"
    const val MINUTES = "selectedMinutes"
    const val REVISION = "selectionRevision"
    const val SURFACE = "ringSurface"
    const val INITIAL_WHEN = "ringInitialWhen"
    const val PROTOCOL = "protocol"
    const val STEPS = "deltaSteps"
    const val ACTION_ADJUST = "com.hwani1103.shiftbell.ADJUST_SNOOZE"
    const val ACTION_EXECUTE = "com.hwani1103.shiftbell.SNOOZE_SELECTED"
    data class Command(val selection: RingingAlarmTracker.SnoozeSelection, val steps: Int?)

    fun intent(context: Context, selected: RingingAlarmTracker.SnoozeSelection, steps: Int? = null): Intent {
        val ring = selected.ring
        val suffix = when (steps) { -1 -> "minus"; 1 -> "plus"; null -> "snooze/${selected.minutes}"; else -> error("Invalid steps") }
        return Intent(context, AlarmActionReceiver::class.java).apply {
            action = if (steps == null) ACTION_EXECUTE else ACTION_ADJUST
            data = Uri.parse("shiftbell://ring-control/v2/${ring.alarmId}/${ring.round}/${selected.revision}/$suffix")
            putExtra(PROTOCOL, 2)
            putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, ring.alarmId)
            putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, ring.round)
            putExtra(MINUTES, selected.minutes)
            putExtra(REVISION, selected.revision)
            if (steps != null) putExtra(STEPS, steps)
        }
    }
    internal fun decode(context: Context, input: Intent): Command? {
        if (input.getIntExtra(PROTOCOL, -1) != 2) return null
        val id = input.getIntExtra(AlarmActionReceiver.EXTRA_ALARM_ID, -1)
        val round = input.getLongExtra(AlarmActionReceiver.EXTRA_RING_ROUND, -1)
        val minutes = input.getIntExtra(MINUTES, -1)
        val revision = input.getLongExtra(REVISION, -1)
        if (id <= 0 || round <= 0 || revision < 0 || !SnoozeText.valid(minutes)) return null
        val steps = when (input.action) {
            ACTION_EXECUTE -> null
            ACTION_ADJUST -> input.getIntExtra(STEPS, 0).takeIf { it == -1 || it == 1 } ?: return null
            else -> return null
        }
        val selected = RingingAlarmTracker.SnoozeSelection(RingingAlarmTracker.ActiveRing(id, round), minutes, revision)
        val expected = intent(context, selected, steps)
        if (input.data != expected.data || input.component != expected.component) return null
        return Command(selected, steps)
    }
    private fun pending(context: Context, selected: RingingAlarmTracker.SnoozeSelection, steps: Int? = null) =
        PendingIntent.getBroadcast(context, 0, intent(context, selected, steps), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    fun decorate(context: Context, builder: NotificationCompat.Builder, selection: RingingAlarmTracker.SnoozeSelection,
        label: String, cover: Boolean, initialWhen: Long, dismiss: PendingIntent) {
        val content = SnoozeText.selection(context, selection.minutes)
        val views = RemoteViews(context.packageName, R.layout.notification_ring_controls).apply {
            setTextViewText(R.id.ringNoticeTitle, label)
            setTextViewText(R.id.ringNoticeStatus, context.getString(R.string.notif_ringing_content))
            setTextViewText(R.id.snoozeValueText, content)
            setContentDescription(R.id.snoozeDecreaseButton, context.getString(R.string.alarm_snooze_decrease))
            setContentDescription(R.id.snoozeIncreaseButton, context.getString(R.string.alarm_snooze_increase))
            setBoolean(R.id.snoozeDecreaseButton, "setEnabled", selection.minutes > 5)
            setBoolean(R.id.snoozeIncreaseButton, "setEnabled", selection.minutes < 30)
            setOnClickPendingIntent(R.id.snoozeDecreaseButton, pending(context, selection, -1))
            setOnClickPendingIntent(R.id.snoozeIncreaseButton, pending(context, selection, 1))
        }
        builder.addExtras(Bundle().apply {
            putInt(VERSION, 2); putInt(MINUTES, selection.minutes); putLong(REVISION, selection.revision)
            putString(SURFACE, if (cover) "cover" else "standard"); putLong(INITIAL_WHEN, initialWhen)
        }).setContentText(COLLAPSED_BLANK).setSubText(context.getString(R.string.notif_ringing_content))
            .setStyle(NotificationCompat.DecoratedCustomViewStyle()).setCustomBigContentView(views)
            .addAction(android.R.drawable.ic_lock_idle_alarm, SnoozeText.compact(selection.minutes), pending(context, selection))
            .addAction(android.R.drawable.ic_delete, context.getString(R.string.notif_action_dismiss), dismiss)
    }
}
