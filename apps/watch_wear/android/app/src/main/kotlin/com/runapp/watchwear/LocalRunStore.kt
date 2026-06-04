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
import java.io.File

@Serializable
data class QueuedLap(val number: Int, val atMs: Long, val distanceM: Double)

@Serializable
data class QueuedRun(
    val id: String,
    val startedAtIso: String,
    val durationS: Int,
    val distanceM: Double,
    /// Absolute path on local disk to the streamed track file produced by
    /// `TrackWriter`. Holding only the path (not the JSON body) keeps the
    /// DataStore payload tiny regardless of run length — critical for
    /// ultra-length runs where the track file can be multiple megabytes.
    val trackFilePath: String,
    val avgBpm: Double? = null,
    val activityType: String = "run",
    val laps: List<QueuedLap> = emptyList(),
    /// Cumulative step count for the run — captured from the
    /// `TYPE_STEP_COUNTER` sensor during recording. Written to
    /// `run.metadata.steps` on upload. Null when the device has no
    /// pedometer or the sensor never emitted.
    val steps: Int? = null,
    /// Snapshot of the universal `privacy_default` at stop time,
    /// mapped to a boolean: `public → true`; `followers` /
    /// `private` / not-yet-fetched → false. Null omits the column
    /// on upload so the DB default (`false`) wins — preserves the
    /// pre-change behaviour for runs queued before this field
    /// existed (kotlinx-serialization fills the default on decode).
    val isPublic: Boolean? = null,
)

private val Context.dataStore by preferencesDataStore(name = "watch_wear")
private val KEY_QUEUE: Preferences.Key<String> = stringPreferencesKey("queued_runs_v2")

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

    /// Wipe the entire upload queue, including the on-disk track files
    /// the queued runs reference.
    ///
    /// Called from sign-out teardown ([RunViewModel.tearDownSession]).
    /// The queue holds finished-but-unsynced runs, and `drainQueue`
    /// uploads them under whatever session is current at drain time — so
    /// leaving another user's runs queued across a sign-out would upload
    /// user A's GPS traces into user B's account. Clearing on sign-out is
    /// fail-closed against that cross-user leak. The trade-off is that a
    /// run recorded offline and not yet synced is dropped on sign-out; in
    /// practice the queue is drained on every run-stop and every
    /// offline→online edge, so it's normally empty before a deliberate
    /// sign-out. Deleting the track files too keeps the previous user's
    /// traces from lingering recoverably in the cache dir.
    suspend fun clear() {
        val current = queue.first()
        for (run in current) {
            runCatching { File(run.trackFilePath).delete() }
        }
        context.dataStore.edit { prefs -> prefs.remove(KEY_QUEUE) }
    }

    private suspend fun write(runs: List<QueuedRun>) {
        context.dataStore.edit { prefs ->
            prefs[KEY_QUEUE] = json.encodeToString(listSerializer, runs)
        }
    }
}
