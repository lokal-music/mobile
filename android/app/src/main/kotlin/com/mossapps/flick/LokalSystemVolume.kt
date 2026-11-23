package com.mossapps.flick

import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Android media volume, independent of the direct USB/DAP gain controls. */
object LokalSystemVolume {
    fun register(messenger: BinaryMessenger, context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        fun read(): Double {
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            return if (max > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max else 0.0
        }
        MethodChannel(messenger, "lokal/system_volume").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "get" -> result.success(read())
                    "set" -> {
                        val volume = call.argument<Number>("volume")?.toDouble()
                        if (volume == null || !volume.isFinite()) {
                            result.error("bad_volume", "Expected a finite volume", null)
                        } else {
                            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val step = Math.round(volume.coerceIn(0.0, 1.0) * max).toInt()
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, step, 0)
                            result.success(read())
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: SecurityException) {
                result.error("volume_unavailable", "Android refused the media volume change", null)
            }
        }
        EventChannel(messenger, "lokal/system_volume/events").setStreamHandler(object : EventChannel.StreamHandler {
            private var observer: ContentObserver? = null
            private var receiver: BroadcastReceiver? = null
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                onCancel(null)
                var last = read()
                fun publish() {
                    val value = read()
                    if (value != last) { last = value; events.success(value) }
                }
                observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean) { publish() }
                }
                // Media-key changes arrive before AudioService persists Settings.
                // Keep the observer as a fallback for OEM implementations.
                receiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        // OEMs do not consistently include EXTRA_VOLUME_STREAM_TYPE.
                        // Re-read STREAM_MUSIC for every volume broadcast; unrelated
                        // stream changes are filtered by publish()'s value comparison.
                        if (intent?.action == "android.media.VOLUME_CHANGED_ACTION") publish()
                    }
                }
                val filter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
                if (Build.VERSION.SDK_INT >= 33) {
                    context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("DEPRECATION")
                    context.registerReceiver(receiver, filter)
                }
                context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer!!)
                events.success(last)
            }
            override fun onCancel(arguments: Any?) {
                observer?.let { context.contentResolver.unregisterContentObserver(it) }
                observer = null
                receiver?.let { context.unregisterReceiver(it) }
                receiver = null
            }
        })
    }
}
