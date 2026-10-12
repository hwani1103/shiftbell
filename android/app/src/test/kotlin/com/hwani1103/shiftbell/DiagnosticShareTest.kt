package com.hwani1103.shiftbell

import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import androidx.core.content.FileProvider
import java.io.File

// AndroidX's path strategy uses Unix separators; Robolectric runs on Windows.
// URI grants/composition and file contents are tested here; real provider reads
// are verified separately through the USB receiving mail app.
@Implements(FileProvider::class)
class WindowsDiagnosticFileProviderShadow {
    companion object {
        @JvmStatic @Implementation
        fun getUriForFile(context: Context, authority: String, file: File): Uri =
            Uri.parse("content://$authority/diagnostic_logs/${file.name}")
    }
}

@RunWith(RobolectricTestRunner::class)
class DiagnosticShareTest {
    @Test @Config(sdk = [28, 34], shadows = [WindowsDiagnosticFileProviderShadow::class])
    fun `shares readable private txt attachment and recipient without login`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val chooser = DiagnosticShare.prepare(context, "share", "subject", "body")
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("text/plain", send.type)
        assertArrayEquals(arrayOf("lowvibe07@gmail.com"), send.getStringArrayExtra(Intent.EXTRA_EMAIL))
        assertEquals("subject", send.getStringExtra(Intent.EXTRA_SUBJECT))
        assertTrue(send.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        val uri = send.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)!!
        assertEquals("content", uri.scheme)
        assertEquals("${context.packageName}.diagnostics", uri.authority)
        assertEquals(uri, send.clipData!!.getItemAt(0).uri)
        val text = File(context.cacheDir, "diagnostic_share/${uri.lastPathSegment}").readText(Charsets.UTF_8)
        assertTrue(text.startsWith("=== ShiftBell 진단 파일 ==="))
        assertTrue(text.contains("=== 기록"))
        assertTrue(uri.lastPathSegment!!.endsWith(".txt"))
    }
}
