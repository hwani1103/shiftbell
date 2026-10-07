package com.hwani1103.shiftbell

import android.app.Instrumentation
import android.content.ContentValues
import android.os.Build
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** Synthetic fixtures only, on a fresh emulator. Never compiled into the app. */
object DevTimezoneAudit {
    fun seed(instrumentation: Instrumentation): JSONObject {
        val context = instrumentation.targetContext
        check(context.packageName == "com.hwani1103.shiftbell.dev")
        check(Build.HARDWARE in setOf("ranchu", "goldfish")) { "Emulator only" }
        check(TimeZone.getDefault().id == "Asia/Seoul") { "Seed in Seoul" }
        val db = DatabaseHelper.getInstance(context).getWritableDatabaseWithRetry()!!
        check(db.version == 28)
        for (table in listOf("alarms", "shift_schedule", "alarm_history", "alarm_creation_log", "fixed_alarm_consumptions")) {
            check(db.rawQuery("SELECT count(*) FROM $table", null).use { it.moveToFirst(); it.getInt(0) } == 0) {
                "Fresh synthetic database required: $table"
            }
        }
        val first = Calendar.getInstance(Locale.US).apply {
            add(Calendar.MINUTE, 2); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val later = (first.clone() as Calendar).apply { add(Calendar.MINUTE, 30) }
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val hm = SimpleDateFormat("HH:mm", Locale.US)
        val full = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        val label = "TZ_AUDIT_20261007"
        db.beginTransaction()
        try {
            db.insertOrThrow("shift_schedule", null, ContentValues().apply {
                put("id", 1); put("is_regular", 0); put("shift_types", label)
                put("assigned_dates", JSONObject().put(day.format(first.time), label)
                    .put(day.format(later.time), label).toString())
            })
            db.update("alarm_types", ContentValues().apply {
                put("sound_file", "silent"); put("volume", 0.0)
                put("vibration_strength", 0); put("duration", 1)
            }, "id = 3", null)
            for (at in listOf(first, later)) db.insertOrThrow("shift_alarm_templates", null, ContentValues().apply {
                put("shift_type", label); put("time", hm.format(at.time))
                put("alarm_type_id", 3); put("day_offset", 0)
            })
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        check(AlarmRefreshEngine.refresh(context)) { "Real OS reservation failed" }
        return JSONObject().put("firstSlot", full.format(first.time)).put("firstEpoch", first.timeInMillis)
            .put("normalSlot", full.format(later.time)).put("normalEpoch", later.timeInMillis)
            .put("label", label).put("durationMinutes", 1)
    }
}
