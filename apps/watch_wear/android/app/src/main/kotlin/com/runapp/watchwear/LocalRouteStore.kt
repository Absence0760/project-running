package com.runapp.watchwear

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.builtins.ListSerializer

private val Context.routeDataStore by preferencesDataStore(name = "watch_wear_routes")

/// On-disk cache of the user's saved routes, refreshed from Supabase
/// whenever the pre-run screen opens. Survives cold launch so the picker
/// shows something useful even if the network is down.
///
/// Payload is a single JSON-encoded list — routes are small (a few
/// hundred waypoints at most) and there's no reason to key them
/// individually. Clear on sign-out so the next user doesn't see the
/// previous user's list.
///
/// Also tracks a small LRU of recently-tapped route IDs so the picker
/// can surface "what I usually run" before "what I last saved on the
/// web". Stored as a comma-separated string (DataStore preference
/// values can't be List<String>); ~10 entries × 36-char UUIDs ≈ 400
/// bytes, vastly under any reasonable prefs cap.
class LocalRouteStore(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(SavedRoute.serializer())

    val routes: Flow<List<SavedRoute>> = context.routeDataStore.data.map { prefs ->
        val raw = prefs[KEY_ROUTES_JSON] ?: return@map emptyList()
        try {
            json.decodeFromString(serializer, raw)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    val recentIds: Flow<List<String>> = context.routeDataStore.data.map { prefs ->
        val raw = prefs[KEY_RECENT_IDS] ?: return@map emptyList()
        raw.split(",").filter { it.isNotBlank() }
    }

    suspend fun current(): List<SavedRoute> = routes.first()

    /// Persist the route cache. Two cost guards on the underlying
    /// Preferences DataStore, which rewrites its ENTIRE backing file on
    /// every committed change:
    ///
    /// 1. **Bounded** to [MAX_ROUTES] (= the server-side `limit=30` the
    ///    watch's `fetchRoutes` query uses). Both inbound sources — the
    ///    Supabase fetch and the phone's Data Layer push — are nominally
    ///    capped at 30, but a phone running an older/looser bridge could
    ///    push more; capping here keeps the backing file bounded and the
    ///    1.4-inch picker un-scrollable past what fits.
    /// 2. **Dedup'd**: skip the rewrite when the encoded list is
    ///    byte-identical to what's already on disk. The pre-run screen
    ///    re-saves on every open and the phone re-pushes on every Data
    ///    Layer event, most of which don't change the set — without this
    ///    each is a full-file rewrite for no change.
    suspend fun save(list: List<SavedRoute>) {
        val encoded = json.encodeToString(serializer, boundRoutes(list))
        context.routeDataStore.edit { prefs ->
            if (prefs[KEY_ROUTES_JSON] != encoded) {
                prefs[KEY_ROUTES_JSON] = encoded
            }
        }
    }

    /// Push `id` to the front of the recents LRU, deduped, capped at
    /// `MAX_RECENTS`. Called on each route pick; the picker reads
    /// `recentIds` to sort frequently-used routes to the top.
    suspend fun pushRecent(id: String) {
        if (id.isBlank()) return
        context.routeDataStore.edit { prefs ->
            val existing = prefs[KEY_RECENT_IDS]?.split(",")?.filter { it.isNotBlank() }
                ?: emptyList()
            val updated = (listOf(id) + existing.filter { it != id }).take(MAX_RECENTS)
            prefs[KEY_RECENT_IDS] = updated.joinToString(",")
        }
    }

    suspend fun clear() {
        context.routeDataStore.edit { prefs ->
            prefs.remove(KEY_ROUTES_JSON)
            prefs.remove(KEY_RECENT_IDS)
        }
    }

    companion object {
        private val KEY_ROUTES_JSON: Preferences.Key<String> = stringPreferencesKey("routes_v1")
        private val KEY_RECENT_IDS: Preferences.Key<String> = stringPreferencesKey("recent_route_ids_v1")
        private const val MAX_RECENTS = 10

        /// Local cap on the persisted route cache. Mirrors the
        /// `limit=30` on the watch's `fetchRoutes` Supabase query — see
        /// `RunWatchApp` / `SupabaseClient.fetchRoutes`. Keeps the
        /// DataStore backing file (rewritten whole on every save)
        /// bounded regardless of how many routes a source hands us.
        const val MAX_ROUTES = 30
    }
}

/// Bound a route list to [LocalRouteStore.MAX_ROUTES], preserving order
/// (the inbound lists are pre-sorted — Supabase by `updated_at desc`, the
/// phone push by the user's starred set). File-level `internal` so the
/// cap is unit-testable without a DataStore-backing `Context`.
internal fun boundRoutes(
    list: List<SavedRoute>,
    max: Int = LocalRouteStore.MAX_ROUTES,
): List<SavedRoute> = if (list.size <= max) list else list.take(max)
