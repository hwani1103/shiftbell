package com.hwani1103.shiftbell

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject

/** Explicit USB audit only. No production APK includes this instrumentation. */
class DevAlarmAuditInstrumentation : Instrumentation() {
    private lateinit var arguments: Bundle

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        this.arguments = arguments ?: Bundle()
        start()
    }

    override fun onStart() {
        val result = Bundle()
        try {
            check(targetContext.packageName == "com.hwani1103.shiftbell.dev")
            if (arguments.getString("action") == "backup_storage") {
                val report = DevBackupStorageAudit.run(this)
                result.putString("stream", report.toString() + "\n")
                finish(Activity.RESULT_OK, result)
                return
            }
            check(arguments.getString("action") == "partial_refresh")
            val expected = arguments.getString("expectedIds")!!.split(',').map { it.toInt() }.toSet()
            check(expected.size >= 3) { "Explicit synthetic alarm IDs are required" }
            val context = targetContext
            val db = DatabaseHelper.getInstance(context).getWritableDatabaseWithRetry()!!
            fun rows(): String {
                val array = JSONArray()
                db.rawQuery("SELECT * FROM alarms ORDER BY id", null).use { c ->
                    while (c.moveToNext()) {
                        val row = JSONObject()
                        c.columnNames.forEachIndexed { i, name -> row.put(name, if (c.isNull(i)) JSONObject.NULL else c.getString(i)) }
                        array.put(row)
                    }
                }
                return array.toString()
            }
            val ids = mutableSetOf<Int>()
            db.rawQuery("SELECT id FROM alarms", null).use { c -> while (c.moveToNext()) ids += c.getInt(0) }
            check(ids == expected) { "Fixture IDs differ; refusing to touch alarms" }
            check(AlarmWakeScheduler.failedIds(context).isEmpty())
            val before = rows()
            var count = 0
            var failedId = -1
            val registered = mutableSetOf<Int>()
            val callback: (Context, Int, Long, String) -> Unit = { c, id, at, label ->
                check(!db.inTransaction()) { "OS scheduling before DB commit" }
                count++
                if (count == 2) {
                    failedId = id
                    AlarmWakeScheduler.cancelRaw(c, id)
                    throw IllegalStateException("Explicit one-ID USB audit failure")
                }
                AlarmWakeScheduler.scheduleRaw(c, id, at, label)
                registered += id
            }
            try {
                AlarmRefreshEngine.doRefresh(context, callback)
                check(failedId in expected && registered.size == expected.size - 1)
                check(AlarmWakeScheduler.failedIds(context) == setOf(failedId))
                check(rows() == before) { "Failed OS scheduling changed committed DB rows" }
                // Host reads dumpsys during this bounded pause to verify exactly one missing OS reservation.
                sendStatus(10, Bundle().apply { putString("partial", JSONObject().put("failedId", failedId).put("registered", JSONArray(registered.sorted())).toString()) })
                Thread.sleep(12000)
            } finally {
                AlarmWakeScheduler.retryFailed(context)
            }
            check(AlarmWakeScheduler.failedIds(context).isEmpty())
            check(rows() == before)
            result.putString("stream", "PASS partial refresh: committed DB preserved, one failed ID tracked, retry cleared failure; host must compare OS reservations.\n")
            finish(Activity.RESULT_OK, result)
        } catch (failure: Throwable) {
            result.putString("stream", failure.stackTraceToString())
            finish(Activity.RESULT_CANCELED, result)
        }
    }
}
