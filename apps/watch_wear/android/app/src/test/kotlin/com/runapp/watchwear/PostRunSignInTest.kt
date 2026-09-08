package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard over the fault `PostRunScreen` could state and not act
/// on (decisions § 1545).
///
/// `SyncFault.SignInRequired` renders there as "Sign in again to sync", and
/// the screen carried no sign-in: the only route to one was the Next button,
/// which the sentence does not name and which costs the runner the summary of
/// the run they had just finished. The Sync button beside it stayed the
/// primary action and could not succeed.
///
/// Compose wiring is not host-JVM testable without Robolectric, which this
/// module avoids, so this is a source grep per the module's convention
/// (`PreRunSyncFailureTest`, `PreRunRejectedQueueTest`, `ScreenWiringTest`).
class PostRunSignInTest {

    private val ui: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    /// A named declaration's body, from its signature to the next one at the
    /// same indent — so nothing below can satisfy an assertion about it.
    private fun vmBody(signature: String): String {
        val start = vm.indexOf(signature)
        assertTrue("`$signature` is gone or renamed — this guard reads nothing", start >= 0)
        val end = vm.indexOf("\n\n    ", start)
        assertTrue("could not find the end of `$signature`", end > start)
        return vm.substring(start, end)
    }

    private fun postRunBody(): String {
        val start = ui.indexOf("private fun PostRunScreen(")
        assertTrue("`PostRunScreen` is gone or renamed", start >= 0)
        val end = ui.indexOf("\nprivate fun ", start + 1)
        assertTrue("could not find the end of `PostRunScreen`", end > start)
        val body = ui.substring(start, end)
        assertTrue(
            "the extracted screen renders no sync banner — the extraction is wrong " +
                "and every assertion below would pass vacuously",
            body.contains("syncFaultMessage(syncFault)"),
        )
        return body
    }

    /// The call the stage dispatcher makes, so an argument asserted here is
    /// the one PostRun actually receives and not PreRun's identically-named
    /// neighbour.
    private fun postRunCall(): String {
        val start = ui.indexOf("Stage.PostRun -> PostRunScreen(")
        assertTrue("the PostRun stage no longer renders PostRunScreen", start >= 0)
        val end = ui.indexOf("\n                Stage.", start + 1)
        assertTrue("could not find the end of the PostRun call", end > start)
        return ui.substring(start, end)
    }

    @Test
    fun `the screen the sign-in fault renders on can reach a sign-in`() {
        val body = postRunBody()
        assertTrue(
            "PostRun states `SyncFault.SignInRequired` and offers no way to act on " +
                "it — the banner names a remedy that lives two screens away and does " +
                "not say so",
            body.contains("onClick = onSignIn"),
        )
        val call = postRunCall()
        assertTrue(
            "the sign-in must be wired to the view model, or the control is a " +
                "no-op: ${'$'}call",
            call.contains("onSignIn = vm::openSignIn"),
        )
        assertTrue(
            "the screen must be told whether there is a session at all: ${'$'}call",
            call.contains("authed = state.authed"),
        )
    }

    @Test
    fun `the sign-in replaces the primary action rather than joining it`() {
        val body = postRunBody()
        val start = body.indexOf("if (needsSignIn")
        assertTrue("PostRun no longer branches on a sign-in state", start >= 0)
        val end = body.indexOf("\n            } else {", start)
        assertTrue("could not find the end of the sign-in branch", end > start)
        val branch = body.substring(start, end)
        assertTrue("the branch renders no control", branch.contains("CompactChip("))
        assertFalse(
            "the sign-in branch must not also offer the drain: a Sync that cannot " +
                "get through is exactly what this state replaces",
            branch.contains("onClick = onSync"),
        )
        assertTrue(
            "the control must announce itself as the sign-in — the chip's own label " +
                "is a phrase in most locales and ellipsises",
            branch.contains("contentDescription = primaryCd"),
        )
    }

    @Test
    fun `both states with no usable session resolve to the sign-in`() {
        val body = postRunBody()
        val line = body.lineSequence().first { it.contains("val needsSignIn") }
        assertTrue(
            "the sign-in must answer the fault the banner states: ${'$'}line",
            line.contains("SyncFault.SignInRequired"),
        )
        assertTrue(
            "…and the plainer case with it. A run recorded signed-out queues " +
                "locally and `drainQueue` returns before reading anything without a " +
                "session, so the Sync button spins for the auth-wait and reports " +
                "nothing: ${'$'}line",
            line.contains("!authed"),
        )
        assertTrue(
            "…and neither may claim a run that has already landed: ${'$'}line",
            line.contains("!synced"),
        )
    }

    @Test
    fun `signing in returns to the screen it was opened from`() {
        // The reason the return stage exists. A runner who signs in from
        // PostRun is signing in to upload the run PostRun is showing, and
        // landing on PreRun throws that summary away at the exact moment the
        // sign-in made it uploadable — while `signInWithEmailInternal` forces
        // the drain that fills in "Synced".
        val open = vmBody("fun openSignIn()")
        assertTrue(
            "`openSignIn` must record where it was opened from, or the return is a " +
                "guess: ${'$'}open",
            open.contains("signInReturnStage = from"),
        )
        for (signature in listOf("fun cancelSignIn()", "fun signInWithEmail(")) {
            val body = vmBody(signature)
            assertTrue(
                "`$signature` must leave for the recorded stage: ${'$'}body",
                body.contains("stageAfterSignIn()"),
            )
            assertFalse(
                "`$signature` must not hardcode PreRun — that is the line that " +
                    "discards a PostRun summary: ${'$'}body",
                body.contains("stage = Stage.PreRun"),
            )
        }
    }

    @Test
    fun `the return does not overrule a stage something else has moved on`() {
        // A restore, not a claim. If the recording service has brought a run
        // back while the runner was typing, the stage it set stands.
        val resolver = vmBody("private fun stageAfterSignIn()")
        assertTrue(
            "`stageAfterSignIn` must check it is still on the sign-in screen: " +
                "${'$'}resolver",
            resolver.contains("_state.value.stage == Stage.SignIn"),
        )
    }
}
