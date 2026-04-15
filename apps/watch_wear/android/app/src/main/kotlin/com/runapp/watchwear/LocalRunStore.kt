package com.runapp.watchwear

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

@Serializable
data class QueuedLap(val number: Int, val atMs: Long, val distanceM: Double)

@Serializable
data class QueuedRun(
    val id: String,
    val startedAtIso: String,
    val durationS: Int,
    val distanceM: Double,
    val trackJson: String,
    val avgBpm: Double? = null,
    val activityType: String = "run",
    val laps: List<QueuedLap> = emptyList(),
)

private val Context.dataStore by preferencesDataStore(name = "watch_wear")
private val KEY_QUEUE: Preferences.Key<String> = stringPreferencesKey("queued_runs_v1")

/// DataStore-backed queue of finished runs awaiting upload.
class LocalRunStore(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val listSerializer = ListSerializer(QueuedRun.serializer())

    val queue: Flow<List<QueuedRun>> = context.dataStore.data.map { prefs ->
        val raw = prefs[KEY_QUEUE] ?: "[]"
        runCatching {
            json.decodeFromString(listSerializer, raw)
        }.getOrDefault(emptyList())
    }

    suspend fun save(run: QueuedRun) {
        val current = queue.first().filter { it.id != run.id } + run
        write(current)
    }

    suspend fun remove(id: String) {
        val current = queue.first().filter { it.id != id }
        write(current)
    }

    suspend fun contains(id: String): Boolean =
        queue.first().any { it.id == id }

    private suspend fun write(runs: List<QueuedRun>) {
        context.dataStore.edit { prefs ->
            prefs[KEY_QUEUE] = json.encodeToString(listSerializer, runs)
        }
    }
}
