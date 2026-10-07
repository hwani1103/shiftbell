package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration

/** Bound app-owned native alarm UI without changing the device setting. */
object AppTextScale {
    const val MAX_SCALE = 1.3f

    fun context(base: Context): Context {
        // Keep display dimensions/density inherited. Explicitly carry the
        // parent's current locale when creating a fresh bounded-font context.
        val config = Configuration()
        config.fontScale = base.resources.configuration.fontScale.coerceAtMost(MAX_SCALE)
        config.setLocales(base.resources.configuration.locales)
        return base.createConfigurationContext(config)
    }
}
