package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.Configuration

/** Fix app-owned native alarm typography without changing the device setting. */
object AppTextScale {
    const val MAX_SCALE = 1f

    fun context(base: Context): Context {
        // Keep display dimensions/density inherited. Explicitly carry the
        // parent's current locale when creating a fresh fixed-font context.
        val config = Configuration()
        config.fontScale = MAX_SCALE
        config.setLocales(base.resources.configuration.locales)
        return base.createConfigurationContext(config)
    }
}
