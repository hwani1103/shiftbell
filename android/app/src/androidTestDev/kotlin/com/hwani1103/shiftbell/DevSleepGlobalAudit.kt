package com.hwani1103.shiftbell

import android.app.Instrumentation
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.PowerManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/** Explicit dev USB audit. Synthetic rows are transactionally rolled back. */
object DevSleepGlobalAudit {
    fun run(test: Instrumentation): JSONObject {
        val result = JSONObject()
        var failure: Throwable? = null
        test.runOnMainSync {
            try {
                val base = test.targetContext
                check(base.packageName == "com.hwani1103.shiftbell.dev")
                check(base.getSystemService(PowerManager::class.java).isInteractive)
                val db = DatabaseHelper.getInstance(base).getWritableDatabaseWithRetry()!!
                val prefs = base.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val keys = listOf("flutter.condition_tab_enabled", "flutter.sleep_global_enabled_v1")
                val before = keys.associateWith { if (prefs.contains(it)) prefs.getBoolean(it, false) else null }
                val state = base.createDeviceProtectedStorageContext().getSharedPreferences("sleep_detection_state", Context.MODE_PRIVATE)
                val firstOff = if (state.contains("first_off_sample_at")) state.getLong("first_off_sample_at", -1) else null
                val cases = JSONArray()
                db.beginTransaction()
                try {
                    db.delete("sleep_records", null, null)
                    fun count(): Int = db.rawQuery("SELECT COUNT(*) FROM sleep_records", null).use { it.moveToFirst(); it.getInt(0) }
                    fun seed(minutes: Int, source: String): Long {
                        val now = System.currentTimeMillis()
                        return db.insertOrThrow("sleep_records", null, ContentValues().apply {
                            put("start_time", SleepTimestamp.format(now - minutes * 60000L))
                            putNull("end_time"); put("source", source)
                            put("status", if(source == "AUTO_DETECTED") "PENDING_CONFIRMATION" else "CONFIRMED")
                            put("created_at", SleepTimestamp.format(now)); put("updated_at", SleepTimestamp.format(now))
                        })
                    }
                    for (tag in listOf("ko-KR", "en-US", "de-DE", "pt-BR", "hi-IN")) {
                        val config = Configuration(base.resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) }
                        val context = base.createConfigurationContext(config)
                        val receiver = SleepWidgetActionReceiver()
                        fun action(value: String) = receiver.onReceive(context, Intent(value))
                        prefs.edit().putBoolean(keys[0], false).putBoolean(keys[1], false).commit()
                        check(!SleepDetectionScheduler.isSleepDetectionEnabled(context))
                        action(SleepWidgetProvider.ACTION_SLEEP)
                        check(count() == 0) { "Disabled widget wrote data: $tag" }
                        prefs.edit().putBoolean(keys[0], true).putBoolean(keys[1], true).commit()
                        check(SleepDetectionScheduler.isSleepDetectionEnabled(context))
                        action(SleepWidgetProvider.ACTION_SLEEP); check(count() == 1)
                        action(SleepWidgetProvider.ACTION_SLEEP); check(count() == 1)
                        action(SleepWidgetProvider.ACTION_WAKE); check(count() == 0)
                        seed(3, "MANUAL"); action(SleepWidgetProvider.ACTION_WAKE)
                        db.rawQuery("SELECT source, status, end_time FROM sleep_records", null).use {
                            check(it.moveToFirst()); check(it.getString(0) == "WIDGET_MANUAL")
                            check(it.getString(1) == "CONFIRMED"); check(SleepTimestamp.parse(it.getString(2)) != null)
                        }
                        db.delete("sleep_records", null, null)
                        seed(119, "AUTO_DETECTED"); action(SleepWidgetProvider.ACTION_WAKE); check(count() == 0)
                        seed(121, "AUTO_DETECTED"); action(SleepWidgetProvider.ACTION_WAKE)
                        db.rawQuery("SELECT status, end_time FROM sleep_records", null).use {
                            check(it.moveToFirst()); check(it.getString(0) == "CONFIRMED"); check(!it.isNull(1))
                        }
                        db.delete("sleep_records", null, null)
                        seed(299, "AUTO_DETECTED"); SleepDetectionReceiver.checkNow(context); check(count() == 0)
                        seed(301, "AUTO_DETECTED"); SleepDetectionReceiver.checkNow(context)
                        db.rawQuery("SELECT status, end_time FROM sleep_records", null).use {
                            check(it.moveToFirst()); check(it.getString(0) == "PENDING_CONFIRMATION"); check(!it.isNull(1))
                        }
                        db.delete("sleep_records", null, null)
                        seed(600, "AUTO_DETECTED"); SleepDetectionReceiver.checkNow(context)
                        db.rawQuery("SELECT start_time, end_time, status FROM sleep_records", null).use {
                            check(it.moveToFirst())
                            check(SleepTimestamp.parse(it.getString(1))!! - SleepTimestamp.parse(it.getString(0))!! == 9 * 3600000L)
                            check(it.getString(2) == "PENDING_CONFIRMATION")
                        }
                        db.delete("sleep_records", null, null)
                        cases.put(JSONObject().put("locale", tag).put("passed", true)
                            .put("sleepButton", context.getString(R.string.sleep_widget_sleep))
                            .put("wakeButton", context.getString(R.string.sleep_widget_wake))
                            .put("checks", "disabled write blocked; duplicate start ignored; <2min manual discarded; widget manual confirmed; auto <120min discarded; widget auto confirmed; auto <300min discarded; >=300min pending; 9h cap pending"))
                    }
                    result.put("passed", true).put("cases", cases)
                        .put("scope", "Actual Android receiver/database execution with synthetic elapsed-time records; not natural overnight detection or launcher UI")
                } finally {
                    db.endTransaction() // Deliberately no setTransactionSuccessful: preserve existing rows.
                    val editor = prefs.edit()
                    before.forEach { (key, value) -> if(value == null) editor.remove(key) else editor.putBoolean(key, value) }
                    editor.commit()
                    val stateEditor = state.edit()
                    if(firstOff == null) stateEditor.remove("first_off_sample_at") else stateEditor.putLong("first_off_sample_at", firstOff)
                    stateEditor.commit()
                    SleepDetectionScheduler.ensureScheduled(base)
                    SleepWidgetProvider.requestUpdate(base)
                }
            } catch (error: Throwable) { failure = error }
        }
        failure?.let { throw it }
        return result
    }
}
