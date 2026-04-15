package com.runapp.watchwear.recording

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.runapp.watchwear.GpsPoint
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class CheckpointPoint(
    val lat: Double,
    val lng: Double,
    val ele: Double?,
    val epochMs: Long,
) {
    fun toGps() = GpsPoint(lat, lng, ele, epochMs)
    companion object {
        fun from(p: GpsPoint) = CheckpointPoint(p.lat, p.lng, p.ele, p.epochMs)
    }
}

@Serializable
data class Checkpoint(
    val runId: String,
    val startedAtMs: Long,
    val savedAtMs: Long,
    val distanceM: Double,
    val track: List<CheckpointPoint>,
    val bpmSamples: List<Int>,
)

private val Context.checkpointDataStore by preferencesDataStore(name = "watch_wear_checkpoint")
private val KEY_CHECKPOINT: Preferences.Key<String> = stringPreferencesKey("checkpoint_v1")

/// Periodic snapshot of an in-progress run. Written by the recording
/// service every ~15s and on every GPS sample after the first 30s. If
/// the process is killed mid-run, the next launch finds the checkpoint
/// and the user can recover the partial recording instead of losing it.
class CheckpointStore(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val pointSerializer = ListSerializer(CheckpointPoint.serializer())

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
