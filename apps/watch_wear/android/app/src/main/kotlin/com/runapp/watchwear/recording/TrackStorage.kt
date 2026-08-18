package com.runapp.watchwear.recording

import android.content.Context
import com.runapp.watchwear.QueuedRun
import java.io.File

/// Where a recorded run's GPS track lives on the watch, and the
/// cold-start reconciliation between that directory and the upload queue.
///
/// The track file used to be written to `context.cacheDir`, which the
/// platform reclaims under storage pressure without asking. Until the run
/// has been uploaded that file is the *only* copy of the trace, so a purge
/// silently destroyed recorded runs while the queue kept promising to sync
/// them. A not-yet-synced payload is not a cache: it lives in `filesDir`,
/// which only this app deletes. Android Auto-Backup never sees it —
/// `android:allowBackup="false"` (see `BackupExclusionManifestTest`).
object TrackStorage {
    /// Age a stranded file must reach before the sweep may delete it, so a
    /// writer that has just created a file for a run not yet in the queue is
    /// never raced. Mirrors the one-hour gate the phone's `.tmp` orphan sweep
    /// uses (decisions.md § 313).
    const val ORPHAN_MIN_AGE_MS: Long = 60 * 60 * 1000L

    fun durableDir(context: Context): File = File(context.filesDir, "tracks")

    /// The pre-migration location. Read at cold start so an upgrade over an
    /// install with queued runs moves their tracks instead of orphaning them.
    fun legacyCacheDir(context: Context): File = File(context.cacheDir, "tracks")

    fun fileFor(context: Context, runId: String): File =
        File(durableDir(context), "$runId.json")
}

/// Move every queued run's track out of `legacyDir` and into `durableDir`,
/// returning the queue with its paths rewritten. Only queue entries are
/// touched: an in-flight recording is not queued, so its open file is never
/// moved out from under `TrackWriter`.
///
/// An entry whose file is already durable, or whose file is gone entirely,
/// is returned with the path it can actually be served from — a rewrite to a
/// destination that does not exist would turn a recoverable "the payload was
/// purged" into a path that never had one.
internal fun migrateQueuedTracks(
    runs: List<QueuedRun>,
    legacyDir: File,
    durableDir: File,
): List<QueuedRun> = runs.map { run ->
    val source = File(run.trackFilePath)
    if (source.parentFile?.absolutePath != legacyDir.absolutePath) return@map run
    val destination = File(durableDir, source.name)
    if (destination.exists()) return@map run.copy(trackFilePath = destination.absolutePath)
    if (!source.exists()) return@map run
    durableDir.mkdirs()
    val moved = source.renameTo(destination) || runCatching {
        source.copyTo(destination, overwrite = true)
        source.delete()
        true
    }.getOrDefault(false)
    if (moved) run.copy(trackFilePath = destination.absolutePath) else run
}

/// Delete track files in `durableDir` that nothing can still want, and
/// return what was deleted.
///
/// `keepPaths` must carry every path that is still owned by something: the
/// upload queue, the crash checkpoint awaiting a recovery prompt, and the
/// live recording. `filesDir` is not self-cleaning the way the cache dir
/// was, so without this a track stranded by a crash between "queue entry
/// removed" and "file deleted" would live forever — but a sweep that
/// guesses wrong destroys exactly the run this whole change exists to
/// protect, hence the explicit keep-set plus the age gate.
internal fun sweepOrphanTracks(
    durableDir: File,
    keepPaths: Set<String>,
    nowMs: Long,
    minAgeMs: Long = TrackStorage.ORPHAN_MIN_AGE_MS,
): List<File> {
    val keep = keepPaths.map { File(it).absolutePath }.toSet()
    val entries = durableDir.listFiles() ?: return emptyList()
    val deleted = mutableListOf<File>()
    for (file in entries) {
        if (!file.isFile) continue
        if (file.absolutePath in keep) continue
        if (nowMs - file.lastModified() < minAgeMs) continue
        if (file.delete()) deleted += file
    }
    return deleted
}
