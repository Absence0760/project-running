package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard over the crash-recovery prompt's DISPLAY half, the
/// residual § 1107 filed rather than took.
///
/// § 1107 made `gradeRecovery` fail closed on an unreadable queue: the grade
/// is `Ignore`, nothing is queued and nothing is cleared. Correct for the
/// data, and completely silent for the runner — the prompt is a full-screen
/// takeover with no failure line, and `syncError` renders on `PostRunScreen`,
/// a screen a runner sitting under this takeover cannot reach. So "Save it"
/// did nothing, twice over: the tap was inert AND the prompt was never raised
/// at all on a cold start into an unreadable queue.
///
/// Compose wiring is not host-JVM testable without Robolectric, which this
/// module avoids, so the two halves are pinned with a source grep per the
/// module's convention (`CheckpointRecoveryWiringTest`, `RotaryScrollWiringTest`).
class RecoveryPromptDisclosureTest {

    private val ui: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    /// The takeover, from the branch that raises it to the `return` that ends
    /// it — so an assertion cannot be satisfied by the unreadable chip further
    /// down the same composable, which is a different surface on a different
    /// screen state.
    private fun prompt(): String {
        val start = ui.indexOf("if (pendingRecoveryDistance != null) {")
        assertTrue("the recovery takeover branch is gone from PreRunScreen", start >= 0)
        val end = ui.indexOf("\n        return\n    }", start)
        assertTrue("could not find the end of the recovery takeover branch", end > start)
        return ui.substring(start, end)
    }

    @Test
    fun `the prompt states the unreadable queue rather than failing silently`() {
        val block = prompt()
        assertTrue(
            "the takeover must render the unreadable-queue string. Without it the " +
                "runner taps \"Save it\", the re-grade answers Ignore, and nothing " +
                "visibly happens at all — the prompt is a takeover and `syncError` " +
                "renders on PostRunScreen.",
            block.contains("R.string.sync_queue_unreadable"),
        )
        assertTrue(
            "the disclosure must be conditional on the fault, not permanent",
            Regex("""if \(queueUnreadable\)""").containsMatchIn(block),
        )
    }

    @Test
    fun `Save it is disabled while the queue is unreadable and Discard is not`() {
        val block = prompt()
        val save = block.indexOf("R.string.save_it")
        val discard = block.indexOf("R.string.discard")
        assertTrue("expected a Save it chip", save >= 0)
        assertTrue("expected a Discard chip", discard >= 0)
        assertTrue("expected Save it before Discard", save < discard)

        val saveChip = block.substring(block.lastIndexOf("Chip(", save), save)
        assertTrue(
            "\"Save it\" must be disabled while the queue is unreadable — the tap " +
                "cannot succeed, because `store.save` reads the same file the grade " +
                "could not: $saveChip",
            Regex("""enabled\s*=\s*!queueUnreadable""").containsMatchIn(saveChip),
        )

        // Discard is the ONLY way off a screen with no Start button. Disabling
        // it too would strand a runner who wants to record now behind a corrupt
        // file, costing them the next run as well as this one.
        val discardChip = block.substring(block.lastIndexOf("Chip(", discard), discard)
        assertTrue(
            "\"Discard\" must stay live — it is the only exit from a takeover with " +
                "no Start button: $discardChip",
            !discardChip.contains("enabled"),
        )
    }

    @Test
    fun `the prompt scrolls, and the scroll is rotary-wired like every other list here`() {
        val block = prompt()
        assertTrue(
            "the takeover must scroll: title + distance + two 52 dp chips already " +
                "measure past what a 192 dp round watch leaves inside 20 dp padding, " +
                "so Discard fell off the bottom edge with no way to reach it",
            block.contains("verticalScroll("),
        )
        assertTrue(
            "a scrolling surface on this watch is reached by the bezel/crown too",
            block.contains(".rotaryScrollable("),
        )
        // The module-wide pairing invariant, restated locally so this branch
        // cannot drift out of it: a rotary modifier with no focused requester
        // silently receives nothing.
        assertEquals(
            "each rotaryScrollable in the takeover needs its FocusRequester focused",
            Regex("""\.rotaryScrollable\(""").findAll(block).count(),
            Regex("""rotaryFocus\.requestFocus\(\)""").findAll(block).count(),
        )
    }

    @Test
    fun `a queue read that recovers re-raises the prompt it withheld`() {
        assertTrue(
            "`checkRecovery` runs once from `init`, so a read that recovers inside " +
                "the same process never re-raises the prompt it withheld. Route the " +
                "recovery through `onQueueBecameReadable`.",
            vm.contains("private fun onQueueBecameReadable(wasUnreadable: Boolean)"),
        )

        val fn = Regex(
            """private fun onQueueBecameReadable\(wasUnreadable: Boolean\)[\s\S]*?\n    \}"""
        ).find(vm)
        assertTrue("expected an onQueueBecameReadable body", fn != null)
        val body = fn!!.value
        assertTrue(
            "must only fire on the TRANSITION — every queue emission would " +
                "otherwise re-read the checkpoint store: $body",
            body.contains("if (!wasUnreadable) return"),
        )
        assertTrue(
            "must not re-raise over a prompt already on screen, or an arriving " +
                "emission swaps the checkpoint under a decision in progress: $body",
            body.contains("if (_state.value.pendingRecovery != null) return"),
        )
        assertTrue("must re-take the grade", body.contains("checkRecovery()"))
    }

    @Test
    fun `both readers of the queue file re-raise, not just one`() {
        // The flag is cleared in two places and the file has two readers — the
        // retrying stream and the drain the runner's own retry goes through.
        // Hooking only one leaves the other clearing the flag while the prompt
        // stays withheld, which is the same silence in a new place.
        val clears = Regex("""queueUnreadable = false""").findAll(vm).count()
        val reraises = Regex("""onQueueBecameReadable\(wasUnreadable\)""").findAll(vm).count()
        assertEquals(
            "every site that clears `queueUnreadable` must re-raise: $clears clear(s), " +
                "$reraises re-raise(s)",
            clears,
            reraises,
        )
    }
}
