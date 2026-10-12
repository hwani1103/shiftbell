package com.hwani1103.shiftbell

import android.content.Context
import android.content.SharedPreferences

/** Device-protected global preference; never stores a running round's temporary choice. */
object SnoozeDefaults {
    private const val KEY = "default_minutes"
    internal var commitOverride: ((SharedPreferences.Editor) -> Boolean)? = null
    private fun prefs(context: Context) = context.createDeviceProtectedStorageContext()
        .getSharedPreferences("snooze_defaults", Context.MODE_PRIVATE)
    fun valid(minutes: Int) = minutes == 5 || minutes == 10 || minutes == 15
    fun read(context: Context): Int = try {
        prefs(context).getInt(KEY, 5).takeIf(::valid) ?: 5
    } catch (_: ClassCastException) { 5 }

    /** A failed commit must not become a successful in-memory preference. */
    fun write(context: Context, minutes: Int): Boolean {
        require(valid(minutes))
        val preferences = prefs(context)
        val previous = read(context)
        val editor = preferences.edit().putInt(KEY, minutes)
        val saved = commitOverride?.invoke(editor) ?: editor.commit()
        if (!saved) preferences.edit().putInt(KEY, previous).commit()
        return saved
    }
}
