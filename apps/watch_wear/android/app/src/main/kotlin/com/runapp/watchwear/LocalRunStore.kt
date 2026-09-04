package com.runapp.watchwear

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.runapp.watchwear.recording.migrateQueuedTracks
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
    /// Share of the run's active time the heart-rate sensor covered, 0..1.
    /// Uploaded as `metadata.hr_coverage`; null omits the key — a run queued
    /// before the field existed says nothing rather than claiming zero.
    val hrCoverage: Double? = null,
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

private val queueJson = Json { ignoreUnknownKeys = true }
private val queueSerializer = ListSerializer(QueuedRun.serializer())

internal fun decodeQueue(raw: String?): List<QueuedRun> = runCatching {
    queueJson.decodeFromString(queueSerializer, raw ?: "[]")
}.getOrDefault(emptyList())

internal fun encodeQueue(runs: List<QueuedRun>): String =
    queueJson.encodeToString(queueSerializer, runs)

/// The three queue mutations, as pure `raw JSON -> raw JSON` reductions.
///
/// They exist so the read half of each read-modify-write can happen against
/// the `Preferences` snapshot **inside** DataStore's `edit` transaction. The
/// previous shape read through `queue.first()` outside it, so a drain that
/// removed an uploaded run and a concurrent `save` could each write a whole
/// list built from a stale snapshot: the removed run reappeared after its
/// track file had already been deleted, and every later drain then failed on
/// the missing payload with the entry stuck in the queue forever.
internal fun queueAfterSave(raw: String?, run: QueuedRun): String =
    encodeQueue(decodeQueue(raw).filter { it.id != run.id } + run)

internal fun queueAfterRemove(raw: String?, id: String): String =
    encodeQueue(decodeQueue(raw).filter { it.id != id })

/// DataStore-backed queue of finished runs awaiting upload.
class LocalRunStore(private val context: Context) {

    val queue: Flow<List<QueuedRun>> = context.dataStore.data.map { prefs ->
        decodeQueue(prefs[KEY_QUEUE])
    }

    suspend fun save(run: QueuedRun) {
        context.dataStore.edit { prefs ->
            prefs[KEY_QUEUE] = queueAfterSave(prefs[KEY_QUEUE], run)
        }
    }

    suspend fun remove(id: String) {
        context.dataStore.edit { prefs ->
            prefs[KEY_QUEUE] = queueAfterRemove(prefs[KEY_QUEUE], id)
        }
    }

    suspend fun contains(id: String): Boolean =
        queue.first().any { it.id == id }

    /// Move any queued run whose track still sits in the pre-migration cache
    /// directory into [durableDir], rewriting the queue entry in the same
    /// transaction so the pair can never disagree about where the payload is.
    /// Returns the queue as it stands afterwards.
    suspend fun migrateTrackFiles(legacyDir: File, durableDir: File): List<QueuedRun> {
        var migrated: List<QueuedRun> = emptyList()
        context.dataStore.edit { prefs ->
            migrated = migrateQueuedTracks(decodeQueue(prefs[KEY_QUEUE]), legacyDir, durableDir)
            prefs[KEY_QUEUE] = encodeQueue(migrated)
        }
        return migrated
    }

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
    /// traces from lingering recoverably on disk.
    suspend fun clear() {
        var dropped: List<QueuedRun> = emptyList()
        context.dataStore.edit { prefs ->
            dropped = decodeQueue(prefs[KEY_QUEUE])
            prefs.remove(KEY_QUEUE)
        }
        for (run in dropped) {
            runCatching { File(run.trackFilePath).delete() }
        }
    }
}
