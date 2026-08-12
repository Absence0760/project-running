package com.runapp.watchwear.recording

import java.io.File
import java.io.RandomAccessFile

/// What to do with a checkpoint that is still on disk when the app starts.
enum class RecoveryAction {
    /// The checkpoint is the only record of this run — prompt to recover it.
    Offer,

    /// A recording is in flight and this checkpoint belongs to it. Leave it
    /// completely alone: it is the live crash-safety net, so neither prompt
    /// (the run is not lost) nor clear (that would disarm the net).
    Ignore,

    /// The run is already captured somewhere strictly better than this
    /// snapshot. Drop the checkpoint silently.
    Discard,
}

/// Grade a surviving checkpoint before offering it to the runner.
///
/// A checkpoint lags the run by up to one checkpoint interval and its track
/// file is shared with the upload path, so "a checkpoint exists" alone does
/// not mean "this run needs rescuing" — and acting on one that does not is
/// destructive, because `saveRun` upserts on the run id (`Prefer:
/// resolution=merge-duplicates`) and re-uploads the track to the same
/// Storage key:
///
///   - `alreadyQueued`: the normal stop path banked this run into
///     `LocalRunStore` with the final distance, duration and laps. Recovering
///     would overwrite that queue entry with the older, shorter snapshot and
///     upload it instead.
///   - `trackFileExists`: `pushRun` deletes the track file as its last act
///     after a successful upload, and `TrackWriter.open` creates the file at
///     run start — so on this device a missing file means the run already
///     reached Supabase, never that it had no points. Recovering would upsert
///     the checkpoint's stale summary over the finished row and replace its
///     Storage track with an empty one.
fun recoveryActionFor(
    activeRecording: Boolean,
    alreadyQueued: Boolean,
    trackFileExists: Boolean,
): RecoveryAction = when {
    activeRecording -> RecoveryAction.Ignore
    alreadyQueued || !trackFileExists -> RecoveryAction.Discard
    else -> RecoveryAction.Offer
}

/// Re-seal a recovered run's track file so it parses as JSON, returning null
/// when there is nothing to seal.
///
/// A process killed mid-run leaves the array unclosed (`TrackWriter.close`
/// never ran), so a trailing `]` is appended. A file that is *absent* is not
/// sealed into an empty array: an empty array is a factual claim that the run
/// had no points, and uploading it would overwrite whatever track is already
/// in Storage under this run id. Absent means the payload is gone — the
/// caller must decline to recover rather than publish a blank track.
fun sealTrackFileOrNull(file: File): File? {
    if (!file.exists()) return null
    val len = file.length()
    if (len == 0L) {
        file.writeText("[]")
        return file
    }
    val last = RandomAccessFile(file, "r").use { raf ->
        raf.seek(len - 1)
        raf.read()
    }
    if (last != ']'.code) file.appendText("]")
    return file
}
