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

/// One delivery from the phone-side push: the parsed route list plus
/// the `updated_at_ms` epoch stamp the writer embedded in the
/// DataMap. The consumer (`RunViewModel.observeRoutesBridge`) keeps
/// the most-recently-seen stamp so an out-of-order Wearable Data
/// Layer delivery (rare but possible — DataItem propagation isn't
/// strictly FIFO across reconnects) can't roll the watch back to
/// an older starred set.
data class RoutesPush(
    val routes: List<SavedRoute>,
    val updatedAtMs: Long,
)

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
/// Payload shape: `routes_json` (the same
/// `[{id, name, distance_m, waypoints:[{lat,lng}]}]` array the
/// phone's `LocalRouteStore` exposes filtered to `isStarred==true`)
/// plus `updated_at_ms` (epoch millis when the phone serialised the
/// push). The cap on the phone side is 50 routes per DataItem to
/// stay under the ~100 KB Wearable Data Layer limit; the parser
/// here just accepts whatever lands.
class RoutesBridge(context: Context) {
    private val dataClient: DataClient = Wearable.getDataClient(context)
    private val json = Json { ignoreUnknownKeys = true }

    val events: Flow<RoutesPush> = callbackFlow {
        val listener = DataClient.OnDataChangedListener { evts ->
            for (event in evts) {
                if (event.dataItem.uri.path != PATH) continue
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val dm = DataMapItem.fromDataItem(event.dataItem).dataMap
                val raw = dm.getString("routes_json") ?: continue
                val parsed = parseRoutesJson(json, raw)
                val updatedAtMs = dm.getLong("updated_at_ms")
                trySend(RoutesPush(routes = parsed, updatedAtMs = updatedAtMs))
            }
        }
        dataClient.addListener(listener)
        awaitClose { dataClient.removeListener(listener) }
    }

    suspend fun current(): RoutesPush? {
        val uri = Uri.Builder().scheme("wear").path(PATH).build()
        val buffer = dataClient.getDataItems(uri).await()
        return try {
            buffer.firstOrNull()?.let { item ->
                val dm = DataMapItem.fromDataItem(item).dataMap
                val raw = dm.getString("routes_json") ?: return@let null
                val parsed = parseRoutesJson(json, raw)
                val updatedAtMs = dm.getLong("updated_at_ms")
                RoutesPush(routes = parsed, updatedAtMs = updatedAtMs)
            }
        } finally {
            buffer.release()
        }
    }

    companion object {
        const val PATH = "/saved_routes"
    }
}

/// Stable-sort: routes whose IDs appear in [recentIds] move to the
/// front in LRU order; everything else preserves its incoming
/// (`updated_at desc`) order. Pure helper so the re-ordering math is
/// unit-testable without booting `RunViewModel`. Used by
/// `RunViewModel.sortByRecency` + `observeRoutesBridge`.
internal fun sortRoutesByRecency(
    routes: List<SavedRoute>,
    recentIds: List<String>,
): List<SavedRoute> {
    if (recentIds.isEmpty()) return routes
    val byId = routes.associateBy { it.id }
    val recents = recentIds.mapNotNull { byId[it] }
    val recentSet = recents.map { it.id }.toSet()
    val rest = routes.filter { it.id !in recentSet }
    return recents + rest
}

/// Defensive stale-push gate. Returns true when [incoming] should
/// be applied — strictly newer than [lastApplied] (or the watch has
/// never applied a push yet). Pure helper so it's unit-testable
/// without booting the ViewModel.
///
/// Wearable Data Layer usually delivers in FIFO order, but a
/// reconnect or sync after a watch reboot can deliver an older
/// DataItem after a newer one. Applying the older one would roll
/// the watch's starred set back. Compare by `updated_at_ms` and
/// drop the older.
internal fun shouldApplyRoutesPush(lastAppliedMs: Long, incoming: Long): Boolean {
    // Zero/negative timestamps are a corrupt or pre-stamp-aware
    // writer; accept them once but track the higher of the two so
    // a subsequent properly-stamped push isn't rejected by a stale
    // legacy push that landed first.
    if (incoming <= 0L) return lastAppliedMs == 0L
    return incoming > lastAppliedMs
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
