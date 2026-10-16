package com.hwani1103.shiftbell

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Game-only media effects. No alarm stream, volume, focus or permission changes. */
class SyncPathsAudio(
    private val context: Context,
    messenger: BinaryMessenger,
    private val lifecycle: Lifecycle,
) : DefaultLifecycleObserver {
    private val channel = MethodChannel(messenger, "sync_paths/effects")
    private var effects: SoundPool? = null
    private val samples = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val streams = ArrayDeque<Int>()
    private var foreground = false

    init {
        lifecycle.addObserver(this)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialize" -> { initialize(); result.success(null) }
                    "play" -> { play(call.arguments as? String); result.success(null) }
                    "stop" -> { stop(); result.success(null) }
                    "release" -> { release(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                release()
                result.error("audio_unavailable", "Effects unavailable", null)
            }
        }
    }

    private fun initialize() {
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
            context.assets.openFd("sync_paths_audio/$name.wav").use {
                samples[name] = pool.load(it, 1)
            }
        }
    }

    private fun play(name: String?) {
        val sample = samples[name] ?: return
        if (!foreground || !loaded.contains(sample)) return
        while (streams.size >= 3) effects?.stop(streams.removeFirst())
        val stream = effects?.play(sample, .65f, .65f, 1, 0, 1f) ?: 0
        if (stream != 0) streams.addLast(stream)
    }

    private fun stop() {
        for (stream in streams) effects?.stop(stream)
        streams.clear()
    }

    private fun release() {
        stop()
        effects?.release()
        effects = null
        samples.clear()
        loaded.clear()
    }

    override fun onResume(owner: LifecycleOwner) { foreground = true }
    override fun onPause(owner: LifecycleOwner) { foreground = false; stop() }
    override fun onDestroy(owner: LifecycleOwner) = dispose()

    fun dispose() {
        release()
        channel.setMethodCallHandler(null)
        lifecycle.removeObserver(this)
    }
}
