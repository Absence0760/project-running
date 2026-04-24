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

    suspend fun current(): List<SavedRoute> = routes.first()

    suspend fun save(list: List<SavedRoute>) {
        val encoded = json.encodeToString(serializer, list)
        context.routeDataStore.edit { prefs ->
            prefs[KEY_ROUTES_JSON] = encoded
        }
    }

    suspend fun clear() {
        context.routeDataStore.edit { prefs ->
            prefs.remove(KEY_ROUTES_JSON)
        }
    }

    companion object {
        private val KEY_ROUTES_JSON: Preferences.Key<String> = stringPreferencesKey("routes_v1")
    }
}
