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
        // Word-boundary: `discard_confirm` (the armed label) and `discard_stake`
        // (the armed warning) both sit inside this block and both start with
        // the same eight characters, so a bare indexOf lands on the Save chip.
        val discard = Regex("""R\.string\.discard\b""").find(block)?.range?.first ?: -1
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
    fun `Discard is behind a two-press confirm that announces the arm and the stake`() {
        // The checkpoint is the run's only durable record while the queue does
        // not hold it (§ 1107), and since § 1154 Discard is the only ENABLED
        // control on the screen whenever the queue is unreadable — so a runner
        // who wants their run and finds "Save it" greyed out has exactly one
        // thing left to press. One tap must not destroy it (decisions § 1206).
        val block = prompt()
        val discardChip = block.substring(
            block.lastIndexOf("Chip(", block.indexOf("R.string.discard_confirm")),
        )
        assertTrue(
            "the Discard chip must grade its press through `confirmPress` rather than " +
                "calling the destructive callback directly: $discardChip",
            Regex("""confirmPress\(discardArmedAtMs""").containsMatchIn(discardChip),
        )
        assertTrue(
            "only the CONFIRMED branch may discard — a first press must arm and do " +
                "nothing else: $discardChip",
            Regex("""ConfirmPress\.Confirmed\s*->\s*\{[^}]*onDiscardRecovery\(\)""")
                .containsMatchIn(discardChip),
        )
        assertTrue(
            "`onDiscardRecovery` must be reachable from nowhere else in the takeover — " +
                "an unguarded second call site is the defect wearing a guard",
            Regex("""onDiscardRecovery\(\)""").findAll(block).count() == 1,
        )
        assertTrue(
            "the armed state must change the label — an arm nobody can see reads as a " +
                "dead button, and the next press then lands on a live discard",
            block.contains("R.string.discard_confirm"),
        )
        assertTrue(
            "the arm must name the stake: this checkpoint exists nowhere else",
            block.contains("R.string.discard_stake"),
        )
        assertTrue(
            "the arm must lapse on its own, or a watch put down while armed comes " +
                "back with a destructive control one tap from firing",
            Regex("""delay\(CONFIRM_WINDOW_MS\)""").containsMatchIn(block),
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
        RotaryWiring.assertPaired(block, "the recovery takeover")
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
