package com.hwani1103.shiftbell

import android.Manifest
import android.app.Activity
import android.os.Build

/** Completes even when Android returns empty arrays after Back/swipe dismissal.
 * The callback reports route completion, never permission approval.
 */
internal class NotificationPermissionRequest {
    companion object { const val REQUEST_CODE = 9082 }
    private var pending: ((Boolean) -> Unit)? = null

    fun launch(activity: Activity, complete: (Boolean) -> Unit) {
        if (pending != null) { complete(false); return }
        if (Build.VERSION.SDK_INT < 33) { complete(true); return }
        pending = complete
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
        } catch (_: Exception) { finish(false) }
    }

    fun onResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        finish(true)
        return true
    }

    fun dispose() { finish(false) }

    private fun finish(completed: Boolean) {
        val callback = pending
        pending = null
        callback?.invoke(completed)
    }
}
