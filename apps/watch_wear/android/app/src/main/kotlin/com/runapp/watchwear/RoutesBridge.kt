package com.runapp.watchwear

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/// Sibling of [SessionBridge] — listens at `/saved_routes` for the
/// starred-route subset the paired phone pushes via the Wearable Data
/// Layer. Without this, the watch's route picker is online-only at
/// run-start time: it fetches `is_starred=eq.true` routes from
/// Supabase whenever the pre-run screen opens, and a watch out of
/// network range falls back to whatever the previous fetch cached.
/// With the phone push, the watch's `LocalRouteStore` is kept current
/// the moment the user stars on the phone — survives cold launch
/// offline, survives an LTE-less out-and-back, and the picker shows
/// the latest list without a Supabase round-trip.
///
/// Payload shape: a single `routes_json` string carrying the same
/// `[{id, name, distance_m, waypoints:[{lat,lng}]}]` array the
/// phone's `LocalRouteStore` exposes filtered to `isStarred==true`.
class RoutesBridge(context: Context) {
    private val dataClient: DataClient = Wearable.getDataClient(context)
    private val json = Json { ignoreUnknownKeys = true }

    val events: Flow<List<SavedRoute>> = callbackFlow {
        val listener = DataClient.OnDataChangedListener { evts ->
            for (event in evts) {
                if (event.dataItem.uri.path != PATH) continue
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val dm = DataMapItem.fromDataItem(event.dataItem).dataMap
                val raw = dm.getString("routes_json") ?: continue
                val parsed = parseRoutesJson(json, raw)
                trySend(parsed)
            }
        }
        dataClient.addListener(listener)
        awaitClose { dataClient.removeListener(listener) }
    }

    suspend fun current(): List<SavedRoute>? {
        val uri = Uri.Builder().scheme("wear").path(PATH).build()
        val buffer = dataClient.getDataItems(uri).await()
        return try {
            buffer.firstOrNull()?.let { item ->
                val raw = DataMapItem.fromDataItem(item).dataMap.getString("routes_json")
                    ?: return@let null
                parseRoutesJson(json, raw)
            }
        } finally {
            buffer.release()
        }
    }

    companion object {
        const val PATH = "/saved_routes"
    }
}

/// Pure parser pulled out as a file-level helper so the JSON contract
/// is testable without booting `DataClient`. Matches the encoding in
/// `apps/mobile_android/lib/wear_routes_bridge.dart`.
internal fun parseRoutesJson(json: Json, raw: String): List<SavedRoute> {
    val arr = try {
        json.parseToJsonElement(raw) as? JsonArray ?: return emptyList()
    } catch (_: Throwable) {
        return emptyList()
    }
    return arr.mapNotNull { el ->
        val obj = el as? JsonObject ?: return@mapNotNull null
        val id = obj["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
        val name = obj["name"]?.jsonPrimitive?.contentOrNull ?: "Unnamed route"
        val distanceM = obj["distance_m"]?.jsonPrimitive?.doubleOrNull ?: 0.0
        val wpArr = obj["waypoints"]?.jsonArray ?: return@mapNotNull null
        val waypoints = wpArr.mapNotNull { wpEl ->
            val wp = wpEl as? JsonObject ?: return@mapNotNull null
            val lat = wp["lat"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
            val lng = wp["lng"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
            SavedRoute.Waypoint(lat = lat, lng = lng)
        }
        if (waypoints.size < 2) return@mapNotNull null
        SavedRoute(id = id, name = name, distanceM = distanceM, waypoints = waypoints)
    }
}
