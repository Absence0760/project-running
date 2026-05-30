package com.runapp.watchwear

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/// Build the `runs.metadata` jsonb for a finished watch run.
///
/// Pure function so the cross-platform watch-payload fixture test
/// (`WatchRunPayloadFixtureTest`) can exercise it without a live
/// Supabase or DataStore. The contract — keys, lap shape — is
/// shared with the Flutter watch-ingest queue and the web row reader
/// via `fixtures/watch_run_payload.json`. See ADR 40 in
/// `docs/architecture/decisions.md`.
///
/// Lap shape is canonical per `docs/backend/metadata.md` § laps:
/// `[{ index, start_offset_s, distance_m, duration_s }]` — per-lap
/// deltas, not cumulative. The on-device `QueuedLap` is cumulative
/// (`atMs`, `distanceM`); this function does the cumulative→delta
/// conversion.
fun buildRunMetadata(
    activityType: String,
    avgBpm: Double?,
    steps: Int?,
    laps: List<QueuedLap>,
    lastModifiedAtIso: String,
): JsonObject = buildJsonObject {
    put("activity_type", activityType)
    if (avgBpm != null) put("avg_bpm", avgBpm)
    if (steps != null && steps > 0) put("steps", steps)
    // Mobile's delta-fetch path (`runs_screen._fetchRemote`) filters
    // on `metadata->>'last_modified_at' > since`. Without this stamp
    // the row is invisible to every refresh after the first full
    // pull. See docs/backend/metadata.md § last_modified_at.
    put("last_modified_at", lastModifiedAtIso)
    if (laps.isNotEmpty()) {
        put("laps", buildJsonArray {
            var prevMs = 0L
            var prevDist = 0.0
            for (lap in laps) {
                addJsonObject {
                    put("index", lap.number)
                    put("start_offset_s", (prevMs / 1000).toInt())
                    put("distance_m", (lap.distanceM - prevDist).coerceAtLeast(0.0))
                    put(
                        "duration_s",
                        ((lap.atMs - prevMs) / 1000).toInt().coerceAtLeast(0),
                    )
                }
                prevMs = lap.atMs
                prevDist = lap.distanceM
            }
        })
    }
}
