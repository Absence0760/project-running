package com.runapp.watchwear.recording

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class Checkpoint(
    val runId: String,
    val startedAtMs: Long,
    val savedAtMs: Long,
    val distanceM: Double,
    /// Path to the JSON-array track file on disk. `TrackWriter` owns the
    /// file; checkpoints just reference it. Full track is never stored
    /// in DataStore — which is critical for a 10-hour run because
    /// DataStore rewrites its full backing file on every commit.
    val trackFilePath: String,
    val trackPointCount: Int,
    // Forward-compat defaults: these fields were added after v1. A v1
    // checkpoint written by an older build must decode cleanly so that
    // a user who upgrades the watch app mid-recording (background
    // install, or install just after a crash but before recovery) can
    // still recover the run. Without defaults `runCatching { ... }
    // .getOrNull()` in `CheckpointStore.current` would silently drop
    // the snapshot and the runner would lose the in-flight run.
    val bpmSum: Long = 0L,
    val bpmCount: Long = 0L,
    val activityType: String = "run",
    val laps: List<CheckpointLap> = emptyList(),
)

@Serializable
data class CheckpointLap(val number: Int, val atMs: Long, val distanceM: Double)

private val Context.checkpointDataStore by preferencesDataStore(name = "watch_wear_checkpoint")
private val KEY_CHECKPOINT: Preferences.Key<String> = stringPreferencesKey("checkpoint_v2")

/// Periodic snapshot metadata of an in-progress run. The track itself
/// lives in a streaming file written by `TrackWriter`; the checkpoint
/// just captures the summary every 15s so a crashed process can be
/// recovered. DataStore writes stay tiny (< 1KB) regardless of run
/// length — a 10-hour run checkpoints with the same payload size as a
/// 10-minute one.
class CheckpointStore(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun current(): Checkpoint? {
        val raw = context.checkpointDataStore.data.first()[KEY_CHECKPOINT] ?: return null
        return runCatching { json.decodeFromString(Checkpoint.serializer(), raw) }.getOrNull()
    }

    suspend fun save(checkpoint: Checkpoint) {
        context.checkpointDataStore.edit { prefs ->
            prefs[KEY_CHECKPOINT] = json.encodeToString(Checkpoint.serializer(), checkpoint)
        }
    }

    suspend fun clear() {
        context.checkpointDataStore.edit { prefs -> prefs.remove(KEY_CHECKPOINT) }
    }
}
