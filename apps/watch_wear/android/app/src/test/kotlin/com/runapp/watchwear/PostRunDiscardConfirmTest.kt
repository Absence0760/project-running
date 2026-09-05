package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard over the PostRun screen's Discard, the twin of the
/// crash-recovery Discard § 1206 guarded and of the two watchOS ones § 1208 did.
///
/// `RunViewModel.discard` is `store.remove(id)` and the button renders only on
/// the `!synced` branch, so the run it deletes has not reached Supabase and the
/// local queue is the only place it exists. One tap must not end it.
///
/// Compose wiring is not host-JVM testable without Robolectric, which this
/// module avoids, so this is a source grep per the module's convention
/// (`RecoveryPromptDisclosureTest`, `ScreenWiringTest`). What it pins is the
/// SHAPE of the guard, not its wording: the destructive callback is reachable
/// from exactly one place and that place is the confirmed branch.
class PostRunDiscardConfirmTest {

    private val ui: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    /// The PostRunScreen body, from its signature to the next top-level
    /// declaration — so nothing below can satisfy an assertion about it.
    private fun postRun(): String {
        val start = ui.indexOf("private fun PostRunScreen(")
        assertTrue("PostRunScreen is gone or renamed — this guard reads nothing", start >= 0)
        val end = ui.indexOf("\nprivate fun ", start + 1)
        assertTrue("could not find the end of PostRunScreen", end > start)
        val body = ui.substring(start, end)
        assertTrue(
            "the extracted body does not contain the Discard control at all — the " +
                "extraction is wrong, and every assertion below would pass vacuously",
            body.contains("R.string.discard_short"),
        )
        return body
    }

    @Test
    fun `the destructive callback is reachable only from the confirmed branch`() {
        val body = postRun()
        // The defect this replaces was `onClick = onDiscard` on a 52 dp button.
        // Anchoring on the CALL rather than on the button keeps the guard true
        // if the control is restyled, relabelled or moved.
        val calls = Regex("""onDiscard\(\)""").findAll(body).count()
        assertEquals(
            "`onDiscard()` must be called from exactly one place in PostRunScreen — " +
                "a second call site is the defect wearing a guard",
            1,
            calls,
        )
        assertTrue(
            "the one call must sit in the CONFIRMED branch: a first press has to arm " +
                "and do nothing else",
            Regex("""ConfirmPress\.Confirmed\s*->\s*\{[^}]*onDiscard\(\)""")
                .containsMatchIn(body),
        )
        assertTrue(
            "the press must be graded through `confirmPress`, not decided inline",
            Regex("""confirmPress\(discardArmedAtMs""").containsMatchIn(body),
        )
        assertTrue(
            "no control may bind the destructive callback directly — that is the " +
                "single-tap discard this guard exists to refuse",
            !Regex("""onClick\s*=\s*onDiscard\b""").containsMatchIn(body),
        )
    }

    @Test
    fun `the arm is announced by a label and a sentence, not by a colour`() {
        val body = postRun()
        assertTrue(
            "the armed state must render `discard_confirm` — the unarmed control is a " +
                "52 dp `×` with no room for a word, so the arm has to relabel something " +
                "a reader can see. This module already refuses colour as a signal.",
            body.contains("R.string.discard_confirm"),
        )
        assertTrue(
            "the arm must name the stake: this run is not saved anywhere else",
            body.contains("R.string.discard_stake"),
        )
        assertTrue(
            "the confirm must announce itself to TalkBack too — the `×` and the " +
                "confirm would otherwise read identically",
            body.contains("R.string.cd_discard_confirm"),
        )
        assertTrue(
            "both must render only while armed, or the screen states a stake for a " +
                "run nobody is discarding",
            Regex("""if \(discardArmed\)""").containsMatchIn(body),
        )
    }

    @Test
    fun `the arm lapses on its own and a landed sync retires it`() {
        val body = postRun()
        assertTrue(
            "a watch put down while armed must not be found later with a destructive " +
                "control one tap from firing",
            Regex("""delay\(CONFIRM_WINDOW_MS\)""").containsMatchIn(body),
        )
        assertTrue(
            "the armed confirm must not outlive the unsynced state it guards — once " +
                "the run has reached Supabase the local copy is no longer the only one",
            Regex("""val discardArmed = discardArmedAtMs != null && !synced""")
                .containsMatchIn(body),
        )
    }
}
