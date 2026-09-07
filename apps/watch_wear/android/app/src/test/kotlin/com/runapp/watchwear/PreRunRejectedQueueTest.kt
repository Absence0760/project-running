package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard over the PreRun chip that reports the queue entries the
/// server has permanently refused, and over the discard behind it
/// (decisions § 1347).
///
/// The two halves it pins are the two halves of the defect. A permanently
/// rejected run stays queued by design, so without a surface the runner sees a
/// count that never falls and a Sync that reports success on every tap; and the
/// only remedy is destructive, so the surface must not fire on one press and
/// must not act on the queue at large — a run saved since the last drain pass
/// has never been tried, and taking it with the stuck ones would destroy a run
/// nobody judged.
///
/// Compose wiring is not host-JVM testable without Robolectric, which this
/// module avoids, so this is a source grep per the module's convention
/// (`PostRunDiscardConfirmTest`, `ScreenWiringTest`). The behaviour underneath
/// — which ids a pass rejects and which survive to the next one — is real unit
/// coverage in `DrainQueueLoopTest`; this file pins only the wiring those
/// values reach the wrist through.
class PreRunRejectedQueueTest {

    private val ui: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    /// The PreRunScreen body, from its signature to the next top-level
    /// declaration — so nothing below can satisfy an assertion about it.
    private fun preRun(): String {
        val start = ui.indexOf("private fun PreRunScreen(")
        assertTrue("PreRunScreen is gone or renamed — this guard reads nothing", start >= 0)
        val end = ui.indexOf("\nprivate fun ", start + 1)
        assertTrue("could not find the end of PreRunScreen", end > start)
        val body = ui.substring(start, end)
        assertTrue(
            "the extracted body does not mention the rejected-queue discard at all — the " +
                "extraction is wrong, and every assertion below would pass vacuously",
            body.contains("onDiscardRejected"),
        )
        return body
    }

    @Test
    fun `the rejected chip takes the slot ahead of the counted one`() {
        val body = preRun()
        // Both are arms of the one if/else chain on the top arc, so their order
        // in source IS their precedence. The counted chip's claim is the thing
        // this state makes false — it offers a Sync that always reports success
        // while the count it states never falls — so it must not win the slot.
        val rejected = body.indexOf("} else if (rejectedCount > 0")
        val counted = body.indexOf("} else if (queuedCount > 0)")
        assertTrue(
            "the rejected-queue branch is not an `else if` arm of the top-arc chain — " +
                "a separate `if` would render BOTH chips and push the arc into Start",
            rejected >= 0,
        )
        assertTrue(
            "the counted `Sync N` branch is gone or is no longer an `else if` arm — " +
                "re-point this guard at whatever now decides the slot",
            counted >= 0,
        )
        assertTrue(
            "the counted chip must yield the slot to the rejected one, not the other " +
                "way round: `Sync N` reports success on every tap for a queue that " +
                "cannot move",
            rejected < counted,
        )
    }

    @Test
    fun `the destructive callback is reachable only from the confirmed branch`() {
        val body = preRun()
        // Anchored on the CALL rather than on the chip, so the guard stays true
        // if the control is restyled, relabelled or moved on the arc.
        val calls = Regex("""onDiscardRejected\(\)""").findAll(body).count()
        assertEquals(
            "`onDiscardRejected()` must be called from exactly one place in " +
                "PreRunScreen — a second call site is the defect wearing a guard",
            1,
            calls,
        )
        assertTrue(
            "the one call must sit in the CONFIRMED branch: a first press has to arm " +
                "and do nothing else",
            Regex("""ConfirmPress\.Confirmed\s*->\s*\{[^}]*onDiscardRejected\(\)""")
                .containsMatchIn(body),
        )
        assertTrue(
            "no control may bind the destructive callback directly — that is the " +
                "single-tap discard this guard exists to refuse",
            !Regex("""onClick\s*=\s*onDiscardRejected\b""").containsMatchIn(body),
        )
    }

    @Test
    fun `the arm states the count, names the stake, and lapses on its own`() {
        val body = preRun()
        assertTrue(
            "the armed label must carry the count — the runner is agreeing to a " +
                "number, and a bare `Discard?` on a chip that said `2 can't sync` " +
                "leaves them confirming they know not what",
            body.contains("R.string.sync_rejected_discard"),
        )
        assertTrue(
            "the arm must name the stake: these runs are not saved anywhere else",
            Regex("""if \(armed\) \{[^}]*R\.string\.discard_stake""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(body),
        )
        assertTrue(
            "the confirm must announce itself to TalkBack too — the unarmed chip and " +
                "the armed one would otherwise read identically",
            body.contains("R.plurals.cd_sync_rejected_confirm"),
        )
        assertTrue(
            "a watch put down while armed must not be found later with a destructive " +
                "control one tap from firing",
            Regex("""delay\(CONFIRM_WINDOW_MS\)""").containsMatchIn(body),
        )
        assertTrue(
            "a drain landing between the arm and the confirm changes WHICH runs the " +
                "second tap destroys — the arm has to lapse on the count, not commit " +
                "to a set the runner never saw",
            Regex("""LaunchedEffect\(rejectedCount\)""").containsMatchIn(body),
        )
    }

    /// A named declaration's body, from its signature to the next one at the
    /// same indent — so nothing below can satisfy an assertion about it.
    private fun vmBody(signature: String): String {
        val start = vm.indexOf(signature)
        assertTrue("`$signature` is gone or renamed — this guard reads nothing", start >= 0)
        val end = vm.indexOf("\n\n    ", start)
        assertTrue("could not find the end of `$signature`", end > start)
        return vm.substring(start, end)
    }

    @Test
    fun `the discard acts on the judged ids and never on the queue at large`() {
        val body = vmBody("fun discardRejectedRuns()")
        assertTrue(
            "the discard must take the ids the last drain pass judged. Acting on the " +
                "queue as it stands would take a run saved since that pass — one " +
                "nothing has tried, let alone refused — with the stuck ones",
            Regex("""val ids = _state\.value\.rejectedRunIds""").containsMatchIn(body),
        )
        assertTrue(
            "and it must be that set the drop iterates. Reading the queue again here " +
                "is the same defect one line further down",
            Regex("""for \(id in ids\)[\s\S]{0,80}?dropQueuedRun\(id""").containsMatchIn(body),
        )
        assertTrue(
            "`store.clear()` wipes the whole queue including its track files; this " +
                "path may only remove the entries it names",
            !body.contains("store.clear()"),
        )
    }

}
