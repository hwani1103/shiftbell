package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration

/** Bound app-owned native alarm UI without changing the device setting. */
object AppTextScale {
    const val MAX_SCALE = 1.3f

    fun context(base: Context): Context {
        // Override only fontScale so folding, density and locale still follow
        // the underlying display configuration.
        val config = Configuration()
        config.fontScale = base.resources.configuration.fontScale.coerceAtMost(MAX_SCALE)
        return base.createConfigurationContext(config)
    }
}
