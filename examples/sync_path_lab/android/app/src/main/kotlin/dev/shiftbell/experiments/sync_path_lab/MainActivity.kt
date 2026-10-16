package dev.shiftbell.experiments.sync_path_lab

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioAttributes
import android.media.SoundPool

class MainActivity : FlutterActivity() {
    private var effects: SoundPool? = null
    private val samples = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val streams = ArrayDeque<Int>()
    private var foreground = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_paths/effects")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        try {
                            initializeEffects()
                            result.success(null)
                        } catch (error: Exception) {
                            releaseEffects()
                            result.error("audio_unavailable", "Effects unavailable", null)
                        }
                    }
                    "play" -> {
                        val sample = samples[call.arguments as? String]
                        if (foreground && sample != null && loaded.contains(sample)) {
                            // Limit overlap and keep stop() bounded during long sessions.
                            while (streams.size >= 3) effects?.stop(streams.removeFirst())
                            val stream = effects?.play(sample, .65f, .65f, 1, 0, 1f) ?: 0
                            if (stream != 0) streams.addLast(stream)
                        }
                        result.success(null)
                    }
                    "stop" -> { stopEffects(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun initializeEffects() {
        if (effects != null) return
        val pool = SoundPool.Builder().setMaxStreams(3)
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        effects = pool
        pool.setOnLoadCompleteListener { current, id, status ->
            if (current === effects && status == 0) loaded.add(id)
        }
        for (name in listOf("select", "route", "undo", "start", "failure", "clear")) {
            assets.openFd("sync_paths_audio/$name.wav").use { descriptor ->
                samples[name] = pool.load(descriptor, 1)
            }
        }
    }

    private fun stopEffects() {
        for (stream in streams) effects?.stop(stream)
        streams.clear()
    }

    private fun releaseEffects() {
        stopEffects()
        effects?.release()
        effects = null
        loaded.clear()
        samples.clear()
    }

    override fun onResume() { super.onResume(); foreground = true }
    override fun onPause() {
        foreground = false
        stopEffects()
        super.onPause()
    }
    override fun onDestroy() { releaseEffects(); super.onDestroy() }
}
