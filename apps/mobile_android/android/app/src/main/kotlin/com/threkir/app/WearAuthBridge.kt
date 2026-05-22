package com.threkir.app

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
                val parsed = try {
                    parseWearAuthPushArgs(args)
                } catch (e: WearAuthArgsException) {
                    result.error("bad_args", e.message, null)
                    return
                }
                val req = PutDataMapRequest.create(PATH).apply {
                    dataMap.putString("access_token", parsed.accessToken)
                    dataMap.putString("refresh_token", parsed.refreshToken)
                    dataMap.putString("user_id", parsed.userId)
                    dataMap.putString("base_url", parsed.baseUrl)
                    dataMap.putString("anon_key", parsed.anonKey)
                    dataMap.putLong("expires_at_ms", parsed.expiresAtMs)
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
        const val PATH = "/supabase_session"
    }
}

/// Parsed view of the `/supabase_session` push args. All six fields
/// are required — a session push with any field missing means the
/// Dart side isn't holding a full session yet, which the bridge
/// surfaces as `bad_args` rather than shipping a half-formed
/// DataItem that the watch's SessionBridge would silently apply.
data class WearAuthPushArgs(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val baseUrl: String,
    val anonKey: String,
    val expiresAtMs: Long,
)

/// Thrown by [parseWearAuthPushArgs] when the input is null or any
/// required field is missing or wrong-typed. The bridge surfaces the
/// message as a `bad_args` MethodChannel error.
class WearAuthArgsException(message: String) : IllegalArgumentException(message)

/// Pure parser for the `run_app/wear_auth` push method's args.
/// Extracted from [WearAuthBridge.onMethodCall] so the input
/// validation contract is unit-testable on a host JVM.
///
/// Unlike `parseWearRoutesPushArgs` (which has tolerant fallbacks
/// because every field is optional from the watch's point of view),
/// this parser is strict: every session field is load-bearing for
/// the watch to authenticate against Supabase. A missing field is
/// always a bug on the Dart side — surface it loudly.
internal fun parseWearAuthPushArgs(args: Map<String, Any?>?): WearAuthPushArgs {
    if (args == null) throw WearAuthArgsException("push needs a Map")
    val accessToken = args["access_token"] as? String
        ?: throw WearAuthArgsException("access_token missing or wrong type")
    val refreshToken = args["refresh_token"] as? String
        ?: throw WearAuthArgsException("refresh_token missing or wrong type")
    val userId = args["user_id"] as? String
        ?: throw WearAuthArgsException("user_id missing or wrong type")
    val baseUrl = args["base_url"] as? String
        ?: throw WearAuthArgsException("base_url missing or wrong type")
    val anonKey = args["anon_key"] as? String
        ?: throw WearAuthArgsException("anon_key missing or wrong type")
    val expiresAtMs = (args["expires_at_ms"] as? Number)?.toLong()
        ?: throw WearAuthArgsException("expires_at_ms missing or wrong type")
    return WearAuthPushArgs(
        accessToken = accessToken,
        refreshToken = refreshToken,
        userId = userId,
        baseUrl = baseUrl,
        anonKey = anonKey,
        expiresAtMs = expiresAtMs,
    )
}
