package com.runapp.watchwear.recording

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the L1 fix: clearing the in-progress
/// checkpoint on stop must be durable against the service scope being
/// cancelled in onDestroy. The clear was a plain `scope.launch { ... }`
/// that raced `scope.cancel()`; if it lost, the next launch showed a
/// phantom "Recover unsaved run?" prompt for a finished run.
///
/// The fix runs the clear (and the stopSelf that triggers onDestroy)
/// inside a single NonCancellable coroutine so the clear can't be
/// dropped and the teardown is ordered after it. That ordering is
/// service-lifecycle wiring — not host-JVM-testable without Robolectric
/// — so it's pinned with a source grep per the module's convention.
class StopTeardownWiringTest {

    private val src: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    @Test
    fun `checkpoint clear runs NonCancellable, not a bare scope launch`() {
        assertTrue(
            "the stop-time checkpoint clear must be NonCancellable so scope.cancel() can't drop it",
            Regex("""scope\.launch\(NonCancellable\)\s*\{[\s\S]*?checkpoints\.clear\(\)""")
                .containsMatchIn(src),
        )
        assertTrue(
            "NonCancellable must be imported",
            src.contains("import kotlinx.coroutines.NonCancellable"),
        )
    }

    @Test
    fun `stopSelf is gated inside the NonCancellable block after the clear`() {
        // The whole teardown (clear → releaseWakeLock → stopForeground →
        // stopSelf) lives in one NonCancellable coroutine; stopSelf comes
        // after checkpoints.clear() so onDestroy can't fire — and cancel
        // the scope — until the clear has committed.
        val block = Regex("""scope\.launch\(NonCancellable\)\s*\{([\s\S]*?)\n        \}""")
            .find(src)?.groupValues?.get(1)
        assertTrue("expected a NonCancellable teardown block in stopRecording", block != null)
        val body = block!!
        val clearIdx = body.indexOf("checkpoints.clear()")
        val stopIdx = body.indexOf("stopSelf()")
        assertTrue("checkpoints.clear() must be present in the teardown block", clearIdx >= 0)
        assertTrue("stopSelf() must be present in the teardown block", stopIdx >= 0)
        assertTrue("stopSelf() must come after checkpoints.clear()", stopIdx > clearIdx)
    }
}
