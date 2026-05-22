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
                val parsed = parseWearRoutesPushArgs(args, System.currentTimeMillis())
                if (parsed == null) {
                    result.error("bad_args", "push needs a Map", null)
                    return
                }
                val req = PutDataMapRequest.create(PATH).apply {
                    dataMap.putString("routes_json", parsed.routesJson)
                    dataMap.putLong("updated_at_ms", parsed.updatedAtMs)
                }
                dataClient.putDataItem(req.asPutDataRequest().setUrgent())
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("put_failed", it.message, null) }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val PATH = "/saved_routes"
    }
}

/// Pure data class for the parsed push args. Exposed at file scope
/// so the unit-test source set can construct + inspect instances
/// without booting the Method-channel bridge.
data class WearRoutesPushArgs(
    val routesJson: String,
    val updatedAtMs: Long,
)

/// Pure arg parser for the `run_app/wear_routes` push method. Extracted
/// from [WearRoutesBridge.onMethodCall] so the input-tolerance contract
/// is unit-testable on a host JVM without the Wearable Data Layer.
///
/// Returns null when [args] is null — the bridge surfaces this as a
/// `bad_args` error result. Otherwise yields a populated args struct
/// using the same fallbacks the bridge ships:
///
/// * `routes_json` defaults to `"[]"` when missing or non-string.
/// * `updated_at_ms` defaults to [nowMs] when missing or non-numeric.
///
/// The fallbacks exist so an older Dart writer (pre-stamp-aware) that
/// only sends `routes_json` still produces a valid DataItem; the
/// watch's stale-push gate then accepts the [nowMs] stamp as a
/// one-shot first-push (see `shouldApplyRoutesPush` in the watch
/// app).
internal fun parseWearRoutesPushArgs(
    args: Map<String, Any?>?,
    nowMs: Long,
): WearRoutesPushArgs? {
    if (args == null) return null
    val routesJson = (args["routes_json"] as? String) ?: "[]"
    val updatedAtMs = (args["updated_at_ms"] as? Number)?.toLong() ?: nowMs
    return WearRoutesPushArgs(routesJson, updatedAtMs)
}
