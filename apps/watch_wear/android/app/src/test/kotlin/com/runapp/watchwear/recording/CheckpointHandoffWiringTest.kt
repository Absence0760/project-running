package com.runapp.watchwear.recording

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard on who clears the in-progress checkpoint, and when.
///
/// The checkpoint is the run's only durable record between the service
/// publishing `Finished` and `LocalRunStore` accepting the queue entry. The
/// service used to clear it inside its own teardown, concurrently with that
/// write and immediately before dropping out of foreground-service state —
/// so a process kill in the window erased both the queue entry and the
/// snapshot that would have rebuilt it, and the run was simply gone.
///
/// The clear now belongs to the writer: `RunViewModel.handleFinishedRun`
/// clears only after `store.save` returns. The worst case flips from losing
/// the run to a checkpoint outliving a banked one, which `recoveryActionFor`
/// grades `Discard` — silently, no phantom "Recover unsaved run?" prompt.
///
/// Service lifecycle and the ViewModel are both Android-bound and not
/// host-JVM testable without Robolectric, so the ordering is pinned with a
/// source grep per the module's convention (see `CheckpointRecoveryWiringTest`).
class CheckpointHandoffWiringTest {

    private val serviceSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    private val viewModelSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    /// The named function's body.
    ///
    /// `suspend` is erased from the source before matching rather than
    /// spelled into every caller's signature: whether a function suspends is
    /// a property of how it is CALLED, and nothing this file asserts depends
    /// on it. Keying on the modifier failed the build the day
    /// `handleFinishedRun` moved its track read off the main thread — a
    /// change that touched none of the ordering below.
    private fun body(src: String, signature: String): String {
        val normalised = src.replace(" suspend fun ", " fun ")
        val block = Regex("""${Regex.escape(signature)}[\s\S]*?\n    \}""").find(normalised)
        assertTrue("expected a $signature body", block != null)
        return block!!.value
    }

    @Test
    fun `the recording service never clears the checkpoint`() {
        assertTrue(
            "the service must still write checkpoints",
            serviceSrc.contains("checkpoints.save("),
        )
        assertFalse(
            "clearing the checkpoint from the service races the queue write it protects",
            serviceSrc.contains("checkpoints.clear()"),
        )
    }

    @Test
    fun `stop tears the service down without waiting on a checkpoint write`() {
        val fn = body(serviceSrc, "private fun stopRecording()")
        assertTrue(
            "stop must publish Finished for the ViewModel to bank",
            fn.contains("RecordingRepository.Stage.Finished"),
        )
        val finished = fn.indexOf("RecordingRepository.Stage.Finished")
        val stop = fn.indexOf("stopSelf()")
        assertTrue("stop must still stop the service", stop >= 0)
        assertTrue("Finished must be published before the service stops", finished < stop)
        assertTrue(
            "the wake lock must be released on stop",
            fn.contains("releaseWakeLock()"),
        )
    }

    @Test
    fun `the finished run is banked before its checkpoint is cleared`() {
        val fn = body(viewModelSrc, "private fun handleFinishedRun(")
        val save = fn.indexOf("store.save(")
        val clear = fn.indexOf("checkpoints.clear()")
        assertTrue("the finished run must be queued", save >= 0)
        assertTrue("the checkpoint must be cleared once the run is queued", clear >= 0)
        assertTrue(
            "clearing before the queue write leaves a kill window with no record of the run",
            clear > save,
        )
    }

    @Test
    fun `recovering a checkpoint queues before it clears too`() {
        val fn = body(viewModelSrc, "fun recoverCheckpoint()")
        val save = fn.lastIndexOf("store.save(")
        val clear = fn.lastIndexOf("checkpoints.clear()")
        assertTrue("the recovered run must be queued", save >= 0)
        assertTrue("the checkpoint must be cleared once the run is queued", clear >= 0)
        assertTrue("the same ordering applies on the recovery path", clear > save)
    }
}
