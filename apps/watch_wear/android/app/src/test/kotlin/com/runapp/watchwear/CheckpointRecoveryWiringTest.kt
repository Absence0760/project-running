package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard that `RunViewModel` actually routes both recovery
/// entry points through `recoveryActionFor` / `sealTrackFileOrNull`.
///
/// `CheckpointRecoveryTest` proves the graders are right; this proves they are
/// consulted. The ViewModel is DataStore-/Context-bound and not host-JVM
/// testable without Robolectric, so the wiring is pinned with a source grep
/// per the module's convention (see `SignOutLifecycleWiringTest`).
class CheckpointRecoveryWiringTest {

    private val src: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    private fun body(signature: String): String {
        val block = Regex("""${Regex.escape(signature)}[\s\S]*?\n    \}""").find(src)
        assertTrue("expected a $signature body", block != null)
        return block!!.value
    }

    @Test
    fun `the grader reads all three inputs it grades on`() {
        val fn = body("private suspend fun gradeRecovery(")
        assertTrue("must call the pure grader", fn.contains("recoveryActionFor("))
        assertTrue(
            "must ask the queue whether this run was already banked",
            fn.contains("store.contains(cp.runId)"),
        )
        assertTrue(
            "must ask the filesystem whether the track survives",
            Regex("""File\(cp\.trackFilePath\)\.exists\(\)""").containsMatchIn(fn),
        )
        assertTrue(
            "must treat a live recording as an active stage",
            fn.contains("RecordingRepository.metrics.value.stage"),
        )
    }

    @Test
    fun `the prompt is only raised for a checkpoint graded Offer`() {
        val fn = body("private fun checkRecovery()")
        assertTrue("must grade the checkpoint", fn.contains("gradeRecovery(cp)"))
        val offerArm = fn.indexOf("RecoveryAction.Offer")
        val assign = fn.indexOf("pendingRecovery = cp")
        assertTrue("expected an Offer arm", offerArm >= 0)
        assertTrue("expected the prompt assignment", assign >= 0)
        assertTrue(
            "pendingRecovery must be set under the Offer arm, not unconditionally",
            assign > offerArm,
        )
        assertTrue(
            "a discarded checkpoint must be cleared so it can't re-prompt",
            fn.contains("RecoveryAction.Discard -> checkpoints.clear()"),
        )
    }

    @Test
    fun `accepting the prompt re-grades before it queues anything`() {
        // The cold-start drain can upload the run — and delete its track file —
        // while the prompt sits on screen, so the grade taken when the prompt
        // was raised is not the grade that matters when it is accepted.
        val fn = body("fun recoverCheckpoint()")
        val grade = fn.indexOf("gradeRecovery(cp)")
        val save = fn.indexOf("store.save(")
        assertTrue("must re-grade on accept", grade >= 0)
        assertTrue("expected the queue write", save >= 0)
        assertTrue("must re-grade before queueing", grade < save)
        assertTrue(
            "must bail out on any grade other than Offer",
            fn.contains("gradeRecovery(cp) != RecoveryAction.Offer"),
        )
    }

    @Test
    fun `a run whose track cannot be sealed is never queued`() {
        val fn = body("fun recoverCheckpoint()")
        val seal = fn.indexOf("sealTrackFile(cp.trackFilePath)")
        val save = fn.indexOf("store.save(")
        assertTrue("must seal the track", seal >= 0)
        assertTrue("must seal before queueing", seal < save)
        assertTrue(
            "a null seal must abort the recovery",
            Regex("""sealTrackFile\(cp\.trackFilePath\)\s*\?:""").containsMatchIn(fn),
        )
    }

    @Test
    fun `the ViewModel no longer fabricates an empty track for a missing file`() {
        // The regression: an absent track file was stubbed to `[]` and uploaded,
        // blanking the finished run's Storage object. Sealing now lives in
        // `sealTrackFileOrNull`, which refuses.
        assertTrue(
            "sealing must delegate to the pure helper",
            src.contains("sealTrackFileOrNull(File(path))"),
        )
        assertFalse(
            "the ViewModel must not write an empty-array stub",
            Regex("""writeText\("\[]"\)""").containsMatchIn(src),
        )
    }
}
