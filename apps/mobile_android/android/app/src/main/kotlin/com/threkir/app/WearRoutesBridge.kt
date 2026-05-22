package com.threkir.app

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Pushes the user's starred routes to the paired Wear OS watch via the
/// Wearable Data Layer. Dart side (`lib/wear_routes_bridge.dart`)
/// subscribes to `LocalRouteStore` changes and calls `push` with a JSON
/// array of `{id, name, distance_m, waypoints:[{lat,lng}]}`.
///
/// Sibling of `WearAuthBridge` — same pattern, different DataLayer path.
/// `DataClient` transparently handles the case of no watch paired — the
/// DataItem sits in the local device's graph until a watch shows up.
class WearRoutesBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/wear_routes")
    private val dataClient = Wearable.getDataClient(context)

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "push" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                if (args == null) {
                    result.error("bad_args", "push needs a Map", null)
                    return
                }
                val routesJson = args["routes_json"] as? String ?: "[]"
                val updatedAtMs = (args["updated_at_ms"] as? Number)?.toLong()
                    ?: System.currentTimeMillis()
                val req = PutDataMapRequest.create(PATH).apply {
                    dataMap.putString("routes_json", routesJson)
                    dataMap.putLong("updated_at_ms", updatedAtMs)
                }
                dataClient.putDataItem(req.asPutDataRequest().setUrgent())
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("put_failed", it.message, null) }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val PATH = "/saved_routes"
    }
}
