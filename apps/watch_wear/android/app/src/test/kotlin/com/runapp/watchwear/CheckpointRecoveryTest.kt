package com.runapp.watchwear

import com.runapp.watchwear.recording.RecoveryAction
import com.runapp.watchwear.recording.recoveryActionFor
import com.runapp.watchwear.recording.sealTrackFileOrNull
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/// Pins the two guards standing between a surviving checkpoint and the
/// "Recover unsaved run?" prompt.
///
/// `saveRun` upserts on the run id and re-uploads the track to the same
/// Storage key, so recovering a run that is already captured does not create
/// a second run — it overwrites the first one with an older, shorter snapshot.
class CheckpointRecoveryTest {

    @get:Rule val tmp = TemporaryFolder()

    // ─────────────────────── the grading truth table ───────────────────────

    @Test fun `a crashed run with its track still on disk is offered`() {
        assertEquals(
            RecoveryAction.Offer,
            recoveryActionFor(
                activeRecording = false,
                alreadyQueued = false,
                trackFileExists = true,
            ),
        )
    }

    @Test fun `a run already banked in the upload queue is discarded, not offered`() {
        // The queue entry carries the final distance, duration and laps as of
        // the stop; the checkpoint lags it by up to one checkpoint interval.
        assertEquals(
            RecoveryAction.Discard,
            recoveryActionFor(
                activeRecording = false,
                alreadyQueued = true,
                trackFileExists = true,
            ),
        )
    }

    @Test fun `a run whose track file is gone is discarded, not offered`() {
        // `pushRun` deletes the track file only after a successful upload, and
        // `TrackWriter.open` creates it at run start — so a missing file means
        // this run is already in Supabase.
        assertEquals(
            RecoveryAction.Discard,
            recoveryActionFor(
                activeRecording = false,
                alreadyQueued = false,
                trackFileExists = false,
            ),
        )
    }

    @Test fun `a checkpoint belonging to a live recording is left untouched`() {
        // Not `Discard`: clearing it would disarm the crash-safety net of a run
        // that is still being recorded.
        assertEquals(
            RecoveryAction.Ignore,
            recoveryActionFor(
                activeRecording = true,
                alreadyQueued = false,
                trackFileExists = true,
            ),
        )
    }

    @Test fun `an active recording outranks both discard reasons`() {
        for (queued in listOf(false, true)) {
            for (exists in listOf(false, true)) {
                assertEquals(
                    "queued=$queued exists=$exists",
                    RecoveryAction.Ignore,
                    recoveryActionFor(
                        activeRecording = true,
                        alreadyQueued = queued,
                        trackFileExists = exists,
                    ),
                )
            }
        }
    }

    // ─────────────────────────── sealing the track ───────────────────────────

    @Test fun `an unclosed array is sealed with a trailing bracket`() {
        val f = tmp.newFile("track.json")
        f.writeText("""[{"lat":1.0,"lng":2.0}""")

        val sealed = sealTrackFileOrNull(f)

        assertEquals(f, sealed)
        assertEquals("""[{"lat":1.0,"lng":2.0}]""", f.readText())
    }

    @Test fun `an already-closed array is left byte-for-byte alone`() {
        val f = tmp.newFile("track.json")
        val original = """[{"lat":1.0,"lng":2.0}]"""
        f.writeText(original)

        assertEquals(f, sealTrackFileOrNull(f))
        assertEquals(original, f.readText())
    }

    @Test fun `a zero-length file becomes an empty array`() {
        // The writer opened but never flushed its `[`. There is no track to
        // lose here, and the run still deserves its summary.
        val f = tmp.newFile("track.json")

        assertEquals(f, sealTrackFileOrNull(f))
        assertEquals("[]", f.readText())
    }

    @Test fun `a missing file is refused rather than stubbed into an empty array`() {
        // The regression: stubbing `[]` here published a blank track over the
        // finished run's Storage object.
        val f = File(tmp.root, "gone.json")

        assertNull(sealTrackFileOrNull(f))
        assertEquals(false, f.exists())
    }
}
