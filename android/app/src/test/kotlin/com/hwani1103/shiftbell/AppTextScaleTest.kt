package com.hwani1103.shiftbell

import android.content.res.Configuration
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AppTextScaleTest {
    @Test fun appTypographyIsFixedWithoutMutatingSystem() {
        val app = ApplicationProvider.getApplicationContext<Context>()
        for (scale in listOf(.85f, 1f, 1.09f, 1.25f, 1.28f, 1.3f, 1.31f, 1.6f, 2f)) {
            val configuration = Configuration(app.resources.configuration).apply { fontScale = scale }
            val source = app.createConfigurationContext(configuration)
            val bounded = AppTextScale.context(source)
            assertEquals(1f, bounded.resources.configuration.fontScale, .00001f)
            assertEquals(scale, source.resources.configuration.fontScale, .00001f)
        }
    }
}
