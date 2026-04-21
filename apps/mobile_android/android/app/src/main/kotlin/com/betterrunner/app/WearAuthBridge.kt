package com.betterrunner.app

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Pushes the current Supabase session to the paired Wear OS watch via the
/// Wearable Data Layer. Dart side (`lib/wear_auth_bridge.dart`) subscribes to
/// `Supabase.instance.client.auth.onAuthStateChange` and calls `push` /
/// `clear` through the `run_app/wear_auth` method channel.
///
/// `DataClient` transparently handles the case of no watch paired — the
/// DataItem just sits in the local device's graph until a watch shows up.
class WearAuthBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/wear_auth")
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
                val req = PutDataMapRequest.create(PATH).apply {
                    dataMap.putString("access_token", args["access_token"] as String)
                    dataMap.putString("refresh_token", args["refresh_token"] as String)
                    dataMap.putString("user_id", args["user_id"] as String)
                    dataMap.putString("base_url", args["base_url"] as String)
                    dataMap.putString("anon_key", args["anon_key"] as String)
                    dataMap.putLong("expires_at_ms", (args["expires_at_ms"] as Number).toLong())
                }
                dataClient.putDataItem(req.asPutDataRequest().setUrgent())
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("put_failed", it.message, null) }
            }
            "clear" -> {
                val uri = Uri.Builder().scheme("wear").path(PATH).build()
                dataClient.deleteDataItems(uri)
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("delete_failed", it.message, null) }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val PATH = "/supabase_session"
    }
}
