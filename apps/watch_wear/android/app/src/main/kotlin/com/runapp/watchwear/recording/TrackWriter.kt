package com.runapp.watchwear.recording

import android.content.Context
import com.runapp.watchwear.GpsPoint
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.time.Instant

/// Append-only writer that streams GPS points to a JSON array on disk
/// as they arrive, so a 10-hour run doesn't hold a 36,000-element list
/// in memory.
///
/// The output file is a valid JSON array — opens with `[`, comma-
/// separates points, closes with `]`. Readers (both the Dart api_client
/// and anything else decoding the Storage track file) see the exact
/// same shape as the old in-memory `encodeTrack` produced, so nothing
/// downstream changes.
///
/// Flushes every 32 points so a crash loses at most ~30s of GPS at 1Hz
/// while avoiding a disk write on every single sample.
class TrackWriter(private val file: File) {
    private var writer: PrintWriter? = null
    private var count = 0
    private var open = false

    val pointCount: Int get() = count
    val path: String get() = file.absolutePath

    fun open() {
        file.parentFile?.mkdirs()
        file.delete()
        val pw = PrintWriter(BufferedWriter(FileWriter(file, false), BUFFER_BYTES))
        pw.print("[")
        pw.flush()
        writer = pw
        count = 0
        open = true
    }

    fun append(point: GpsPoint) {
        val w = writer ?: return
        if (count > 0) w.print(",")
        val ts = Instant.ofEpochMilli(point.epochMs)
        val ele = point.ele?.toString() ?: "null"
        w.print(
            "{\"lat\":${point.lat}," +
                "\"lng\":${point.lng}," +
                "\"ele\":$ele," +
                "\"ts\":\"$ts\"}"
        )
        count++
        if (count % FLUSH_EVERY == 0) w.flush()
    }

    /// Close and return the finished file. Safe to call more than once;
    /// the file contents remain a valid JSON array once sealed.
    fun close(): File {
        val w = writer
        if (open && w != null) {
            w.print("]")
            w.flush()
            w.close()
        }
        writer = null
        open = false
        return file
    }

    companion object {
        private const val BUFFER_BYTES = 8192
        private const val FLUSH_EVERY = 32

        /// Return a file handle in the app's cache dir for a given run id.
        /// `cache` rather than `files` because the file is transient — it
        /// lives until the run is uploaded + acknowledged, then we delete.
        fun fileFor(context: Context, runId: String): File =
            File(context.cacheDir, "tracks/$runId.json")
    }
}
