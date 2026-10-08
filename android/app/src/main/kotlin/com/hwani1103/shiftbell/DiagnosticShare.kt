package com.hwani1103.shiftbell

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/** Private cached attachment works on all supported Android versions. */
object DiagnosticShare {
    fun prepare(context: Context, title: String, subject: String, body: String): Intent {
        val directory = File(context.cacheDir, "diagnostic_share").apply { mkdirs() }
        // Keep recent drafts available to receiving apps; retire stale files only.
        directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 7L * 86400000 }
            ?.forEach { it.delete() }
        val file = File(directory, "ShiftBell_Diag_${System.currentTimeMillis()}.txt")
        file.writeText(DiagReport.buildSnapshot(context) +
            "\n=== 기록(오래된 것 → 최근) ===\n" + DiagLog.readAll(context), Charsets.UTF_8)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.diagnostics", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_EMAIL, arrayOf("lowvibe07@gmail.com"))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            clipData = ClipData(file.name, arrayOf("text/plain"), ClipData.Item(uri))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // Suggest installed mail apps, while the standard chooser also allows
        // another sharing app or a file-storage target. No account access/login.
        val mail = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        val emailTargets = context.packageManager.queryIntentActivities(mail, 0)
            .map { it.activityInfo.packageName }.distinct()
            .map { Intent(send).setPackage(it) }
            .filter { it.resolveActivity(context.packageManager) != null }
        return Intent.createChooser(send, title).apply {
            if (emailTargets.isNotEmpty()) {
                putExtra(Intent.EXTRA_INITIAL_INTENTS, emailTargets.take(2).toTypedArray())
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
}
