package com.runapp.watchwear.watch_wear

import android.content.Context
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.DeltaDataType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Live heart-rate readings from Wear OS Health Services, surfaced to
/// Flutter via a method channel (`watch_wear/hr`) and an event channel
/// (`watch_wear/hr/stream`). The Dart `HeartRateService` owns the lifecycle.
class HeartRatePlugin(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "watch_wear/hr")
    private val eventChannel = EventChannel(messenger, "watch_wear/hr/stream")
    private val measureClient = HealthServices.getClient(context).measureClient
    private var eventSink: EventChannel.EventSink? = null
    private var registered = false

    private val callback = object : MeasureCallback {
        override fun onAvailabilityChanged(
            dataType: DeltaDataType<*, *>,
            availability: Availability
        ) {
            if (availability is DataTypeAvailability) {
                eventSink?.success(mapOf("availability" to availability.name))
            }
        }

        override fun onDataReceived(data: DataPointContainer) {
            val points = data.getData(DataType.HEART_RATE_BPM)
            for (p in points) {
                eventSink?.success(mapOf("bpm" to p.value))
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (!registered) {
                    measureClient.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
                    registered = true
                }
                result.success(null)
            }
            "stop" -> {
                if (registered) {
                    measureClient.unregisterMeasureCallbackAsync(
                        DataType.HEART_RATE_BPM,
                        callback
                    )
                    registered = false
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
