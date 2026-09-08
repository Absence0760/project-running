package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard over the two things the PreRun top arc could not say:
/// that the last drain pass stopped (decisions § 1390), and that what stopped
/// it was a session no retry can renew (decisions § 1544).
///
/// `syncFault` renders on `PostRunScreen` alone, and `startNextRun` clears it —
/// so on the screen a runner is on for every drain but the first, a 5xx or a
/// dead socket looked exactly like a successful sync of nothing: the count did
/// not fall, `drainBackoff` was armed behind it, and no surface named a reason.
///
/// Compose wiring is not host-JVM testable without Robolectric, which this
/// module avoids, so this is a source grep per the module's convention
/// (`PreRunRejectedQueueTest`, `ScreenWiringTest`). The behaviour underneath —
/// which classifications count as transient — is real unit coverage in
/// `DrainQueueLoopTest`; this file pins only that the verdict reaches the wrist
/// and survives the trip through PostRun.
class PreRunSyncFailureTest {

    private val ui: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    private val strings: String = File("src/main/res/values/strings.xml").readText()

    /// A named declaration's body, from its signature to the next one at the
    /// same indent — so nothing below can satisfy an assertion about it.
    private fun vmBody(signature: String): String {
        val start = vm.indexOf(signature)
        assertTrue("`$signature` is gone or renamed — this guard reads nothing", start >= 0)
        val end = vm.indexOf("\n\n    ", start)
        assertTrue("could not find the end of `$signature`", end > start)
        return vm.substring(start, end)
    }

    /// The counted-chip arm of the top-arc `when`, on its own: from its own
    /// label to the next one. Read branch-scoped so a match from the
    /// unreadable or rejected chip above cannot satisfy an assertion about
    /// this one.
    private fun countedBranch(): String {
        val start = ui.indexOf("SyncChipState.Queued, SyncChipState.RetryQueued -> {")
        assertTrue("the counted `Sync N` arm is gone or renamed", start >= 0)
        val end = ui.indexOf("\n                SyncChipState.", start + 1)
        assertTrue("could not find the end of the counted arm", end > start)
        val body = ui.substring(start, end)
        assertTrue(
            "the extracted arm does not render the count at all — the extraction is " +
                "wrong, and every assertion below would pass vacuously",
            body.contains("R.string.sync_count"),
        )
        return body
    }

    /// The sign-in arm of the same `when`, extracted the same way, so a match
    /// from the arms above or below cannot satisfy an assertion about it.
    private fun signInBranch(): String {
        val start = ui.indexOf("SyncChipState.SignInRequired -> {")
        assertTrue("the sign-in arm is gone or renamed", start >= 0)
        val end = ui.indexOf("\n                SyncChipState.", start + 1)
        assertTrue("could not find the end of the sign-in arm", end > start)
        val body = ui.substring(start, end)
        assertTrue(
            "the extracted arm renders no chip at all — the extraction is wrong, and " +
                "every assertion below would pass vacuously",
            body.contains("CompactChip("),
        )
        return body
    }

    @Test
    fun `the drain records a transient failure as a standing fact, not as the banner`() {
        // `lastFault` is about the PASS — a trailing success clears it, and so
        // does `startNextRun`. `blockedBy` is about the QUEUE, which is the
        // lifetime this surface needs. The same split § 1347 drew for the
        // permanently-rejected ids.
        val drain = vmBody("private suspend fun drainQueueLocked(")
        assertTrue(
            "the drain must publish the pass's own transient verdict — deriving it " +
                "from `lastFault` would raise the notice for a permanent rejection too, " +
                "and clear it on any trailing success",
            Regex("""syncBlockedBy = result\.blockedBy""").containsMatchIn(drain),
        )
        assertTrue(
            "RunUiState must carry it as a FAULT, or the arc cannot tell a 5xx the " +
                "runner retries from a session the server will not renew — the two " +
                "were one boolean, and the chip offered a retry for both",
            Regex("""val syncBlockedBy: SyncFault\?""").containsMatchIn(vm),
        )
    }

    @Test
    fun `leaving PostRun does not take the notice with it`() {
        // This is the whole defect in one line. `startNextRun` clears
        // `syncFault` because the banner belongs to the run just finished; if
        // it cleared this too, the runner would land on PreRun with a count
        // that will not fall and nothing saying why — which is the state that
        // was shipped.
        val next = vmBody("fun startNextRun()")
        assertTrue("the reset must still clear the PostRun banner", next.contains("syncFault = null"))
        assertFalse(
            "`startNextRun` must NOT reset the transient-failure notice: PreRun is the " +
                "screen the runner reaches through it, and clearing it here is exactly " +
                "how the arc went silent for every drain but the first",
            next.contains("syncBlockedBy"),
        )
    }

    @Test
    fun `the failure is said on the Sync chip and does not take its slot`() {
        val body = countedBranch()
        assertTrue(
            "the counted arm must read the transient verdict — a slot of its own would " +
                "take the arc from the retry in order to explain why a retry is " +
                "needed, and Sync is still the useful affordance during a transient. " +
                "`syncChipState` folds the two into one arm for that reason; " +
                "`SyncChipStateTest` evaluates which of them a given state is",
            body.contains("syncSlot == SyncChipState.RetryQueued"),
        )
        assertTrue(
            "…and the chip must still fire the drain in that state",
            body.contains("onClick = onSync"),
        )
        assertTrue(
            "the failed state must change the LABEL. Colour alone is not a signal — the " +
                "rule this arc already follows for the unreadable chip (§ 1104)",
            body.contains("R.string.sync_retry_count"),
        )
        assertTrue(
            "…and it must still be able to render the ordinary label, or the chip claims " +
                "a failure that is over",
            body.contains("R.string.sync_count"),
        )
    }

    @Test
    fun `both states announce themselves, and not with the same sentence`() {
        val body = countedBranch()
        // The 100 dp label cannot hold either sentence and the warning colour
        // announces nothing at all, so the content description is the only
        // place the reason can live for a TalkBack user.
        assertTrue(
            "the chip must carry a contentDescription",
            Regex("""\.semantics \{ contentDescription = """).containsMatchIn(body),
        )
        assertTrue(
            "the failed state needs its own announcement",
            body.contains("R.plurals.cd_sync_failed_retry"),
        )
        assertTrue(
            "and so does the ordinary one, or the two read identically to TalkBack",
            body.contains("R.plurals.cd_sync_queued"),
        )
        for (key in listOf("sync_retry_count", "cd_sync_failed_retry", "cd_sync_queued")) {
            assertTrue(
                "values/strings.xml must declare $key",
                strings.contains("name=\"$key\""),
            )
        }
    }

    @Test
    fun `a disabled chip is never labelled Retry`() {
        val body = countedBranch()
        // Offline the chip is already disabled, and the disabled state is the
        // honest signal there. Dimming a control that says "Retry" invites a
        // tap that cannot fire — and the network coming back re-raises the
        // label on its own, because the flag survives until a pass clears it.
        assertTrue(
            "the failed label must come off the resolved slot, which is where the " +
                "`online` conjunction now lives — deciding it again here would be a " +
                "second copy of the rule and only one of them is under test",
            Regex("""syncFailedNow = syncSlot == SyncChipState\.RetryQueued""")
                .containsMatchIn(body),
        )
        assertTrue(
            "the chip must still be gated on the network and the session — this one " +
                "uploads, unlike the unreadable chip's local file read",
            body.contains("enabled = online && authed && !syncing"),
        )
    }

    @Test
    fun `the one fault a retry cannot clear offers the sign-in instead`() {
        val body = signInBranch()
        // The defect in one arm. `classifyDrainError` reads a 401 as
        // `RetryAfterRefresh`, so a refresh the server refuses ends the pass
        // on `SignInRequired` — and the counted chip then read "Retry N",
        // enabled, firing, re-running the same drain and failing the same
        // refresh on every tap.
        assertTrue(
            "the sign-in arm must route to the sign-in screen — firing the drain here " +
                "is the tap that can never succeed",
            body.contains("onClick = onSignIn"),
        )
        assertFalse("…and must not fire the drain", body.contains("onClick = onSync"))
        assertTrue(
            "the label must be the sign-in one. Colour alone is not a signal — the rule " +
                "this arc already follows for the unreadable chip (§ 1104)",
            body.contains("R.string.sign_in"),
        )
        assertFalse(
            "…and must not be a counted label, which is the sentence being corrected",
            body.contains("R.string.sync_count") || body.contains("R.string.sync_retry_count"),
        )
        assertTrue(
            "the 100 dp label cannot hold the reason and the warning colour announces " +
                "nothing, so the content description is the only place the sentence and " +
                "the count can both live",
            body.contains("R.plurals.cd_sync_sign_in_required"),
        )
        assertTrue(
            "values/strings.xml must declare cd_sync_sign_in_required",
            strings.contains("name=\"cd_sync_sign_in_required\""),
        )
    }
}
