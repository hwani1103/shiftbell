package com.hwani1103.shiftbell

import android.view.View
import android.widget.Button
import android.widget.TextView

/** Owned and closed by the Activity/Service/Dialog. Renders in place without recreating a window. */
internal class SnoozeControlsBinding(private val root: View, private val ring: RingingAlarmTracker.ActiveRing,
    private val afterExecute: () -> Unit = {}) : AutoCloseable {
    private var bound: RingingAlarmTracker.SnoozeSelection? = null
    private val subscription = RingSnoozeController.observe(ring, ::render)
    init {
        root.findViewById<View>(R.id.snoozeDecreaseButton).setOnClickListener { RingSnoozeController.adjust(root.context, ring, -1) }
        root.findViewById<View>(R.id.snoozeIncreaseButton).setOnClickListener { RingSnoozeController.adjust(root.context, ring, 1) }
        root.findViewById<View>(R.id.snoozeButton).setOnClickListener { execute() }
        refresh()
    }
    fun refresh() { RingingAlarmTracker.selectionForLiveRing(root.context, ring)?.let(::render) }
    fun execute() {
        val selected = bound ?: return
        val result = RingSnoozeController.execute(root.context, RingSnoozeController.click(selected))
        if (result != SnoozeExecution.InvalidInput) afterExecute()
    }
    private fun render(selection: RingingAlarmTracker.SnoozeSelection) {
        bound = selection
        val button = root.findViewById<Button>(R.id.snoozeButton)
        val value = root.findViewById<TextView>(R.id.snoozeValueText)
        val lockTitle = root.findViewById<TextView>(R.id.lockSnoozeTitle)
        if (value != null) value.text = if (lockTitle != null) root.context.getString(R.string.alarm_snooze_duration, selection.minutes)
            else SnoozeText.compact(selection.minutes)
        else button.text = SnoozeText.compact(selection.minutes)
        button.contentDescription = SnoozeText.description(root.context, selection.minutes)
        root.findViewById<View>(R.id.snoozeDecreaseButton).apply {
            isEnabled = selection.minutes > 5
            contentDescription = root.context.getString(R.string.alarm_snooze_decrease)
        }
        root.findViewById<View>(R.id.snoozeIncreaseButton).apply {
            isEnabled = selection.minutes < 30
            contentDescription = root.context.getString(R.string.alarm_snooze_increase)
        }
    }
    override fun close() { subscription.close() }
}
