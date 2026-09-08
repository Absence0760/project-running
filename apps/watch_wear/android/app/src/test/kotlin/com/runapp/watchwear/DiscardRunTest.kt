package com.runapp.watchwear

import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The PostRun `×`, evaluated rather than read.
///
/// The failure it is about could not be reached from any test: `discard` ran
/// its whole body under `launchGuarded`, whose handler only logs, so a
/// DataStore read or write that threw aborted the coroutine before
/// `startNextRun()` and left the runner on PostRun with a confirm they had
/// already given and no visible result — the one moment they most want off the
/// screen (decisions § 1491). `discardRun` is that body as a pure decision, so
/// the throw is now a case rather than a crash.
class DiscardRunTest {

    private class Boom(message: String) : RuntimeException(message)

    @Test
    fun `a dropped run reports what it did`() = runBlocking {
        val dropped = mutableListOf<String>()
        val outcome = discardRun("a") { dropped += it }
        assertEquals(DiscardOutcome.Dropped, outcome)
        assertEquals(listOf("a"), dropped)
    }

    @Test
    fun `no run to drop is not a failure`() = runBlocking {
        // `thisRunId` is null once a run has synced — the drain dropped the
        // entry and the file together. There is nothing left to delete, so
        // this must not read as a fault the arc then reports.
        var called = false
        val outcome = discardRun(null) { called = true }
        assertEquals(DiscardOutcome.NothingQueued, outcome)
        assertTrue("nothing to drop must not touch the store", !called)
    }

    @Test
    fun `a store that throws is an outcome, not the end of the coroutine`() = runBlocking {
        val outcome = discardRun("a") { throw Boom("queue file unreadable") }
        assertTrue("$outcome", outcome is DiscardOutcome.Failed)
        assertEquals(
            "queue file unreadable",
            (outcome as DiscardOutcome.Failed).error.message,
        )
    }

    @Test
    fun `the throwable is carried out, not swallowed into a boolean`() = runBlocking {
        // The raw fault is the only diagnostic a wrist ever produces, and the
        // caller is the only thing here with a `Log`. Reducing this to "it
        // failed" would lose it exactly as `syncError` used to lose it by
        // rendering it (§ 1490).
        val cause = Boom("edit failed")
        val outcome = discardRun("a") { throw cause }
        assertEquals(cause, (outcome as DiscardOutcome.Failed).error)
    }

    // ─────────── the caller's half, which needs an Android runtime ───────────

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    /// `discard()`, from its signature to the next declaration at the same
    /// indent — so nothing below can satisfy an assertion about it.
    private fun discardBody(): String {
        val start = vm.indexOf("    fun discard() {")
        assertTrue("`discard()` is gone or renamed — this guard reads nothing", start >= 0)
        val end = vm.indexOf("\n\n    ", start)
        assertTrue("could not find the end of `discard()`", end > start)
        val body = vm.substring(start, end)
        assertTrue(
            "the extracted body does not call the decision at all — the extraction " +
                "is wrong and both assertions below would pass vacuously",
            body.contains("discardRun("),
        )
        return body
    }

    @Test
    fun `the stage advances outside every branch that could refuse to`() {
        val body = discardBody()
        // The whole filing in one assertion. `startNextRun()` must not sit
        // inside a success arm: the run is still queued when the drop fails,
        // which is the SAFE direction, and stranding a runner who wants to
        // record now behind a corrupt file costs them the next run as well as
        // this one (§ 1107).
        assertEquals(
            "`startNextRun()` must appear exactly once in `discard()`, unguarded: $body",
            1,
            Regex("""startNextRun\(\)""").findAll(body).count(),
        )
        assertTrue("expected a failure branch to guard against", body.contains("DiscardOutcome.Failed"))
        // "Unconditional" is expressible here as a DEPTH. `launchGuarded {`
        // opens at eight spaces, so a statement in its body sits at twelve and
        // anything inside a branch of it sits deeper. Reading the advance's
        // POSITION relative to the failure branch does not say this: an `else`
        // arm puts it after the branch closes and passes such a check, which is
        // exactly the shape being guarded against.
        assertTrue(
            "`startNextRun()` must sit in `discard()`'s coroutine body, not inside " +
                "a branch of it: $body",
            Regex("""\n {12}startNextRun\(\)""").containsMatchIn(body),
        )
    }

    @Test
    fun `a drop that did not happen is logged and said, not merely logged`() {
        val body = discardBody()
        // `launchGuarded`'s handler already logs — that is what it did before,
        // and it is why this was silent rather than crashing. A log the runner
        // cannot read is not a report.
        assertTrue(
            "the failure must reach `Log.e` with the throwable, or the only " +
                "diagnostic a wrist produces is gone: $body",
            Regex("""Log\.e\([^)]*outcome\.error\)""").containsMatchIn(body),
        )
        assertTrue(
            "…and it must raise the flag the PreRun arc reads, or the runner lands " +
                "on a screen whose count silently did not fall: $body",
            body.contains("queueUnreadable = true"),
        )
    }
}
