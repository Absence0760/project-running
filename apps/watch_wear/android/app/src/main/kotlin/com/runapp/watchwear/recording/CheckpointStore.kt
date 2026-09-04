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
    // Active milliseconds the heart-rate sensor was delivering by `savedAtMs`.
    // NULL, not 0, when nothing measured it — a checkpoint written by a build
    // predating the field would otherwise recover as zero coverage and suppress
    // an average that build would have saved (decisions § 1083).
    val hrAvailableMs: Long? = null,
    val activityType: String = "run",
    val laps: List<CheckpointLap> = emptyList(),
    // Cumulative pedometer steps for the in-flight run, and the runner's
    // universal `privacy_default` ("public" / "followers" / "private")
    // snapshotted at write time. Both are what the NORMAL stop path
    // (`RunViewModel.handleFinishedRun`) stamps onto `QueuedRun`; a
    // crash-recovered run must carry them too or it silently uploads with
    // no step count and always non-public. Null `steps` ⇒ omit
    // `metadata.steps`; null `privacyDefault` ⇒ DB default (`false`,
    // non-public) — the fail-closed choice when the pref never loaded.
    val steps: Int? = null,
    val privacyDefault: String? = null,
    // Total paused time (ms) accumulated by `savedAtMs`, folding any
    // in-progress pause at write time. Recovery subtracts it from the
    // wall-clock span to get active duration. Defaults to 0 so a v1
    // checkpoint (no paused field) recovers the raw span exactly as it
    // did before the field existed — see the forward-compat note above.
    val pausedAccumulatedMs: Long = 0L,
)

@Serializable
data class CheckpointLap(val number: Int, val atMs: Long, val distanceM: Double)

/// Active recording duration (seconds) a recovered checkpoint uploads as:
/// the wall-clock span from start to the last saved snapshot, minus the
/// paused time banked by then. A v1 checkpoint with no `pausedAccumulatedMs`
/// subtracts 0 and recovers the raw span — matching pre-field behaviour.
internal fun checkpointActiveDurationS(cp: Checkpoint): Int =
    (((cp.savedAtMs - cp.startedAtMs) - cp.pausedAccumulatedMs) / 1000).toInt()

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
