package com.hwani1103.shiftbell

import android.app.Instrumentation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Executes the real Native writer against uniquely named, disposable MediaStore files. */
internal object DevBackupStorageAudit {
    fun run(instrumentation: Instrumentation): JSONObject {
        val context = instrumentation.targetContext
        check(context.packageName == "com.hwani1103.shiftbell.dev")
        val token = UUID.randomUUID().toString().replace("-", "")
        val prefix = "ShiftBell_Audit_${token}_"
        val preferenceName = "usb_backup_audit_$token"
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val prefs = context.getSharedPreferences(preferenceName, Context.MODE_PRIVATE)
        val originalPrefs = context.getSharedPreferences("backup_prefs", Context.MODE_PRIVATE).all.toMap()
        fun files(wantedPrefix: String): Map<Uri, String> {
            val found = linkedMapOf<Uri, String>()
            resolver.query(collection, arrayOf("_id", "_display_name"), null, null, null)!!.use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(1)
                    if (name.startsWith(wantedPrefix)) found[ContentUris.withAppendedId(collection, c.getLong(0))] = name
                }
            }
            return found
        }
        fun bytes(uri: Uri) = resolver.openInputStream(uri)!!.use { it.readBytes() }
        fun hashes(wantedPrefix: String) = files(wantedPrefix).keys.associateWith { uri ->
            MessageDigest.getInstance("SHA-256").digest(bytes(uri)).joinToString("") { "%02x".format(it) }
        }
        val originalFiles = hashes("ShiftBell_Backup_dev_")
        val content = """{"schemaVersion":26,"tables":{"shift_schedule":[]},"audit":true}"""
        fun create(suffix: String): Uri {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, prefix + suffix)
                put(MediaStore.Downloads.MIME_TYPE, "application/json")
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/ShiftBell/")
            }
            val uri = resolver.insert(collection, values)!!
            resolver.openOutputStream(uri, "w")!!.use { it.write(content.toByteArray()) }
            return uri
        }
        var activity: MainActivity? = null
        instrumentation.runOnMainSync {
            activity = MainActivity()
            val isolated = object : ContextWrapper(context) {
                override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                    if (name == "backup_prefs") prefs else super.getSharedPreferences(name, mode)
            }
            ContextWrapper::class.java.getDeclaredMethod("attachBaseContext", Context::class.java).apply {
                isAccessible = true
                invoke(activity, isolated)
            }
            MainActivity::class.java.getDeclaredField("BACKUP_DISPLAY_NAME_PREFIX\$delegate").apply {
                isAccessible = true
                set(activity, lazy { prefix })
            }
        }
        val writer = MainActivity::class.java.getDeclaredMethod("writeBackupFile", String::class.java, BackupFileNaming.Kind::class.java).apply { isAccessible = true }
        fun write(value: String, kind: BackupFileNaming.Kind) = writer.invoke(activity, value, kind) as Boolean
        val report = JSONObject()
        try {
            val oldLegacy = create("261001_1200.json")
            val previousLegacy = create("260930_1200.json")
            val oldManual = create("manual_261001_120000.json")
            val oldAuto = create("auto_261001_120000.json")
            prefs.edit().putString("last_backup_uri", oldLegacy.toString())
                .putString("prev_backup_uri", previousLegacy.toString())
                .putString("last_backup_uri_manual", oldManual.toString())
                .putString("last_backup_uri_auto", oldAuto.toString()).commit()
            val before = hashes(prefix)
            val beforePrefs = prefs.all.toMap()
            check(!write("{\"incomplete\":true}", BackupFileNaming.Kind.AUTO))
            check(hashes(prefix) == before && prefs.all == beforePrefs)
            report.put("readbackValidationFailurePreservedAllFour", true)
            check(write(content, BackupFileNaming.Kind.MANUAL))
            check(files(prefix).size == 4)
            check(oldLegacy in files(prefix) && previousLegacy in files(prefix) && oldAuto in files(prefix))
            check(oldManual !in files(prefix))
            val manual = Uri.parse(prefs.getString("last_backup_uri_manual", null)!!)
            check(write(content, BackupFileNaming.Kind.AUTO))
            check(files(prefix).size == 2 && manual in files(prefix))
            check(oldLegacy !in files(prefix) && previousLegacy !in files(prefix) && oldAuto !in files(prefix))
            check(!prefs.contains("last_backup_uri") && !prefs.contains("prev_backup_uri"))
            report.put("legacyCleanupOnlyAfterAutoSuccess", true).put("manualSlotRetained", true)
            instrumentation.sendStatus(11, Bundle().apply { putString("backupMigration", report.toString()) })

            // Remove only the uniquely named pending test row while the real writer is running.
            // This induces an actual MediaStore write/read/publish failure without filling storage.
            val successful = hashes(prefix)
            val successPrefs = prefs.all.toMap()
            val running = AtomicBoolean(true)
            val removed = AtomicReference<Uri?>(null)
            val injectorError = AtomicReference<Throwable?>(null)
            val worker = Thread {
                try {
                    while (running.get() && removed.get() == null) {
                        val query = Bundle().apply { putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE) }
                        resolver.query(collection, arrayOf("_id", "_display_name", "is_pending"), query, null)!!.use { c ->
                            while (c.moveToNext()) {
                                if (c.getString(1).startsWith(prefix) && c.getInt(2) == 1) {
                                    val uri = ContentUris.withAppendedId(collection, c.getLong(0))
                                    check(uri !in successful)
                                    if (resolver.delete(uri, null, null) == 1) removed.set(uri)
                                }
                            }
                        }
                        Thread.sleep(1)
                    }
                } catch (failure: Throwable) { injectorError.set(failure) }
            }
            worker.start()
            val succeeded: Boolean
            try {
                val large = JSONObject(content).put("padding", "x".repeat(8 * 1024 * 1024)).toString()
                succeeded = write(large, BackupFileNaming.Kind.AUTO)
            } finally {
                running.set(false)
                worker.join(5000)
            }
            check(!worker.isAlive)
            injectorError.get()?.let { throw it }
            check(removed.get() != null && !succeeded) { "Pending-file failure was not intercepted" }
            check(hashes(prefix) == successful && prefs.all == successPrefs)
            report.put("actualPendingFileFailurePreservedBothSlots", true)
            check(hashes("ShiftBell_Backup_dev_") == originalFiles)
            check(context.getSharedPreferences("backup_prefs", Context.MODE_PRIVATE).all == originalPrefs)
            report.put("originalBackupHashesAndMetadataUnchanged", true)
        } finally {
            for (uri in files(prefix).keys) resolver.delete(uri, null, null)
            context.deleteSharedPreferences(preferenceName)
            check(files(prefix).isEmpty())
            check(hashes("ShiftBell_Backup_dev_") == originalFiles)
            check(context.getSharedPreferences("backup_prefs", Context.MODE_PRIVATE).all == originalPrefs)
        }
        report.put("temporaryFilesRemoved", true)
        return report
    }
}
