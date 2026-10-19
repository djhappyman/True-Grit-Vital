package dev.truegrit.vital

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/** Observes platform IDs only; Dart checks them against its admitted IANA data. */
class DeviceZone(private val context: Context, messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "true_grit_vital/device_zone")
    private val events = EventChannel(messenger, "true_grit_vital/device_zone_changes")
    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            // Intent payloads are not trusted as zone identifiers.
            if (intent?.action == Intent.ACTION_TIMEZONE_CHANGED ||
                intent?.action == Intent.ACTION_TIME_CHANGED) changed()
        }
    }

    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method != "read") result.notImplemented()
            else {
                try { result.success(TimeZone.getDefault().id) }
                catch (_: Exception) { result.error("zone_unavailable", null, null) }
            }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                unregister()
                sink = eventSink
                val filter = IntentFilter().apply {
                    addAction(Intent.ACTION_TIMEZONE_CHANGED)
                    addAction(Intent.ACTION_TIME_CHANGED)
                }
                try {
                    if (Build.VERSION.SDK_INT >= 33) {
                        context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("DEPRECATION")
                        context.registerReceiver(receiver, filter)
                    }
                    registered = true
                } catch (_: Exception) {
                    sink?.error("zone_events_unavailable", null, null)
                }
            }
            override fun onCancel(arguments: Any?) { unregister(); sink = null }
        })
    }

    fun changed() { sink?.success(null) }
    private fun unregister() {
        if (registered) {
            context.unregisterReceiver(receiver)
            registered = false
        }
    }
    fun dispose() {
        unregister()
        sink = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
